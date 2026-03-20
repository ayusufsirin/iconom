#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-px4-offboard-movement.log"
OFFBOARD_LOG="${ROOT_DIR}/.tmp-offboard-movement-publisher.log"
ARM_LOG="${ROOT_DIR}/.tmp-offboard-movement-arm.log"
MODE_LOG="${ROOT_DIR}/.tmp-offboard-movement-mode.log"
STATUS_LOG="${ROOT_DIR}/.tmp-offboard-movement-status.log"
POSITION_LOG="${ROOT_DIR}/.tmp-offboard-movement-position.log"
PX4_PID=""
OFFBOARD_PID=""

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
  if [[ -n "${OFFBOARD_PID}" ]] && kill -0 "${OFFBOARD_PID}" >/dev/null 2>&1; then
    kill "${OFFBOARD_PID}" >/dev/null 2>&1 || true
    wait "${OFFBOARD_PID}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PX4_PID}" ]] && kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    kill "${PX4_PID}" >/dev/null 2>&1 || true
    wait "${PX4_PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${PX4_LOG}" "${OFFBOARD_LOG}" "${ARM_LOG}" "${MODE_LOG}" "${STATUS_LOG}" "${POSITION_LOG}"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

require_cmd docker

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "offboard movement check requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 121
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "offboard movement check requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 122
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
USE_GUI="${ICONOM_USE_GUI:-0}"

if [[ "${USE_GUI}" == "1" || "${PX4_HEADLESS:-1}" == "0" ]]; then
  require_file "${OVERRIDE_FILE}"

  if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; GUI offboard movement requires a local X11 display" >&2
    exit 133
  fi

  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

trap cleanup EXIT

COMMAND_TOPIC="${PX4_COMMAND_TOPIC:-/plane_01/fmu/in/vehicle_command}"
COMMAND_ACK_TOPIC="${PX4_COMMAND_ACK_TOPIC:-/plane_01/fmu/out/vehicle_command_ack}"
STATUS_TOPIC="${PX4_VEHICLE_STATUS_TOPIC:-/plane_01/fmu/out/vehicle_status_v1}"
LOCAL_POSITION_TOPIC="${PX4_LOCAL_POSITION_TOPIC:-/plane_01/fmu/out/vehicle_local_position}"
OFFBOARD_CONTROL_MODE_TOPIC="${PX4_OFFBOARD_CONTROL_MODE_TOPIC:-/plane_01/fmu/in/offboard_control_mode}"
VEHICLE_RATES_SETPOINT_TOPIC="${PX4_VEHICLE_RATES_SETPOINT_TOPIC:-/plane_01/fmu/in/vehicle_rates_setpoint}"
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-45}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-20}"
OFFBOARD_READY_TIMEOUT_SEC="${PX4_OFFBOARD_READY_TIMEOUT_SEC:-20}"
OFFBOARD_STREAM_SETTLE_SEC="${PX4_OFFBOARD_STREAM_SETTLE_SEC:-3}"
OFFBOARD_RUN_DURATION_SEC="${PX4_OFFBOARD_RUN_DURATION_SEC:-20}"
OFFBOARD_THRUST_X="${PX4_OFFBOARD_THRUST_X:-0.7}"
LOCAL_POSITION_TIMEOUT_SEC="${PX4_LOCAL_POSITION_TIMEOUT_SEC:-30}"
EXPECTED_MIN_DELTA_XY_NORM="${PX4_EXPECTED_MIN_DELTA_XY_NORM:-5.0}"

echo "iconom offboard movement check"
echo "status topic: ${STATUS_TOPIC}"
echo "local position topic: ${LOCAL_POSITION_TOPIC}"
echo "offboard control mode topic: ${OFFBOARD_CONTROL_MODE_TOPIC}"
echo "vehicle rates setpoint topic: ${VEHICLE_RATES_SETPOINT_TOPIC}"
echo "thrust command: x=${OFFBOARD_THRUST_X}"
echo "gui mode: ${USE_GUI}"
echo
echo "this checks the first ROS-side offboard movement slice:"
echo "  - PX4 runtime starts"
echo "  - ROS arms the aircraft"
echo "  - ROS enters OFFBOARD with a body-rate plus thrust stream"
echo "  - VehicleLocalPosition shows bounded planar movement"
echo "  - VehicleStatus remains in OFFBOARD"
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
    echo "${service} did not reach running state before offboard movement check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 123
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

