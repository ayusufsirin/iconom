#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
PX4_LOG_1="${ROOT_DIR}/.tmp-phase4-mode-px4-plane01.log"
PX4_LOG_2="${ROOT_DIR}/.tmp-phase4-mode-px4-plane02.log"
ARM_LOG_1="${ROOT_DIR}/.tmp-phase4-mode-arm-plane01.log"
ARM_LOG_2="${ROOT_DIR}/.tmp-phase4-mode-arm-plane02.log"
MODE_LOG_1="${ROOT_DIR}/.tmp-phase4-mode-plane01.log"
MODE_LOG_2="${ROOT_DIR}/.tmp-phase4-mode-plane02.log"
OFFBOARD_LOG_1="${ROOT_DIR}/.tmp-phase4-mode-offboard-plane01.log"
OFFBOARD_LOG_2="${ROOT_DIR}/.tmp-phase4-mode-offboard-plane02.log"
STATUS_LOG_1="${ROOT_DIR}/.tmp-phase4-mode-status-plane01.log"
STATUS_LOG_2="${ROOT_DIR}/.tmp-phase4-mode-status-plane02.log"
PX4_PID_1=""
PX4_PID_2=""
OFFBOARD_PID_1=""
OFFBOARD_PID_2=""

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
  if [[ -n "${OFFBOARD_PID_1}" ]] && kill -0 "${OFFBOARD_PID_1}" >/dev/null 2>&1; then
    kill "${OFFBOARD_PID_1}" >/dev/null 2>&1 || true
    wait "${OFFBOARD_PID_1}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${OFFBOARD_PID_2}" ]] && kill -0 "${OFFBOARD_PID_2}" >/dev/null 2>&1; then
    kill "${OFFBOARD_PID_2}" >/dev/null 2>&1 || true
    wait "${OFFBOARD_PID_2}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PX4_PID_1}" ]] && kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
    kill "${PX4_PID_1}" >/dev/null 2>&1 || true
    wait "${PX4_PID_1}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PX4_PID_2}" ]] && kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
    kill "${PX4_PID_2}" >/dev/null 2>&1 || true
    wait "${PX4_PID_2}" >/dev/null 2>&1 || true
  fi
  rm -f \
    "${PX4_LOG_1}" "${PX4_LOG_2}" \
    "${ARM_LOG_1}" "${ARM_LOG_2}" \
    "${MODE_LOG_1}" "${MODE_LOG_2}" \
    "${OFFBOARD_LOG_1}" "${OFFBOARD_LOG_2}" \
    "${STATUS_LOG_1}" "${STATUS_LOG_2}"
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

start_offboard_publisher() {
  local namespace="$1"
  local offboard_topic="$2"
  local trajectory_topic="$3"
  local local_position_topic="$4"
  local output_file="$5"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_OFFBOARD_CONTROL_MODE_TOPIC='${offboard_topic}'
    export PX4_TRAJECTORY_SETPOINT_TOPIC='${trajectory_topic}'
    export PX4_LOCAL_POSITION_TOPIC='${local_position_topic}'
    export PX4_OFFBOARD_READY_TIMEOUT_SEC='${OFFBOARD_READY_TIMEOUT_SEC}'
    export PX4_OFFBOARD_RUN_DURATION_SEC='${OFFBOARD_RUN_DURATION_SEC}'
    export PX4_OFFBOARD_STEP_DELAY_SEC='0.0'
    export PX4_OFFBOARD_DELTA_X='0.0'
    export PX4_OFFBOARD_DELTA_Y='0.0'
    export PX4_OFFBOARD_DELTA_Z='0.0'
    export PX4_OFFBOARD_DELTA_YAW='0.0'
    ros2 run iconom_control offboard_hold_publisher
  " >"${output_file}" 2>&1 &
  echo $!
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
PLANE1_OFFBOARD_CONTROL_MODE_TOPIC='/plane_01/fmu/in/offboard_control_mode'
PLANE2_OFFBOARD_CONTROL_MODE_TOPIC='/plane_02/fmu/in/offboard_control_mode'
PLANE1_TRAJECTORY_SETPOINT_TOPIC='/plane_01/fmu/in/trajectory_setpoint'
PLANE2_TRAJECTORY_SETPOINT_TOPIC='/plane_02/fmu/in/trajectory_setpoint'
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-60}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-20}"
ARM_READY_TIMEOUT_SEC="${PX4_ARM_READY_TIMEOUT_SEC:-30}"
STABILITY_TIMEOUT_SEC="${PX4_STABILITY_TIMEOUT_SEC:-5}"
OFFBOARD_READY_TIMEOUT_SEC="${PX4_OFFBOARD_READY_TIMEOUT_SEC:-20}"
OFFBOARD_RUN_DURATION_SEC="${PX4_OFFBOARD_RUN_DURATION_SEC:-40}"
OFFBOARD_STREAM_SETTLE_SEC="${PX4_OFFBOARD_STREAM_SETTLE_SEC:-5}"
EXPECTED_NAV_STATE='14'
MODE_COMMAND_NAME='mode_offboard'

