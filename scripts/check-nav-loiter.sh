#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-px4-nav-loiter.log"
ARM_LOG="${ROOT_DIR}/.tmp-nav-loiter-arm.log"
TAKEOFF_LOG="${ROOT_DIR}/.tmp-nav-loiter-takeoff.log"
LOITER_LOG="${ROOT_DIR}/.tmp-nav-loiter-command.log"
STATUS_LOG="${ROOT_DIR}/.tmp-nav-loiter-status.log"
TAKEOFF_POSITION_LOG="${ROOT_DIR}/.tmp-nav-loiter-takeoff-position.log"
LOITER_POSITION_LOG="${ROOT_DIR}/.tmp-nav-loiter-position.log"
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
  rm -f \
    "${PX4_LOG}" \
    "${ARM_LOG}" \
    "${TAKEOFF_LOG}" \
    "${LOITER_LOG}" \
    "${STATUS_LOG}" \
    "${TAKEOFF_POSITION_LOG}" \
    "${LOITER_POSITION_LOG}"
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

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
USE_GUI="${ICONOM_USE_GUI:-0}"

if [[ "${USE_GUI}" == "1" || "${PX4_HEADLESS:-1}" == "0" ]]; then
  require_file "${OVERRIDE_FILE}"

  if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; GUI nav loiter requires a local X11 display" >&2
    exit 169
  fi

  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

trap cleanup EXIT

COMMAND_TOPIC="${PX4_COMMAND_TOPIC:-/plane_01/fmu/in/vehicle_command}"
COMMAND_ACK_TOPIC="${PX4_COMMAND_ACK_TOPIC:-/plane_01/fmu/out/vehicle_command_ack}"
STATUS_TOPIC="${PX4_VEHICLE_STATUS_TOPIC:-/plane_01/fmu/out/vehicle_status_v1}"
LOCAL_POSITION_TOPIC="${PX4_LOCAL_POSITION_TOPIC:-/plane_01/fmu/out/vehicle_local_position}"
GLOBAL_POSITION_TOPIC="${PX4_GLOBAL_POSITION_TOPIC:-/plane_01/fmu/out/vehicle_global_position}"
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-45}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-25}"
TAKEOFF_ALT_OFFSET_M="${PX4_TARGET_OFFSET_ALT_M:-30.0}"
TAKEOFF_NAV_STATE="${PX4_EXPECTED_TAKEOFF_NAV_STATE:-17}"
LOITER_NAV_STATE="${PX4_EXPECTED_LOITER_NAV_STATE:-4}"
TAKEOFF_MIN_DELTA_XY_NORM="${PX4_EXPECTED_TAKEOFF_MIN_DELTA_XY_NORM:-5.0}"
TAKEOFF_MAX_DELTA_Z="${PX4_EXPECTED_TAKEOFF_MAX_DELTA_Z:--0.5}"
LOITER_MIN_DELTA_XY_NORM="${PX4_EXPECTED_LOITER_MIN_DELTA_XY_NORM:-5.0}"
LOITER_RADIUS_M="${PX4_LOITER_RADIUS_M:-60.0}"

echo "iconom nav loiter check"
echo "command topic: ${COMMAND_TOPIC}"
echo "ack topic: ${COMMAND_ACK_TOPIC}"
echo "status topic: ${STATUS_TOPIC}"
echo "local position topic: ${LOCAL_POSITION_TOPIC}"
echo "global position topic: ${GLOBAL_POSITION_TOPIC}"
echo "takeoff altitude offset: ${TAKEOFF_ALT_OFFSET_M}m"
echo "loiter radius: ${LOITER_RADIUS_M}m"
echo "gui mode: ${USE_GUI}"
echo
echo "this checks the next PX4-native guidance slice:"
echo "  - PX4 runtime starts"
echo "  - ROS arms the aircraft"
echo "  - ROS sends NAV_TAKEOFF to get airborne"
echo "  - ROS sends mode_loiter after takeoff"
echo "  - VehicleStatus enters AUTO_LOITER"
echo "  - VehicleLocalPosition keeps moving while loiter is active"
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
    echo "${service} did not reach running state before nav loiter check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 161
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
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  -e PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG}" 2>&1 &
PX4_PID=$!