echo "step 7: polling ROS 2 graph for offboard topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before offboard movement topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    cat "${PX4_LOG}" >&2 || true
    exit 124
  fi

  TOPICS="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${COMMAND_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${COMMAND_ACK_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${STATUS_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${LOCAL_POSITION_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${OFFBOARD_CONTROL_MODE_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${VEHICLE_RATES_SETPOINT_TOPIC}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

echo "step 8: waiting for preflight-ready VehicleStatus"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${OFFBOARD_READY_TIMEOUT_SEC}'
  export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='true'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not report preflight-ready state before offboard movement" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 125
fi

echo "step 9: arming through the validated command path"
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
  echo "the arm command did not succeed before offboard movement validation" >&2
  cat "${ARM_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 126
fi

echo "step 10: waiting for armed VehicleStatus"
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
  echo "VehicleStatus did not report armed state before offboard movement" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 127
fi

echo "step 11: starting offboard movement publisher in the background"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_OFFBOARD_CONTROL_MODE_TOPIC='${OFFBOARD_CONTROL_MODE_TOPIC}'
  export PX4_VEHICLE_RATES_SETPOINT_TOPIC='${VEHICLE_RATES_SETPOINT_TOPIC}'
  export PX4_OFFBOARD_RUN_DURATION_SEC='${OFFBOARD_RUN_DURATION_SEC}'
  export PX4_OFFBOARD_THRUST_X='${OFFBOARD_THRUST_X}'
  ros2 run iconom_control offboard_rate_thrust_publisher
" >"${OFFBOARD_LOG}" 2>&1 &
OFFBOARD_PID=$!

echo "step 12: letting the offboard stream settle for ${OFFBOARD_STREAM_SETTLE_SEC}s"
sleep "${OFFBOARD_STREAM_SETTLE_SEC}"

if [[ -n "${OFFBOARD_PID}" ]] && ! kill -0 "${OFFBOARD_PID}" >/dev/null 2>&1; then
  OFFBOARD_EXIT=0
  wait "${OFFBOARD_PID}" || OFFBOARD_EXIT=$?
  echo "offboard movement publisher exited before mode switch" >&2
  cat "${OFFBOARD_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 128
fi

echo "step 13: requesting OFFBOARD mode"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='mode_offboard'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${MODE_LOG}" 2>&1; then
  echo "the offboard mode command did not receive an accepted ack" >&2
  cat "${MODE_LOG}" >&2 || true
  cat "${OFFBOARD_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 129
fi

echo "step 14: waiting for VehicleStatus.nav_state=OFFBOARD"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='14'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not reach OFFBOARD nav_state during movement validation" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${MODE_LOG}" >&2 || true
  cat "${OFFBOARD_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 130
fi

echo "step 15: waiting for the commanded local-position response"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_LOCAL_POSITION_TOPIC='${LOCAL_POSITION_TOPIC}'
  export PX4_LOCAL_POSITION_TIMEOUT_SEC='${LOCAL_POSITION_TIMEOUT_SEC}'
  export PX4_MIN_DELTA_XY_NORM='${EXPECTED_MIN_DELTA_XY_NORM}'
  ros2 run iconom_control vehicle_local_position_waiter
" >"${POSITION_LOG}" 2>&1; then
  echo "VehicleLocalPosition did not show the expected offboard movement response" >&2
  cat "${POSITION_LOG}" >&2 || true
  cat "${OFFBOARD_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 131
fi

echo "step 16: confirming VehicleStatus remains in OFFBOARD after movement"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='14'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not remain in OFFBOARD after movement validation" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${POSITION_LOG}" >&2 || true
  cat "${OFFBOARD_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 132
fi

echo "offboard movement is alive"
cat "${ARM_LOG}"
cat "${MODE_LOG}"
cat "${POSITION_LOG}"
cat "${STATUS_LOG}"
