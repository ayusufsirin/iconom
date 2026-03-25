#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-phase6-cueing-px4.log"
ARM_LOG="${ROOT_DIR}/.tmp-phase6-cueing-arm.log"
TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase6-cueing-takeoff.log"
LOITER_LOG="${ROOT_DIR}/.tmp-phase6-cueing-loiter.log"
MODE_LOG="${ROOT_DIR}/.tmp-phase6-cueing-mode.log"
STATUS_LOG="${ROOT_DIR}/.tmp-phase6-cueing-status.log"
POSITION_LOG="${ROOT_DIR}/.tmp-phase6-cueing-position.log"
ADAPTER_LOG="${ROOT_DIR}/.tmp-phase6-ownship-adapter.log"
PREDICTOR_LOG="${ROOT_DIR}/.tmp-phase6-predictor.log"
SELECTOR_LOG="${ROOT_DIR}/.tmp-phase6-selector.log"
PLANNER_LOG="${ROOT_DIR}/.tmp-phase6-planner.log"
STATE_MACHINE_LOG="${ROOT_DIR}/.tmp-phase6-state-machine.log"
RIVAL_LOG="${ROOT_DIR}/.tmp-phase6-rival.log"
CUEING_LOG="${ROOT_DIR}/.tmp-phase6-cueing.log"
PX4_PID=""
ADAPTER_PID=""
PREDICTOR_PID=""
SELECTOR_PID=""
PLANNER_PID=""
STATE_MACHINE_PID=""
RIVAL_PID=""
CUEING_PID=""

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

stop_pid() {
  local pid="$1"
  if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  stop_pid "${CUEING_PID}"
  stop_pid "${RIVAL_PID}"
  stop_pid "${STATE_MACHINE_PID}"
  stop_pid "${PLANNER_PID}"
  stop_pid "${SELECTOR_PID}"
  stop_pid "${PREDICTOR_PID}"
  stop_pid "${ADAPTER_PID}"
  stop_pid "${PX4_PID}"
  rm -f \
    "${PX4_LOG}" \
    "${ARM_LOG}" \
    "${TAKEOFF_LOG}" \
    "${MODE_LOG}" \
    "${LOITER_LOG}" \
    "${STATUS_LOG}" \
    "${POSITION_LOG}" \
    "${ADAPTER_LOG}" \
    "${PREDICTOR_LOG}" \
    "${SELECTOR_LOG}" \
    "${PLANNER_LOG}" \
    "${STATE_MACHINE_LOG}" \
    "${RIVAL_LOG}" \
    "${CUEING_LOG}"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

ros2_exec() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T ros2_app bash -lc "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash
    fi
    set -u
    $1
  "
}

wait_for_topic() {
  local topic="$1"
  local timeout_sec="$2"
  local topics
  for ((i=1; i<=timeout_sec; i++)); do
    topics="$(ros2_exec 'ros2 topic list 2>/dev/null || true')"
    if grep -qx "${topic}" <<<"${topics}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for topic ${topic}" >&2
  return 1
}

wait_for_state() {
  local expected="$1"
  local timeout_sec="$2"
  local output
  for ((i=1; i<=timeout_sec; i++)); do
    output="$(ros2_exec 'timeout 5 ros2 topic echo --once /guidance/pursuit_state 2>/dev/null || true')"
    if grep -q "data: ${expected}" <<<"${output}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for pursuit state ${expected}" >&2
  return 1
}

read_cue_error() {
  ros2_exec 'timeout 10 ros2 topic echo --once /guidance/camera_cue_error_deg 2>/dev/null || true' | awk '/data:/{print $2; exit}'
}

