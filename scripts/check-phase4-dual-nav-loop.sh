#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
PX4_LOG_1="${ROOT_DIR}/.tmp-phase4-dual-nav-px4-plane01.log"
PX4_LOG_2="${ROOT_DIR}/.tmp-phase4-dual-nav-px4-plane02.log"
PX4_PID_1=""
PX4_PID_2=""

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
  if [[ -n "${PX4_PID_1}" ]] && kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
    kill "${PX4_PID_1}" >/dev/null 2>&1 || true
    wait "${PX4_PID_1}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PX4_PID_2}" ]] && kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
    kill "${PX4_PID_2}" >/dev/null 2>&1 || true
    wait "${PX4_PID_2}" >/dev/null 2>&1 || true
  fi
  rm -f "${ROOT_DIR}"/.tmp-phase4-dual-nav-*.log
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_cmd docker
require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

USE_GUI="${ICONOM_USE_GUI:-0}"
if [[ "${USE_GUI}" == "1" || "${PX4_HEADLESS:-1}" == "0" ]]; then
  require_file "${OVERRIDE_FILE}"
  if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; GUI dual nav loop requires a local X11 display" >&2
    exit 229
  fi
  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

ros2_exec() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "$1"
}

run_status_waiter() {
  local namespace="$1"
  local status_topic="$2"
  local output_file="$3"
  local timeout_sec="$4"
  local arming_state="$5"
  local nav_state="$6"
  local preflight_flag="$7"

  local script="
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_VEHICLE_STATUS_TOPIC='${status_topic}'
    export PX4_STATUS_TIMEOUT_SEC='${timeout_sec}'
  "

  if [[ -n "${arming_state}" ]]; then
    script+="
export PX4_EXPECTED_ARMING_STATE='${arming_state}'"
  fi

  if [[ -n "${nav_state}" ]]; then
    script+="
export PX4_EXPECTED_NAV_STATE='${nav_state}'"
  fi

  if [[ -n "${preflight_flag}" ]]; then
    script+="
export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='${preflight_flag}'"
  fi

  script+="
ros2 run iconom_control vehicle_status_waiter"

  ros2_exec "${script}" >"${output_file}" 2>&1
}

run_vehicle_command() {
  local namespace="$1"
  local command_topic="$2"
  local ack_topic="$3"
  local command_name="$4"
  local target_system="$5"
  local output_file="$6"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_COMMAND_TOPIC='${command_topic}'
    export PX4_COMMAND_ACK_TOPIC='${ack_topic}'
    export PX4_COMMAND_NAME='${command_name}'
    export PX4_TARGET_SYSTEM='${target_system}'
    export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
    ros2 run iconom_control vehicle_command_client
  " >"${output_file}" 2>&1
}

run_navigation_command() {
  local namespace="$1"
  local command_topic="$2"
  local ack_topic="$3"
  local global_position_topic="$4"
  local command_name="$5"
  local target_system="$6"
  local output_file="$7"
  local extra_env="$8"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_COMMAND_TOPIC='${command_topic}'
    export PX4_COMMAND_ACK_TOPIC='${ack_topic}'
    export PX4_GLOBAL_POSITION_TOPIC='${global_position_topic}'
    export PX4_NAV_COMMAND_NAME='${command_name}'
    export PX4_TARGET_SYSTEM='${target_system}'
    export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-20}'
${extra_env}
    ros2 run iconom_control navigation_command_client
  " >"${output_file}" 2>&1
}

run_local_position_waiter() {
  local namespace="$1"
  local local_position_topic="$2"
  local output_file="$3"
  local timeout_sec="$4"
  local min_delta_xy_norm="$5"
  local max_delta_z="$6"
  local min_delta_z="$7"

  local script="
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_LOCAL_POSITION_TOPIC='${local_position_topic}'
    export PX4_LOCAL_POSITION_TIMEOUT_SEC='${timeout_sec}'
  "

  if [[ -n "${min_delta_xy_norm}" ]]; then
    script+="
export PX4_MIN_DELTA_XY_NORM='${min_delta_xy_norm}'"
  fi

  if [[ -n "${max_delta_z}" ]]; then
    script+="
export PX4_MAX_DELTA_Z='${max_delta_z}'"
  fi

  if [[ -n "${min_delta_z}" ]]; then
    script+="
export PX4_MIN_DELTA_Z='${min_delta_z}'"
  fi

  script+="
ros2 run iconom_control vehicle_local_position_waiter"

  ros2_exec "${script}" >"${output_file}" 2>&1
}