echo "iconom phase-4 mode isolation check"
echo
echo "this checks the second dual-aircraft control proof:"
echo "  - plane_01 and plane_02 runtimes start together"
echo "  - both aircraft arm independently"
echo "  - plane_01 enters ${MODE_COMMAND_NAME} without changing plane_02"
echo "  - plane_02 then enters ${MODE_COMMAND_NAME} independently"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, xrce_agent, ros2_app, px4, and px4_plane_02"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo xrce_agent ros2_app px4 px4_plane_02

echo "step 4: starting gazebo, xrce_agent, and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in gazebo xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before phase-4 mode isolation check" >&2
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

echo "step 7: polling ROS 2 graph for both mode-control roots"
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

  if grep -qx "${PLANE1_COMMAND_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_COMMAND_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE1_ACK_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_ACK_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE1_STATUS_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_STATUS_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE1_LOCAL_POSITION_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_LOCAL_POSITION_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE1_OFFBOARD_CONTROL_MODE_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_OFFBOARD_CONTROL_MODE_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE1_TRAJECTORY_SETPOINT_TOPIC}" <<<"${TOPICS}" \
    && grep -qx "${PLANE2_TRAJECTORY_SETPOINT_TOPIC}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

echo "step 8: waiting for preflight-ready VehicleStatus on both aircraft"
if ! run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${STATUS_LOG_1}" "${ARM_READY_TIMEOUT_SEC}" '' '' 'true'; then
  echo "plane_01 did not report preflight-ready status" >&2
  cat "${STATUS_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 114
fi

if ! run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${STATUS_LOG_2}" "${ARM_READY_TIMEOUT_SEC}" '' '' 'true'; then
  echo "plane_02 did not report preflight-ready status" >&2
  cat "${STATUS_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 115
fi

echo "step 9: arming plane_01 and plane_02"
if ! run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'arm' '1' "${ARM_LOG_1}"; then
  echo "plane_01 arm command failed" >&2
  cat "${ARM_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 116
fi

if ! run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" 'arm' '2' "${ARM_LOG_2}"; then
  echo "plane_02 arm command failed" >&2
  cat "${ARM_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 117
fi

echo "step 10: verifying both aircraft reached armed state"
if ! run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${STATUS_LOG_1}" "${STATUS_TIMEOUT_SEC}" '2' '' ''; then
  echo "plane_01 did not reach armed state" >&2
  cat "${STATUS_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 118
fi

if ! run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${STATUS_LOG_2}" "${STATUS_TIMEOUT_SEC}" '2' '' ''; then
  echo "plane_02 did not reach armed state" >&2
  cat "${STATUS_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 119
fi

echo "step 11: starting the plane_01 offboard publisher"
OFFBOARD_PID_1="$(start_offboard_publisher "${PLANE1_NAMESPACE}" "${PLANE1_OFFBOARD_CONTROL_MODE_TOPIC}" "${PLANE1_TRAJECTORY_SETPOINT_TOPIC}" "${PLANE1_LOCAL_POSITION_TOPIC}" "${OFFBOARD_LOG_1}")"

echo "step 12: letting the plane_01 offboard stream settle for ${OFFBOARD_STREAM_SETTLE_SEC}s"
sleep "${OFFBOARD_STREAM_SETTLE_SEC}"

if [[ -n "${OFFBOARD_PID_1}" ]] && ! kill -0 "${OFFBOARD_PID_1}" >/dev/null 2>&1; then
  OFFBOARD_EXIT=0
  wait "${OFFBOARD_PID_1}" || OFFBOARD_EXIT=$?
  echo "plane_01 offboard publisher exited before mode switch" >&2
  cat "${OFFBOARD_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 120
