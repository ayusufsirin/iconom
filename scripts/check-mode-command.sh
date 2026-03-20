#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-px4-mode.log"
ARM_LOG="${ROOT_DIR}/.tmp-arm-command.log"
MODE_LOG="${ROOT_DIR}/.tmp-mode-command.log"
STATUS_LOG="${ROOT_DIR}/.tmp-vehicle-status.log"
PX4_PID=""

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 2
  fi
}

cleanup() {
  if [[ -n "${PX4_PID}" ]] && kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    kill "${PX4_PID}" >/dev/null 2>&1 || true
    wait "${PX4_PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${PX4_LOG}" "${ARM_LOG}" "${MODE_LOG}" "${STATUS_LOG}"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

require_cmd docker

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

OVERRIDE_PX4_MODE_COMMAND_NAME="${PX4_MODE_COMMAND_NAME-}"
OVERRIDE_PX4_MODE_EXPECTED_NAV_STATE="${PX4_MODE_EXPECTED_NAV_STATE-}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ -n "${OVERRIDE_PX4_MODE_COMMAND_NAME}" ]]; then
  PX4_MODE_COMMAND_NAME="${OVERRIDE_PX4_MODE_COMMAND_NAME}"
fi

if [[ -n "${OVERRIDE_PX4_MODE_EXPECTED_NAV_STATE}" ]]; then
  PX4_MODE_EXPECTED_NAV_STATE="${OVERRIDE_PX4_MODE_EXPECTED_NAV_STATE}"
fi

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "mode command check requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 101
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "mode command check requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 102
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
trap cleanup EXIT

STATUS_TOPIC="${PX4_VEHICLE_STATUS_TOPIC:-/plane_01/fmu/out/vehicle_status_v1}"
COMMAND_TOPIC="${PX4_COMMAND_TOPIC:-/plane_01/fmu/in/vehicle_command}"
COMMAND_ACK_TOPIC="${PX4_COMMAND_ACK_TOPIC:-/plane_01/fmu/out/vehicle_command_ack}"
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-45}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-20}"
MODE_COMMAND_NAME="${PX4_MODE_COMMAND_NAME:-mode_loiter}"
EXPECTED_NAV_STATE="${PX4_MODE_EXPECTED_NAV_STATE:-4}"
ARM_READY_TIMEOUT_SEC="${PX4_ARM_READY_TIMEOUT_SEC:-30}"

echo "iconom mode command check"
echo "mode command: ${MODE_COMMAND_NAME}"
echo "expected nav_state: ${EXPECTED_NAV_STATE}"
echo "status topic: ${STATUS_TOPIC}"
echo
echo "this checks the first ROS-side mode slice:"
echo "  - PX4 runtime starts"
echo "  - ROS arms the aircraft"
echo "  - ROS publishes one mode command"
echo "  - PX4 acks the mode command"
echo "  - VehicleStatus reflects the expected nav_state"
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building xrce_agent, ros2_app, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent ros2_app px4

echo "step 4: starting xrce_agent and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before mode command check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 103
  fi
done

echo "step 5: building PX4 message and control packages"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc '
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  cd /workspaces/ros2_ws
  colcon build --merge-install --packages-up-to px4_msgs iconom_control
'

echo "step 6: launching the current PX4 runtime path in the background"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  -e PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG}" 2>&1 &
PX4_PID=$!

echo "step 7: polling ROS 2 graph for command and status topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before mode topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    cat "${PX4_LOG}" >&2 || true
    exit 104
  fi

  TOPICS="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${COMMAND_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${COMMAND_ACK_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${STATUS_TOPIC}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

echo "step 8: arming through the validated command path"
echo "step 8a: waiting for preflight-ready VehicleStatus"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${ARM_READY_TIMEOUT_SEC}'
  export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='true'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not report preflight-ready state before arming" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 105
fi

echo "step 8b: arming through the validated command path"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='arm'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${ARM_LOG}" 2>&1; then
  echo "the arm command did not succeed before mode validation" >&2
  cat "${ARM_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 106
fi

echo "step 9: waiting for armed VehicleStatus"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_ARMING_STATE='2'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not report armed state" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 107
fi

echo "step 10: publishing the mode command"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='${MODE_COMMAND_NAME}'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${MODE_LOG}" 2>&1; then
  echo "the mode command did not receive an accepted ack" >&2
  cat "${MODE_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 108
fi

echo "step 11: waiting for expected VehicleStatus.nav_state"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${EXPECTED_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not reach the expected nav_state" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 109
fi

echo "mode command roundtrip is alive"
cat "${ARM_LOG}"
cat "${MODE_LOG}"
cat "${STATUS_LOG}"