wait_for_cue_error_below() {
  local threshold_deg="$1"
  local timeout_sec="$2"
  local sample
  local best=""
  for ((i=1; i<=timeout_sec; i++)); do
    sample="$(read_cue_error)"
    if [[ -n "${sample}" ]]; then
      if [[ -z "${best}" ]] || awk "BEGIN { exit !(${sample} < ${best}) }"; then
        best="${sample}"
      fi
      if python3 - <<PY
value = float(${sample})
threshold = float(${threshold_deg})
raise SystemExit(0 if value <= threshold else 1)
PY
      then
        printf '%s' "${sample}"
        return 0
      fi
    fi
    sleep 1
  done
  if [[ -n "${best}" ]]; then
    echo "timed out waiting for cue error <= ${threshold_deg} deg (best observed ${best} deg)" >&2
  else
    echo "timed out waiting for cue error <= ${threshold_deg} deg (no cue samples observed)" >&2
  fi
  return 1
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
    echo "DISPLAY is not set; GUI cueing check requires a local X11 display" >&2
    exit 219
  fi
  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

trap cleanup EXIT

ICONOM_VEHICLE_NAMESPACE="${ICONOM_VEHICLE_NAMESPACE:-plane_01}"
COMMAND_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/in/vehicle_command"
COMMAND_ACK_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_command_ack"
STATUS_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_status_v1"
LOCAL_POSITION_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_local_position"
GLOBAL_POSITION_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_global_position"
TAKEOFF_ALT_OFFSET_M="${PX4_TARGET_OFFSET_ALT_M:-30.0}"
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-45}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-25}"
TAKEOFF_NAV_STATE="${PX4_EXPECTED_TAKEOFF_NAV_STATE:-17}"
LOITER_NAV_STATE="${PX4_EXPECTED_LOITER_NAV_STATE:-4}"
OFFBOARD_NAV_STATE="${PX4_EXPECTED_OFFBOARD_NAV_STATE:-14}"
TAKEOFF_MIN_DELTA_XY_NORM="${PX4_EXPECTED_TAKEOFF_MIN_DELTA_XY_NORM:-5.0}"
TAKEOFF_MAX_DELTA_Z="${PX4_EXPECTED_TAKEOFF_MAX_DELTA_Z:--0.5}"
INITIAL_CUE_ERROR_MIN_DEG="${PHASE6_INITIAL_CUE_ERROR_MIN_DEG:-35.0}"
FINAL_CUE_ERROR_MAX_DEG="${PHASE6_FINAL_CUE_ERROR_MAX_DEG:-25.0}"
CUE_ERROR_TIMEOUT_SEC="${PHASE6_CUE_ERROR_TIMEOUT_SEC:-90}"


echo "iconom phase-6 camera cueing check"
echo "vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "command topic: ${COMMAND_TOPIC}"
echo "status topic: ${STATUS_TOPIC}"
echo "cue error threshold: <= ${FINAL_CUE_ERROR_MAX_DEG} deg"
echo "gui mode: ${USE_GUI}"
echo
echo "this checks the first aircraft cueing slice:"
echo "  - plane_01 takes off and stabilizes in loiter"
echo "  - a deterministic scripted rival is injected into the phase-6 guidance path"
echo "  - the cueing bridge emits bounded body-rate offboard setpoints"
echo "  - plane_01 enters OFFBOARD and the published cue error drops toward the nose-camera forward cone"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
docker rm -f iconom-referee_server-1 iconom-gazebo-1 iconom-xrce_agent-1 iconom-ros2_app-1 >/dev/null 2>&1 || true

echo "step 3: building gazebo, referee_server, xrce_agent, ros2_app, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo referee_server xrce_agent ros2_app px4

echo "step 4: starting gazebo, referee_server, and xrce_agent"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo referee_server xrce_agent; then
  echo "compose up hit a transient container-networking error; retrying once" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
  sleep 2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo referee_server xrce_agent
fi

RUNNING_SERVICES="$(${COMPOSE_CMD[@]} "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in gazebo referee_server xrce_agent; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before cueing check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 201
  fi
done