echo "step 7: polling ROS 2 graph for navigation topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before nav loiter topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    cat "${PX4_LOG}" >&2 || true
    exit 162
  fi

  TOPICS="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${COMMAND_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${COMMAND_ACK_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${STATUS_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${LOCAL_POSITION_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${GLOBAL_POSITION_TOPIC}" <<<"${TOPICS}"; then
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
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='true'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not report preflight-ready state before nav loiter" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 163
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
  echo "the arm command did not succeed before nav loiter validation" >&2
  cat "${ARM_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 164
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
  echo "VehicleStatus did not report armed state before nav loiter" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 165
fi

echo "step 11: sending NAV_TAKEOFF through the navigation client"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_GLOBAL_POSITION_TOPIC='${GLOBAL_POSITION_TOPIC}'
  export PX4_NAV_COMMAND_NAME='nav_takeoff'
  export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-20}'
  ros2 run iconom_control navigation_command_client
" >"${TAKEOFF_LOG}" 2>&1; then
  echo "the NAV_TAKEOFF command did not succeed before loiter" >&2
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 166
fi

echo "step 12: waiting for VehicleStatus.nav_state=AUTO_TAKEOFF"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${TAKEOFF_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not enter AUTO_TAKEOFF before loiter" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 167
fi

echo "step 13: waiting for takeoff motion in VehicleLocalPosition"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_LOCAL_POSITION_TOPIC='${LOCAL_POSITION_TOPIC}'
  export PX4_LOCAL_POSITION_TIMEOUT_SEC='${PX4_LOCAL_POSITION_TIMEOUT_SEC:-40}'
  export PX4_MIN_DELTA_XY_NORM='${TAKEOFF_MIN_DELTA_XY_NORM}'
  export PX4_MAX_DELTA_Z='${TAKEOFF_MAX_DELTA_Z}'
  ros2 run iconom_control vehicle_local_position_waiter
" >"${TAKEOFF_POSITION_LOG}" 2>&1; then
  echo "VehicleLocalPosition did not show takeoff motion before loiter" >&2
  cat "${TAKEOFF_POSITION_LOG}" >&2 || true
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 168
fi

echo "step 14: sending mode_loiter through the validated command path"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='mode_loiter'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${LOITER_LOG}" 2>&1; then
  echo "the mode_loiter command did not succeed" >&2
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 170
fi

echo "step 15: waiting for VehicleStatus.nav_state=AUTO_LOITER"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${LOITER_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not enter AUTO_LOITER after mode_loiter" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 171
fi

echo "step 16: waiting for continued movement while loiter is active"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_LOCAL_POSITION_TOPIC='${LOCAL_POSITION_TOPIC}'
  export PX4_LOCAL_POSITION_TIMEOUT_SEC='${PX4_LOCAL_POSITION_TIMEOUT_SEC:-40}'
  export PX4_MIN_DELTA_XY_NORM='${LOITER_MIN_DELTA_XY_NORM}'
  ros2 run iconom_control vehicle_local_position_waiter
" >"${LOITER_POSITION_LOG}" 2>&1; then
  echo "VehicleLocalPosition did not keep moving after mode_loiter" >&2
  cat "${LOITER_POSITION_LOG}" >&2 || true
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 172
fi

echo "step 17: confirming VehicleStatus remains AUTO_LOITER"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${LOITER_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not remain AUTO_LOITER after loiter motion" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 173
fi

echo "nav loiter guidance is alive"
cat "${TAKEOFF_LOG}"
cat "${TAKEOFF_POSITION_LOG}"
cat "${LOITER_LOG}"
cat "${LOITER_POSITION_LOG}"