run_land_detected_waiter() {
  local namespace="$1"
  local topic="$2"
  local output_file="$3"
  local timeout_sec="$4"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_LAND_DETECTED_TOPIC='${topic}'
    export PX4_LAND_DETECTED_TIMEOUT_SEC='${timeout_sec}'
    export PX4_EXPECTED_LANDED='true'
    ros2 run iconom_control vehicle_land_detected_waiter
  " >"${output_file}" 2>&1
}

wait_for_topics() {
  local status_topic_1="$1"
  local status_topic_2="$2"
  local command_topic_1="$3"
  local command_topic_2="$4"
  local ack_topic_1="$5"
  local ack_topic_2="$6"
  local local_topic_1="$7"
  local local_topic_2="$8"
  local global_topic_1="$9"
  local global_topic_2="${10}"
  local land_topic_1="${11}"
  local land_topic_2="${12}"

  for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
    if [[ -n "${PX4_PID_1}" ]] && ! kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
      PX4_EXIT=0
      wait "${PX4_PID_1}" || PX4_EXIT=$?
      echo "plane_01 px4 runtime exited before topic discovery" >&2
      echo "plane_01 exit code: ${PX4_EXIT}" >&2
      cat "${PX4_LOG_1}" >&2 || true
      exit 112
    fi
    if [[ -n "${PX4_PID_2}" ]] && ! kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
      PX4_EXIT=0
      wait "${PX4_PID_2}" || PX4_EXIT=$?
      echo "plane_02 px4 runtime exited before topic discovery" >&2
      echo "plane_02 exit code: ${PX4_EXIT}" >&2
      cat "${PX4_LOG_2}" >&2 || true
      exit 113
    fi

    TOPICS="$(ros2_exec 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

    if grep -qx "${status_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${status_topic_2}" <<<"${TOPICS}" \
      && grep -qx "${command_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${command_topic_2}" <<<"${TOPICS}" \
      && grep -qx "${ack_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${ack_topic_2}" <<<"${TOPICS}" \
      && grep -qx "${local_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${local_topic_2}" <<<"${TOPICS}" \
      && grep -qx "${global_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${global_topic_2}" <<<"${TOPICS}" \
      && grep -qx "${land_topic_1}" <<<"${TOPICS}" \
      && grep -qx "${land_topic_2}" <<<"${TOPICS}"; then
      return 0
    fi

    sleep 1
  done

  echo "dual-aircraft nav topics did not appear before timeout" >&2
  exit 114
}