fi

echo "step 13: sending ${MODE_COMMAND_NAME} to plane_01 only"
if ! run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${MODE_COMMAND_NAME}" '1' "${MODE_LOG_1}"; then
  echo "plane_01 mode command failed" >&2
  cat "${MODE_LOG_1}" >&2 || true
  cat "${OFFBOARD_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 121
fi

echo "step 14: verifying plane_01 enters OFFBOARD"
if ! run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${STATUS_LOG_1}" "${STATUS_TIMEOUT_SEC}" '2' "${EXPECTED_NAV_STATE}" ''; then
  echo "plane_01 did not reach nav_state ${EXPECTED_NAV_STATE}" >&2
  cat "${STATUS_LOG_1}" >&2 || true
  cat "${OFFBOARD_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 122
fi

echo "step 15: verifying plane_02 stays out of OFFBOARD"
if run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${STATUS_LOG_2}" "${STABILITY_TIMEOUT_SEC}" '2' "${EXPECTED_NAV_STATE}" ''; then
  echo "plane_02 entered nav_state ${EXPECTED_NAV_STATE} while only plane_01 was targeted" >&2
  cat "${STATUS_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 123
fi

if ! run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${STATUS_LOG_2}" "${STABILITY_TIMEOUT_SEC}" '2' '' ''; then
  echo "plane_02 changed out of armed state while only plane_01 was targeted" >&2
  cat "${STATUS_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 124
fi

echo "step 16: starting the plane_02 offboard publisher"
OFFBOARD_PID_2="$(start_offboard_publisher "${PLANE2_NAMESPACE}" "${PLANE2_OFFBOARD_CONTROL_MODE_TOPIC}" "${PLANE2_TRAJECTORY_SETPOINT_TOPIC}" "${PLANE2_LOCAL_POSITION_TOPIC}" "${OFFBOARD_LOG_2}")"

echo "step 17: letting the plane_02 offboard stream settle for ${OFFBOARD_STREAM_SETTLE_SEC}s"
sleep "${OFFBOARD_STREAM_SETTLE_SEC}"

if [[ -n "${OFFBOARD_PID_2}" ]] && ! kill -0 "${OFFBOARD_PID_2}" >/dev/null 2>&1; then
  OFFBOARD_EXIT=0
  wait "${OFFBOARD_PID_2}" || OFFBOARD_EXIT=$?
  echo "plane_02 offboard publisher exited before mode switch" >&2
  cat "${OFFBOARD_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 125
fi

echo "step 18: sending ${MODE_COMMAND_NAME} to plane_02 independently"
if ! run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${MODE_COMMAND_NAME}" '2' "${MODE_LOG_2}"; then
  echo "plane_02 mode command failed" >&2
  cat "${MODE_LOG_2}" >&2 || true
  cat "${OFFBOARD_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 126
fi

echo "step 19: verifying plane_02 enters OFFBOARD"
if ! run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${STATUS_LOG_2}" "${STATUS_TIMEOUT_SEC}" '2' "${EXPECTED_NAV_STATE}" ''; then
  echo "plane_02 did not reach nav_state ${EXPECTED_NAV_STATE}" >&2
  cat "${STATUS_LOG_2}" >&2 || true
  cat "${OFFBOARD_LOG_2}" >&2 || true
  tail -n 200 "${PX4_LOG_2}" >&2 || true
  exit 127
fi

echo "step 20: verifying plane_01 remains in OFFBOARD"
if ! run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${STATUS_LOG_1}" "${STABILITY_TIMEOUT_SEC}" '2' "${EXPECTED_NAV_STATE}" ''; then
  echo "plane_01 changed out of nav_state ${EXPECTED_NAV_STATE} while plane_02 was targeted" >&2
  cat "${STATUS_LOG_1}" >&2 || true
  tail -n 200 "${PX4_LOG_1}" >&2 || true
  exit 128
fi

echo "phase-4 mode isolation is alive"
cat "${ARM_LOG_1}"
cat "${ARM_LOG_2}"
cat "${MODE_LOG_1}"
cat "${MODE_LOG_2}"
cat "${OFFBOARD_LOG_1}"
cat "${OFFBOARD_LOG_2}"
cat "${STATUS_LOG_1}"
cat "${STATUS_LOG_2}"
