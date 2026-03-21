#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-px4-command.log"
COMMAND_LOG="${ROOT_DIR}/.tmp-vehicle-command.log"
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
  rm -f "${PX4_LOG}" "${COMMAND_LOG}"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

require_cmd docker

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

OVERRIDE_PX4_COMMAND_NAME="${PX4_COMMAND_NAME-}"
OVERRIDE_PX4_COMMAND_TIMEOUT_SEC="${PX4_COMMAND_TIMEOUT_SEC-}"
OVERRIDE_PX4_COMMAND_DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC-}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ -n "${OVERRIDE_PX4_COMMAND_NAME}" ]]; then
  PX4_COMMAND_NAME="${OVERRIDE_PX4_COMMAND_NAME}"
fi

if [[ -n "${OVERRIDE_PX4_COMMAND_TIMEOUT_SEC}" ]]; then
  PX4_COMMAND_TIMEOUT_SEC="${OVERRIDE_PX4_COMMAND_TIMEOUT_SEC}"
fi

if [[ -n "${OVERRIDE_PX4_COMMAND_DISCOVERY_WAIT_SEC}" ]]; then
  PX4_COMMAND_DISCOVERY_WAIT_SEC="${OVERRIDE_PX4_COMMAND_DISCOVERY_WAIT_SEC}"
fi

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "vehicle command check requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 91
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "vehicle command check requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 92
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
trap cleanup EXIT

COMMAND_TOPIC="${PX4_COMMAND_TOPIC:-/plane_01/fmu/in/vehicle_command}"
COMMAND_ACK_TOPIC="${PX4_COMMAND_ACK_TOPIC:-/plane_01/fmu/out/vehicle_command_ack}"
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-45}"
PRE_COMMAND_DELAY_SEC="${PX4_COMMAND_PRE_DELAY_SEC:-0}"

echo "iconom vehicle command check"
echo "command action: ${PX4_COMMAND_NAME:-disarm}"
echo "command topic target: ${COMMAND_TOPIC}"
echo "ack topic target: ${COMMAND_ACK_TOPIC}"
echo "pre-command delay: ${PRE_COMMAND_DELAY_SEC}s"
echo
echo "this checks the first ROS-side control slice:"
echo "  - PX4 runtime starts against the existing xrce_agent path"
echo "  - ROS 2 can see the command and ack topics"
echo "  - a repo-owned node publishes one VehicleCommand"
echo "  - PX4 returns a VehicleCommandAck"
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, xrce_agent, ros2_app, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo xrce_agent ros2_app px4

echo "step 4: starting gazebo, xrce_agent, and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in gazebo xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before vehicle command check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 93
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
  set +u
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  ros2 interface show px4_msgs/msg/VehicleCommand >/dev/null
'

echo "step 6: launching the current PX4 runtime path in the background"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  -e PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG}" 2>&1 &
PX4_PID=$!

echo "step 7: polling ROS 2 graph for command topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before command topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    cat "${PX4_LOG}" >&2 || true
    exit 94
  fi

  TOPICS="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${COMMAND_TOPIC}" <<<"${TOPICS}" && grep -qx "${COMMAND_ACK_TOPIC}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

if [[ "${PRE_COMMAND_DELAY_SEC}" != "0" ]]; then
  echo "step 7b: waiting ${PRE_COMMAND_DELAY_SEC}s before publishing the command"
  sleep "${PRE_COMMAND_DELAY_SEC}"
fi

echo "step 8: running the ROS vehicle command client"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='${PX4_COMMAND_NAME:-disarm}'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${COMMAND_LOG}" 2>&1; then
  echo "the ROS vehicle command client did not receive an accepted ack" >&2
  echo "--- command client log ---" >&2
  cat "${COMMAND_LOG}" >&2 || true
  echo "--- px4 runtime log ---" >&2
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 95
fi

echo "vehicle command roundtrip is alive"
cat "${COMMAND_LOG}"