run_plane_loop() {
  local label="$1"
  local namespace="$2"
  local sysid="$3"
  local command_topic="$4"
  local ack_topic="$5"
  local status_topic="$6"
  local local_position_topic="$7"
  local global_position_topic="$8"
  local land_detected_topic="$9"

  local status_log="${ROOT_DIR}/.tmp-phase4-dual-nav-status-${label}.log"
  local arm_log="${ROOT_DIR}/.tmp-phase4-dual-nav-arm-${label}.log"
  local takeoff_log="${ROOT_DIR}/.tmp-phase4-dual-nav-takeoff-${label}.log"
  local loiter_log="${ROOT_DIR}/.tmp-phase4-dual-nav-loiter-${label}.log"
  local land_log="${ROOT_DIR}/.tmp-phase4-dual-nav-land-${label}.log"
  local takeoff_position_log="${ROOT_DIR}/.tmp-phase4-dual-nav-takeoff-position-${label}.log"
  local land_position_log="${ROOT_DIR}/.tmp-phase4-dual-nav-land-position-${label}.log"
  local land_detected_log="${ROOT_DIR}/.tmp-phase4-dual-nav-land-detected-${label}.log"

  echo "step: waiting for preflight-ready VehicleStatus on ${label}"
  if ! run_status_waiter "${namespace}" "${status_topic}" "${status_log}" "${STATUS_TIMEOUT_SEC}" '' '' 'true'; then
    echo "${label} did not report preflight-ready state" >&2
    cat "${status_log}" >&2 || true
    return 1
  fi

  echo "step: arming ${label}"
  if ! run_vehicle_command "${namespace}" "${command_topic}" "${ack_topic}" 'arm' "${sysid}" "${arm_log}"; then
    echo "${label} arm failed" >&2
    cat "${arm_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for armed VehicleStatus on ${label}"
  if ! run_status_waiter "${namespace}" "${status_topic}" "${status_log}" "${STATUS_TIMEOUT_SEC}" '2' '' ''; then
    echo "${label} did not report armed state" >&2
    cat "${status_log}" >&2 || true
    return 1
  fi

  echo "step: sending NAV_TAKEOFF to ${label}"
  if ! run_navigation_command "${namespace}" "${command_topic}" "${ack_topic}" "${global_position_topic}" 'nav_takeoff' "${sysid}" "${takeoff_log}" "export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'"; then
    echo "${label} NAV_TAKEOFF failed" >&2
    cat "${takeoff_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for AUTO_TAKEOFF on ${label}"
  if ! run_status_waiter "${namespace}" "${status_topic}" "${status_log}" "${STATUS_TIMEOUT_SEC}" '' "${TAKEOFF_NAV_STATE}" ''; then
    echo "${label} did not enter AUTO_TAKEOFF" >&2
    cat "${status_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for takeoff motion on ${label}"
  if ! run_local_position_waiter "${namespace}" "${local_position_topic}" "${takeoff_position_log}" "${TAKEOFF_POSITION_TIMEOUT_SEC}" "${TAKEOFF_MIN_DELTA_XY_NORM}" "${TAKEOFF_MAX_DELTA_Z}" ''; then
    echo "${label} did not show takeoff motion" >&2
    cat "${takeoff_position_log}" >&2 || true
    return 1
  fi

  echo "step: sending mode_loiter to ${label}"
  if ! run_vehicle_command "${namespace}" "${command_topic}" "${ack_topic}" 'mode_loiter' "${sysid}" "${loiter_log}"; then
    echo "${label} mode_loiter failed" >&2
    cat "${loiter_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for AUTO_LOITER on ${label}"
  if ! run_status_waiter "${namespace}" "${status_topic}" "${status_log}" "${STATUS_TIMEOUT_SEC}" '' "${LOITER_NAV_STATE}" ''; then
    echo "${label} did not enter AUTO_LOITER" >&2
    cat "${status_log}" >&2 || true
    return 1
  fi

  echo "step: sending NAV_LAND to ${label}"
  if ! run_navigation_command "${namespace}" "${command_topic}" "${ack_topic}" "${global_position_topic}" 'nav_land' "${sysid}" "${land_log}" "export PX4_TARGET_OFFSET_ALT_M='0.0'"; then
    echo "${label} NAV_LAND failed" >&2
    cat "${land_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for AUTO_LAND on ${label}"
  if ! run_status_waiter "${namespace}" "${status_topic}" "${status_log}" "${STATUS_TIMEOUT_SEC}" '' "${LAND_NAV_STATE}" ''; then
    echo "${label} did not enter AUTO_LAND" >&2
    cat "${status_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for landing descent on ${label}"
  if ! run_local_position_waiter "${namespace}" "${local_position_topic}" "${land_position_log}" "${LAND_POSITION_TIMEOUT_SEC}" '' '' "${LAND_MIN_DELTA_Z}"; then
    echo "${label} did not show landing descent" >&2
    cat "${land_position_log}" >&2 || true
    return 1
  fi

  echo "step: waiting for landed=true on ${label}"
  if ! run_land_detected_waiter "${namespace}" "${land_detected_topic}" "${land_detected_log}" "${LAND_DETECTED_TIMEOUT_SEC}"; then
    echo "${label} did not report landed=true" >&2
    cat "${land_detected_log}" >&2 || true
    return 1
  fi

  cat "${takeoff_log}"
  cat "${takeoff_position_log}"
  cat "${loiter_log}"
  cat "${land_log}"
  cat "${land_position_log}"
  cat "${land_detected_log}"
}

PLANE1_NAMESPACE='plane_01'
PLANE2_NAMESPACE='plane_02'
PLANE1_STATUS_TOPIC='/plane_01/fmu/out/vehicle_status_v1'
PLANE2_STATUS_TOPIC='/plane_02/fmu/out/vehicle_status_v1'
PLANE1_COMMAND_TOPIC='/plane_01/fmu/in/vehicle_command'
PLANE2_COMMAND_TOPIC='/plane_02/fmu/in/vehicle_command'
PLANE1_ACK_TOPIC='/plane_01/fmu/out/vehicle_command_ack'
PLANE2_ACK_TOPIC='/plane_02/fmu/out/vehicle_command_ack'
PLANE1_LOCAL_POSITION_TOPIC='/plane_01/fmu/out/vehicle_local_position'
PLANE2_LOCAL_POSITION_TOPIC='/plane_02/fmu/out/vehicle_local_position'
PLANE1_GLOBAL_POSITION_TOPIC='/plane_01/fmu/out/vehicle_global_position'
PLANE2_GLOBAL_POSITION_TOPIC='/plane_02/fmu/out/vehicle_global_position'
PLANE1_LAND_DETECTED_TOPIC='/plane_01/fmu/out/vehicle_land_detected'
PLANE2_LAND_DETECTED_TOPIC='/plane_02/fmu/out/vehicle_land_detected'
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-60}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-25}"
TAKEOFF_ALT_OFFSET_M="${PX4_TARGET_OFFSET_ALT_M:-30.0}"
TAKEOFF_NAV_STATE="${PX4_EXPECTED_TAKEOFF_NAV_STATE:-17}"
LOITER_NAV_STATE="${PX4_EXPECTED_LOITER_NAV_STATE:-4}"
LAND_NAV_STATE="${PX4_EXPECTED_LAND_NAV_STATE:-18}"
TAKEOFF_MIN_DELTA_XY_NORM="${PX4_EXPECTED_TAKEOFF_MIN_DELTA_XY_NORM:-5.0}"
TAKEOFF_MAX_DELTA_Z="${PX4_EXPECTED_TAKEOFF_MAX_DELTA_Z:--0.5}"
LAND_MIN_DELTA_Z="${PX4_EXPECTED_LAND_MIN_DELTA_Z:-10.0}"
TAKEOFF_POSITION_TIMEOUT_SEC="${PX4_TAKEOFF_LOCAL_POSITION_TIMEOUT_SEC:-40}"
LAND_POSITION_TIMEOUT_SEC="${PX4_LAND_LOCAL_POSITION_TIMEOUT_SEC:-120}"
LAND_DETECTED_TIMEOUT_SEC="${PX4_LAND_DETECTED_TIMEOUT_SEC:-120}"
PLANE1_SYS_ID='1'
PLANE2_SYS_ID='2'