echo "step 5: building PX4 message, competition, control, and guidance packages"
ros2_exec '
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  cd /workspaces/ros2_ws
  colcon build --merge-install --packages-up-to px4_msgs iconom_control iconom_competition iconom_guidance
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

echo "step 7: polling ROS 2 graph for PX4 topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before cueing topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    cat "${PX4_LOG}" >&2 || true
    exit 202
  fi

  TOPICS="$(ros2_exec 'ros2 topic list 2>/dev/null || true')"
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
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='true'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not report preflight-ready state before cueing" >&2
  cat "${STATUS_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 203
fi

echo "step 9: arming through the validated command path"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='arm'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${ARM_LOG}" 2>&1; then
  echo "the arm command did not succeed before cueing validation" >&2
  cat "${ARM_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 204
fi

echo "step 10: sending NAV_TAKEOFF through the validated navigation client"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_GLOBAL_POSITION_TOPIC='${GLOBAL_POSITION_TOPIC}'
  export PX4_NAV_COMMAND_NAME='nav_takeoff'
  export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-20}'
  ros2 run iconom_control navigation_command_client
" >"${TAKEOFF_LOG}" 2>&1; then
  echo "the NAV_TAKEOFF command did not succeed before cueing" >&2
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 205
fi

echo "step 11: waiting for VehicleStatus.nav_state=AUTO_TAKEOFF"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${TAKEOFF_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not enter AUTO_TAKEOFF before cueing" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 206
fi

echo "step 12: waiting for takeoff motion in VehicleLocalPosition"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_LOCAL_POSITION_TOPIC='${LOCAL_POSITION_TOPIC}'
  export PX4_LOCAL_POSITION_TIMEOUT_SEC='${PX4_LOCAL_POSITION_TIMEOUT_SEC:-40}'
  export PX4_MIN_DELTA_XY_NORM='${TAKEOFF_MIN_DELTA_XY_NORM}'
  export PX4_MAX_DELTA_Z='${TAKEOFF_MAX_DELTA_Z}'
  ros2 run iconom_control vehicle_local_position_waiter
" >"${POSITION_LOG}" 2>&1; then
  echo "VehicleLocalPosition did not show takeoff motion before cueing" >&2
  cat "${POSITION_LOG}" >&2 || true
  cat "${TAKEOFF_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 207
fi

echo "step 13: sending mode_loiter to stabilize the airframe before cueing"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='mode_loiter'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${LOITER_LOG}" 2>&1; then
  echo "the mode_loiter command did not succeed before cueing" >&2
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 208
fi

echo "step 14: waiting for VehicleStatus.nav_state=AUTO_LOITER"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${LOITER_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not enter AUTO_LOITER before cueing" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${LOITER_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 209
fi

echo "step 15: starting the live ownship telemetry adapter"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e REF_HOST=referee_server \
  -e REF_PORT=45678 \
  -e AIRCRAFT_ID=${ICONOM_VEHICLE_NAMESPACE} \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/ownship_telemetry_adapter
  ' </dev/null >"${ADAPTER_LOG}" 2>&1 &
ADAPTER_PID=$!

wait_for_topic /competition/ownship/state 20

echo "step 16: starting phase-6 guidance nodes"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/predictor
  ' </dev/null >"${PREDICTOR_LOG}" 2>&1 &
PREDICTOR_PID=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/target_selector
  ' </dev/null >"${SELECTOR_LOG}" 2>&1 &
SELECTOR_PID=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/intercept_planner --ros-args -p max_intercept_distance:=80.0
  ' </dev/null >"${PLANNER_LOG}" 2>&1 &
PLANNER_PID=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/pursuit_state_machine
  ' </dev/null >"${STATE_MACHINE_LOG}" 2>&1 &
STATE_MACHINE_PID=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/scripted_rival_publisher --ros-args -p bearing_offset_deg:=60.0 -p distance_m:=40.0 -p altitude_offset_m:=0.0
  ' </dev/null >"${RIVAL_LOG}" 2>&1 &
RIVAL_PID=$!

"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  ros2_app bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    /workspaces/ros2_ws/install/bin/camera_cueing_bridge --ros-args -p vehicle_namespace:='"${ICONOM_VEHICLE_NAMESPACE}"' -p publish_rate_hz:=20.0 -p thrust_x:=0.72 -p roll_rate_gain:=1.2 -p max_roll_rate:=1.0 -p yaw_rate_gain:=0.35 -p max_yaw_rate:=0.4
  ' </dev/null >"${CUEING_LOG}" 2>&1 &
CUEING_PID=$!

for topic in \
  /competition/rival/state \
  /competition/prediction/rival_position \
  /guidance/selected_target \
  /guidance/intercept_target \
  /guidance/pursuit_state \
  /guidance/camera_cue_error_deg; do
  wait_for_topic "${topic}" 25
done

wait_for_state pursue 30

echo "step 17: sampling the initial cue error"
INITIAL_CUE_ERROR="$(read_cue_error)"
if [[ -z "${INITIAL_CUE_ERROR}" ]]; then
  echo "could not read the initial camera cue error" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 210
fi
if ! python3 - <<PY
value = float(${INITIAL_CUE_ERROR})
threshold = float(${INITIAL_CUE_ERROR_MIN_DEG})
raise SystemExit(0 if value >= threshold else 1)
PY
then
  echo "initial cue error ${INITIAL_CUE_ERROR} deg was below the expected off-axis threshold ${INITIAL_CUE_ERROR_MIN_DEG} deg" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 211
fi

echo "initial cue error: ${INITIAL_CUE_ERROR} deg"

echo "step 18: confirming the cueing bridge emits body-rate offboard setpoints"
for ((i=1; i<=30; i++)); do
  if grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
    break
  fi
  sleep 1
done
if ! grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
  echo "camera cueing bridge did not publish any offboard setpoint" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 212
fi

echo "step 19: switching plane_01 into OFFBOARD for cueing"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_COMMAND_TOPIC='${COMMAND_TOPIC}'
  export PX4_COMMAND_ACK_TOPIC='${COMMAND_ACK_TOPIC}'
  export PX4_COMMAND_NAME='mode_offboard'
  export PX4_COMMAND_TIMEOUT_SEC='${PX4_COMMAND_TIMEOUT_SEC:-15}'
  ros2 run iconom_control vehicle_command_client
" >"${MODE_LOG}" 2>&1; then
  echo "the mode_offboard command did not succeed before cueing validation" >&2
  cat "${MODE_LOG}" >&2 || true
  cat "${CUEING_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 213
fi

echo "step 20: waiting for VehicleStatus.nav_state=OFFBOARD"
if ! ros2_exec "
  export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
  export PX4_VEHICLE_STATUS_TOPIC='${STATUS_TOPIC}'
  export PX4_STATUS_TIMEOUT_SEC='${STATUS_TIMEOUT_SEC}'
  export PX4_EXPECTED_NAV_STATE='${OFFBOARD_NAV_STATE}'
  ros2 run iconom_control vehicle_status_waiter
" >"${STATUS_LOG}" 2>&1; then
  echo "VehicleStatus did not enter OFFBOARD during cueing validation" >&2
  cat "${STATUS_LOG}" >&2 || true
  cat "${MODE_LOG}" >&2 || true
  cat "${CUEING_LOG}" >&2 || true
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 214
fi

echo "step 21: waiting for the cue error to drop toward the forward cone"
FINAL_CUE_ERROR="$(wait_for_cue_error_below "${FINAL_CUE_ERROR_MAX_DEG}" "${CUE_ERROR_TIMEOUT_SEC}")"

echo "phase-6 camera cueing is alive"
echo "initial cue error: ${INITIAL_CUE_ERROR} deg"
echo "final cue error: ${FINAL_CUE_ERROR} deg"
cat "${CUEING_LOG}"