echo "iconom phase-4 dual nav loop check"
echo
echo "this checks the first bounded two-aircraft navigation loop proof:"
echo "  - plane_01 completes takeoff, loiter, and landing"
echo "  - plane_02 then completes the same bounded loop in the same shared sim"
echo "  - no coordination logic is added; both loops remain independently targeted"
echo "  - gui mode: ${USE_GUI}"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, xrce_agent, ros2_app, px4, and px4_plane_02"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo xrce_agent ros2_app px4 px4_plane_02

echo "step 4: starting gazebo, xrce_agent, and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app

RUNNING_SERVICES="$(${COMPOSE_CMD[@]} ${COMPOSE_ARGS[@]} ps --services --status running)"
for service in gazebo xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before phase-4 dual nav loop check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 111
  fi
done

echo "step 5: building PX4 message and control packages"
ros2_exec '
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

echo "step 6: launching plane_01 and plane_02 PX4 runtimes"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG_1}" 2>&1 &
PX4_PID_1=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  px4_plane_02 /usr/local/bin/px4-run-vehicle.sh </dev/null >"${PX4_LOG_2}" 2>&1 &
PX4_PID_2=$!

echo "step 7: polling ROS 2 graph for dual navigation topics"
wait_for_topics \
  "${PLANE1_STATUS_TOPIC}" "${PLANE2_STATUS_TOPIC}" \
  "${PLANE1_COMMAND_TOPIC}" "${PLANE2_COMMAND_TOPIC}" \
  "${PLANE1_ACK_TOPIC}" "${PLANE2_ACK_TOPIC}" \
  "${PLANE1_LOCAL_POSITION_TOPIC}" "${PLANE2_LOCAL_POSITION_TOPIC}" \
  "${PLANE1_GLOBAL_POSITION_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" \
  "${PLANE1_LAND_DETECTED_TOPIC}" "${PLANE2_LAND_DETECTED_TOPIC}"

echo "step 8: running the bounded navigation loop on plane_01"
if ! run_plane_loop 'plane01' "${PLANE1_NAMESPACE}" "${PLANE1_SYS_ID}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_LOCAL_POSITION_TOPIC}" "${PLANE1_GLOBAL_POSITION_TOPIC}" "${PLANE1_LAND_DETECTED_TOPIC}"; then
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 115
fi

echo "step 9: confirming plane_02 stayed disarmed before its own loop"
PLANE2_IDLE_LOG="${ROOT_DIR}/.tmp-phase4-dual-nav-plane02-idle.log"
if ! run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_IDLE_LOG}" "${STATUS_TIMEOUT_SEC}" '1' '' ''; then
  echo "plane_02 changed state unexpectedly during plane_01 loop" >&2
  cat "${PLANE2_IDLE_LOG}" >&2 || true
  exit 116
fi

echo "step 10: running the bounded navigation loop on plane_02"
if ! run_plane_loop 'plane02' "${PLANE2_NAMESPACE}" "${PLANE2_SYS_ID}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_LOCAL_POSITION_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" "${PLANE2_LAND_DETECTED_TOPIC}"; then
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 117
fi

echo "phase-4 dual nav loop is alive"
echo "  plane_01 and plane_02 both completed the bounded phase-3-style loop in one shared sim"
