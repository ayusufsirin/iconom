#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

PX4_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-px4.log"
ARM_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-arm.log"
TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-takeoff.log"
LOITER_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-loiter.log"
MODE_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-mode.log"
STATUS_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-status.log"
AIRBORNE_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-airborne.log"
LAND_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-land.log"
LAND_DETECTED_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-land-detected.log"
OWNSHIP_ADAPTER_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-ownship.log"
PREDICTOR_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-predictor.log"
SELECTOR_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-selector.log"
PLANNER_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-planner.log"
STATE_MACHINE_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-state-machine.log"
RIVAL_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-rival.log"
MONITOR_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-monitor.log"
CUEING_LOG="${ROOT_DIR}/.tmp-phase6-scripted-cue-cueing.log"
CSV_PATH="${ROOT_DIR}/ros2_ws/.tmp-phase6-scripted-cue-geometry.csv"
CONTAINER_CSV_PATH="/workspaces/ros2_ws/.tmp-phase6-scripted-cue-geometry.csv"

PX4_PID=""
OWNSHIP_ADAPTER_PID=""
PREDICTOR_PID=""
SELECTOR_PID=""
PLANNER_PID=""
STATE_MACHINE_PID=""
RIVAL_PID=""
MONITOR_PID=""
CUEING_PID=""
COLD_BUILD="${ICONOM_PHASE6_COLD_BUILD:-0}"

usage() {
  cat <<'USAGE'
Usage: check-phase6-scripted-cue-geometry.sh [--incremental|--cold]

Run the phase-6 scripted route-comparison cueing check.

Environment:
  ICONOM_PHASE6_COLD_BUILD=0|1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cold)
      COLD_BUILD=1
      shift
      ;;
    --incremental)
      COLD_BUILD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

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
  local exit_code="${1:-0}"
  stop_pid "${CUEING_PID}"
  stop_pid "${MONITOR_PID}"
  stop_pid "${RIVAL_PID}"
  stop_pid "${STATE_MACHINE_PID}"
  stop_pid "${PLANNER_PID}"
  stop_pid "${SELECTOR_PID}"
  stop_pid "${PREDICTOR_PID}"
  stop_pid "${OWNSHIP_ADAPTER_PID}"
  stop_pid "${PX4_PID}"
  if [[ "${exit_code}" == "0" ]]; then
    rm -f \
      "${PX4_LOG}" \
      "${ARM_LOG}" \
      "${TAKEOFF_LOG}" \
      "${LOITER_LOG}" \
      "${MODE_LOG}" \
      "${STATUS_LOG}" \
      "${AIRBORNE_LOG}" \
      "${LAND_LOG}" \
      "${LAND_DETECTED_LOG}" \
      "${OWNSHIP_ADAPTER_LOG}" \
      "${PREDICTOR_LOG}" \
      "${SELECTOR_LOG}" \
      "${PLANNER_LOG}" \
      "${STATE_MACHINE_LOG}" \
      "${RIVAL_LOG}" \
      "${MONITOR_LOG}" \
      "${CUEING_LOG}"
  else
    echo "phase-6 scripted cue logs kept under ${ROOT_DIR}/.tmp-phase6-scripted-cue-*" >&2
    echo "phase-6 scripted cue CSV kept at ${CSV_PATH}" >&2
  fi
  "${COMPOSE_CMD[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap 'cleanup "$?"' EXIT

ros2_exec() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "$1"
}

wait_for_topic() {
  local topic="$1"
  local timeout_sec="$2"
  local topics
  for ((i=1; i<=timeout_sec; i++)); do
    topics="$(ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; ros2 topic list 2>/dev/null || true')"
    if grep -Fxq "${topic}" <<<"${topics}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for topic ${topic}" >&2
  return 1
}

wait_for_topics() {
  local topics="$1"
  local timeout_sec="$2"
  while IFS= read -r topic; do
    [[ -z "${topic}" ]] && continue
    wait_for_topic "${topic}" "${timeout_sec}"
  done <<<"${topics}"
}

wait_for_state() {
  local expected="$1"
  local timeout_sec="$2"
  local output
  for ((i=1; i<=timeout_sec; i++)); do
    output="$(ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; timeout 5 ros2 topic echo --once /guidance/pursuit_state 2>/dev/null || true')"
    if grep -q "data: ${expected}" <<<"${output}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for pursuit state ${expected}" >&2
  return 1
}

read_float_topic() {
  local topic="$1"
  ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; timeout 10 ros2 topic echo --once ${topic} 2>/dev/null || true" | awk '/data:/{print $2; exit}'
}

wait_for_min_altitude() {
  local local_position_topic="$1"
  local min_altitude_m="$2"
  local timeout_sec="$3"
  local output
  local z_value
  local altitude_agl

  for ((i=1; i<=timeout_sec; i++)); do
    output="$(ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; timeout 5 ros2 topic echo --once ${local_position_topic} 2>/dev/null || true")"
    z_value="$(printf '%s\n' "${output}" | awk '/^[[:space:]]*z:[[:space:]]*/{print $2; exit}')"
    if [[ -n "${z_value}" ]]; then
      altitude_agl="$(awk "BEGIN { printf \"%.2f\", -( ${z_value} ) }")"
      if awk "BEGIN { exit !(${altitude_agl} >= ${min_altitude_m}) }"; then
        echo "ownship start altitude gate: altitude_agl=${altitude_agl}m >= ${min_altitude_m}m"
        return 0
      fi
    fi
    sleep 1
  done

  echo "timed out waiting for ownship altitude >= ${min_altitude_m}m on ${local_position_topic}" >&2
  return 1
}
wait_for_geometry_hold() {
  local bearing_topic="$1"
  local bearing_threshold_deg="$2"
  local cue_topic="$3"
  local cue_threshold_deg="$4"
  local hold_sec="$5"
  local timeout_sec="$6"
  local sample_period_sec="0.2"
  local samples_required
  local max_iterations
  local hold_count=0
  local bearing_sample=""
  local cue_sample=""
  local best_bearing=""
  local best_cue=""

  samples_required="$(python3 - <<PY
import math
print(max(1, math.ceil(float(${hold_sec}) / 0.2)))
PY
)"
  max_iterations="$(python3 - <<PY
import math
print(max(1, math.ceil(float(${timeout_sec}) / 0.2)))
PY
)"

  for ((i=1; i<=max_iterations; i++)); do
    bearing_sample="$(read_float_topic "${bearing_topic}")"
    cue_sample="$(read_float_topic "${cue_topic}")"

    if [[ -n "${bearing_sample}" ]]; then
      if [[ -z "${best_bearing}" ]] || awk "BEGIN { exit !(${bearing_sample} < ${best_bearing}) }"; then
        best_bearing="${bearing_sample}"
      fi
    fi
    if [[ -n "${cue_sample}" ]]; then
      if [[ -z "${best_cue}" ]] || awk "BEGIN { exit !(${cue_sample} < ${best_cue}) }"; then
        best_cue="${cue_sample}"
      fi
    fi

    if [[ -n "${bearing_sample}" && -n "${cue_sample}" ]] && python3 - <<PY
bearing = float(${bearing_sample})
camera = float(${cue_sample})
raise SystemExit(0 if bearing <= float(${bearing_threshold_deg}) and camera <= float(${cue_threshold_deg}) else 1)
PY
    then
      hold_count=$((hold_count + 1))
      if (( hold_count >= samples_required )); then
        printf '%s %s' "${bearing_sample}" "${cue_sample}"
        return 0
      fi
    else
      hold_count=0
    fi

    sleep "${sample_period_sec}"
  done

  echo "timed out waiting for sustained bearing<=${bearing_threshold_deg} and cue<=${cue_threshold_deg}; best bearing=${best_bearing:-n/a}, best cue=${best_cue:-n/a}" >&2
  return 1
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
    script+=$'\n'"export PX4_EXPECTED_ARMING_STATE='${arming_state}'"
  fi
  if [[ -n "${nav_state}" ]]; then
    script+=$'\n'"export PX4_EXPECTED_NAV_STATE='${nav_state}'"
  fi
  if [[ -n "${preflight_flag}" ]]; then
    script+=$'\n'"export PX4_EXPECTED_PREFLIGHT_CHECKS_PASS='${preflight_flag}'"
  fi

  script+=$'\n''ros2 run iconom_control vehicle_status_waiter'
  ros2_exec "${script}" >"${output_file}" 2>&1
}

run_vehicle_command() {
  local namespace="$1"
  local command_topic="$2"
  local ack_topic="$3"
  local command_name="$4"
  local output_file="$5"

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
  local output_file="$6"
  local extra_env="$7"

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
    export PX4_COMMAND_TIMEOUT_SEC='${PX4_NAVIGATION_TIMEOUT_SEC:-30}'
    export PX4_GLOBAL_POSITION_TIMEOUT_SEC='${PX4_GLOBAL_POSITION_TIMEOUT_SEC:-30}'
${extra_env}
    ros2 run iconom_control navigation_command_client
  " >"${output_file}" 2>&1
}

run_land_detected_waiter() {
  local namespace="$1"
  local land_topic="$2"
  local output_file="$3"
  local timeout_sec="$4"
  local landed_flag="$5"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_LAND_DETECTED_TOPIC='${land_topic}'
    export PX4_LAND_DETECTED_TIMEOUT_SEC='${timeout_sec}'
    export PX4_EXPECTED_LANDED='${landed_flag}'
    ros2 run iconom_control vehicle_land_detected_waiter
  " >"${output_file}" 2>&1
}

assert_airborne_catch_state() {
  local namespace="$1"
  local local_position_topic="$2"
  local land_detected_topic="$3"
  local output_file="$4"
  local min_altitude_m="$5"
  local position
  local land

  position="$(ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; timeout 10 ros2 topic echo --once ${local_position_topic} 2>/dev/null || true")"
  land="$(ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash 2>/dev/null || true; set -u; timeout 10 ros2 topic echo --once ${land_detected_topic} 2>/dev/null || true")"

  (
    local z_value
    local landed
    local altitude_agl

    z_value="$(printf '%s\n' "${position}" | awk '/^[[:space:]]*z:[[:space:]]*/{print $2; exit}')"
    landed="$(printf '%s\n' "${land}" | awk '/^[[:space:]]*landed:[[:space:]]*/{print $2; exit}')"

    if [[ -z "${z_value}" ]]; then
      echo "failed to read vehicle_local_position z for airborne catch gate" >&2
      printf '%s\n' "${position}" >&2
      exit 1
    fi
    if [[ -z "${landed}" ]]; then
      echo "failed to read vehicle_land_detected landed flag for airborne catch gate" >&2
      printf '%s\n' "${land}" >&2
      exit 1
    fi

    altitude_agl="$(awk "BEGIN { printf \"%.2f\", -( ${z_value} ) }")"
    echo "airborne catch gate: z=${z_value} altitude_agl=${altitude_agl} landed=${landed}"

    if awk "BEGIN { exit !(${altitude_agl} < ${min_altitude_m}) }"; then
      echo "catch happened too low: altitude_agl=${altitude_agl}m < required ${min_altitude_m}m" >&2
      exit 1
    fi
    if [[ "${landed}" == "true" ]]; then
      echo "catch happened after ownship had already landed" >&2
      exit 1
    fi
  ) >"${output_file}" 2>&1
}

summarize_geometry_csv() {
  local csv_path="$1"
  python3 "${ROOT_DIR}/scripts/evaluate-phase6-geometry.py" "${csv_path}" \
    --initial-bearing-min-deg "${INITIAL_BEARING_ERROR_MIN_DEG}" \
    --bearing-improvement-min-deg "${BEARING_IMPROVEMENT_MIN_DEG}" \
    --rival-route-min-distance-m "${RIVAL_MIN_ROUTE_DISTANCE_M}" \
    --final-bearing-max-deg "${FINAL_BEARING_ERROR_MAX_DEG}" \
    --final-cue-max-deg "${FINAL_CUE_ERROR_MAX_DEG}" \
    --catch-min-altitude-m "${CATCH_MIN_ALTITUDE_M}" \
    --hold-sec "${CUE_HOLD_SEC}" \
    --initial-range-min-m "${INITIAL_RANGE_MIN_M}" \
    --range-reduction-min-m "${RANGE_REDUCTION_MIN_M}" \
    --final-range-max-m "${FINAL_RANGE_MAX_M}"
}

require_cmd docker
require_cmd python3

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

USE_GUI="${ICONOM_USE_GUI:-0}"
if [[ "${USE_GUI}" == "1" || "${PX4_HEADLESS:-1}" == "0" ]]; then
  require_file "${OVERRIDE_FILE}"
  if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; GUI scripted cue-geometry check requires a local X11 display" >&2
    exit 219
  fi
  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

START_MIN_ALTITUDE_M="${PHASE6_START_MIN_ALTITUDE_M:-12.0}"
START_ALTITUDE_TIMEOUT_SEC="${PHASE6_START_ALTITUDE_TIMEOUT_SEC:-90}"
ICONOM_VEHICLE_NAMESPACE="${ICONOM_VEHICLE_NAMESPACE:-plane_01}"
COMMAND_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/in/vehicle_command"
COMMAND_ACK_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_command_ack"
STATUS_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_status_v1"
LOCAL_POSITION_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_local_position"
GLOBAL_POSITION_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_global_position"
LAND_DETECTED_TOPIC="/${ICONOM_VEHICLE_NAMESPACE}/fmu/out/vehicle_land_detected"

STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-25}"
TOPIC_TIMEOUT_SEC="${PX4_TOPIC_TIMEOUT_SEC:-90}"
TAKEOFF_NAV_STATE="${PX4_EXPECTED_TAKEOFF_NAV_STATE:-17}"
LOITER_NAV_STATE="${PX4_EXPECTED_LOITER_NAV_STATE:-4}"
OFFBOARD_NAV_STATE="${PX4_EXPECTED_OFFBOARD_NAV_STATE:-14}"
LAND_NAV_STATE="${PX4_EXPECTED_LAND_NAV_STATE:-18}"
LAND_DETECTED_TIMEOUT_SEC="${PX4_LAND_DETECTED_TIMEOUT_SEC:-120}"

INITIAL_BEARING_ERROR_MIN_DEG="${PHASE6_INITIAL_BEARING_ERROR_MIN_DEG:-45.0}"
FINAL_BEARING_ERROR_MAX_DEG="${PHASE6_FINAL_BEARING_ERROR_MAX_DEG:-25.0}"
FINAL_CUE_ERROR_MAX_DEG="${PHASE6_FINAL_CUE_ERROR_MAX_DEG:-25.0}"
BEARING_IMPROVEMENT_MIN_DEG="${PHASE6_BEARING_IMPROVEMENT_MIN_DEG:-40.0}"
RIVAL_MIN_ROUTE_DISTANCE_M="${PHASE6_RIVAL_MIN_ROUTE_DISTANCE_M:-20.0}"
CUE_HOLD_SEC="${PHASE6_CUE_HOLD_SEC:-1}"
CUE_ERROR_TIMEOUT_SEC="${PHASE6_CUE_ERROR_TIMEOUT_SEC:-90}"
CUE_WINDOW_SEC="${PHASE6_CUE_WINDOW_SEC:-55}"
CATCH_MIN_ALTITUDE_M="${PHASE6_CATCH_MIN_ALTITUDE_M:-10.0}"
INITIAL_RANGE_MIN_M="${PHASE6_INITIAL_RANGE_MIN_M:-80.0}"
RANGE_REDUCTION_MIN_M="${PHASE6_RANGE_REDUCTION_MIN_M:-40.0}"
FINAL_RANGE_MAX_M="${PHASE6_FINAL_RANGE_MAX_M:-60.0}"

SCRIPTED_RIVAL_BEARING_OFFSET_DEG="${PHASE6_SCRIPTED_RIVAL_BEARING_OFFSET_DEG:-60.0}"
SCRIPTED_RIVAL_DISTANCE_M="${PHASE6_SCRIPTED_RIVAL_DISTANCE_M:-120.0}"
SCRIPTED_RIVAL_ALTITUDE_OFFSET_M="${PHASE6_SCRIPTED_RIVAL_ALTITUDE_OFFSET_M:-0.0}"
SCRIPTED_RIVAL_SPEED_MPS="${PHASE6_SCRIPTED_RIVAL_SPEED_MPS:-12.0}"
SCRIPTED_RIVAL_COURSE_OFFSET_DEG="${PHASE6_SCRIPTED_RIVAL_COURSE_OFFSET_DEG:--90.0}"
SCRIPTED_RIVAL_ROUTE_DURATION_SEC="${PHASE6_SCRIPTED_RIVAL_ROUTE_DURATION_SEC:-45.0}"

FORWARD_CONE_TOPIC="/guidance/camera_cue_error_deg"
BEARING_ERROR_TOPIC="/guidance/bearing_error_deg"

echo "iconom phase-6 scripted cue-geometry check"
echo "gui mode: ${USE_GUI}"
echo "build mode: $([[ "${COLD_BUILD}" == "1" ]] && echo cold || echo incremental)"
echo "csv artifact: ${CSV_PATH}"
echo

echo "this checks the scripted moving-rival route-comparison slice:"
echo "  - plane_01 starts in the maintained single-aircraft runtime"
echo "  - a scripted rival follows a deterministic moving route"
echo "  - the guidance stack cues plane_01 toward that rival"
echo "  - bearing, forward-cone cueing, and range closure all become sustained acceptance gates"
echo "  - plane_01 must still catch while airborne and land successfully afterward"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
ids="$(docker ps -aq --filter name=iconom-)"
if [[ -n "${ids}" ]]; then
  docker rm -f ${ids} >/dev/null 2>&1 || true
fi
rm -f "${CSV_PATH}"

echo "step 3: building gazebo, referee_server, xrce_agent, ros2_app, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo referee_server xrce_agent ros2_app px4

echo "step 4: starting gazebo, referee_server, xrce_agent, and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo referee_server xrce_agent ros2_app
RUNNING_SERVICES="$(${COMPOSE_CMD[@]} ${COMPOSE_ARGS[@]} ps --services --status running)"
for service in gazebo referee_server xrce_agent ros2_app; do
  if ! grep -Fxq "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before scripted cue-geometry validation" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 101
  fi
done

echo "step 5: preparing PX4 message, control, competition, and guidance packages"
ros2_exec "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  cd /workspaces/ros2_ws
  if [[ \"${COLD_BUILD}\" == \"1\" ]]; then
    rm -rf build install log
  fi
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  colcon build --merge-install --packages-up-to px4_msgs iconom_control iconom_competition iconom_guidance
"


echo "step 6: launching the PX4 runtime"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG}" 2>&1 &
PX4_PID=$!

echo "step 7: polling ROS 2 graph for plane_01 topics"
wait_for_topics "$(cat <<TOPICS
${STATUS_TOPIC}
${LOCAL_POSITION_TOPIC}
${GLOBAL_POSITION_TOPIC}
TOPICS
)" "${TOPIC_TIMEOUT_SEC}"

echo "step 8: bringing plane_01 to loiter"
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' '' 'true'
run_vehicle_command "${ICONOM_VEHICLE_NAMESPACE}" "${COMMAND_TOPIC}" "${COMMAND_ACK_TOPIC}" 'arm' "${ARM_LOG}"
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '2' '' ''
run_navigation_command "${ICONOM_VEHICLE_NAMESPACE}" "${COMMAND_TOPIC}" "${COMMAND_ACK_TOPIC}" "${GLOBAL_POSITION_TOPIC}" 'nav_takeoff' "${TAKEOFF_LOG}" ''
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" "" "${TAKEOFF_NAV_STATE}" ""
echo "step 8b: waiting for plane_01 to climb before loiter"
ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${ICONOM_VEHICLE_NAMESPACE}'
    export PX4_LOCAL_POSITION_TOPIC='${LOCAL_POSITION_TOPIC}'
    export PX4_LOCAL_POSITION_TIMEOUT_SEC='${START_ALTITUDE_TIMEOUT_SEC}'
    export PX4_MIN_ALTITUDE_AGL='${START_MIN_ALTITUDE_M}'
    ros2 run iconom_control vehicle_local_position_waiter
  " >"${AIRBORNE_LOG}" 2>&1
run_vehicle_command "${ICONOM_VEHICLE_NAMESPACE}" "${COMMAND_TOPIC}" "${COMMAND_ACK_TOPIC}" 'mode_loiter' "${LOITER_LOG}"
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" "" "${LOITER_NAV_STATE}" ""

echo "step 9: starting the geometry monitor before the scripted rival begins moving"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/cue_geometry_monitor --ros-args -p publish_period_sec:=0.2 -p forward_cone_deg:=${FINAL_CUE_ERROR_MAX_DEG} -p output_csv:='${CONTAINER_CSV_PATH}'" >"${MONITOR_LOG}" 2>&1 &
MONITOR_PID=$!

echo "step 10: starting the ownship adapter, scripted rival, and guidance nodes"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; export REF_HOST=referee_server; export REF_PORT=45678; export AIRCRAFT_ID='${ICONOM_VEHICLE_NAMESPACE}'; /workspaces/ros2_ws/install/bin/ownship_telemetry_adapter" >"${OWNSHIP_ADAPTER_LOG}" 2>&1 &
OWNSHIP_ADAPTER_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/predictor" >"${PREDICTOR_LOG}" 2>&1 &
PREDICTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/target_selector" >"${SELECTOR_LOG}" 2>&1 &
SELECTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/intercept_planner --ros-args -p max_intercept_distance:=80.0" >"${PLANNER_LOG}" 2>&1 &
PLANNER_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/pursuit_state_machine" >"${STATE_MACHINE_LOG}" 2>&1 &
STATE_MACHINE_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/scripted_rival_publisher --ros-args -p publish_period_sec:=0.2 -p bearing_offset_deg:=${SCRIPTED_RIVAL_BEARING_OFFSET_DEG} -p distance_m:=${SCRIPTED_RIVAL_DISTANCE_M} -p altitude_offset_m:=${SCRIPTED_RIVAL_ALTITUDE_OFFSET_M} -p rival_speed_mps:=${SCRIPTED_RIVAL_SPEED_MPS} -p rival_course_offset_deg:=${SCRIPTED_RIVAL_COURSE_OFFSET_DEG} -p route_duration_sec:=${SCRIPTED_RIVAL_ROUTE_DURATION_SEC}" >"${RIVAL_LOG}" 2>&1 &
RIVAL_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/camera_cueing_bridge --ros-args -p vehicle_namespace:='${ICONOM_VEHICLE_NAMESPACE}' -p publish_rate_hz:=20.0 -p thrust_x:=0.66 -p roll_angle_gain:=0.80 -p max_roll_deg:=35.0 -p pitch_angle_deg:=2.0 -p pitch_angle_gain:=0.02 -p max_pitch_deg:=12.0 -p altitude_error_deadband_m:=3.0 -p capture_error_deg:=${FINAL_CUE_ERROR_MAX_DEG}" >"${CUEING_LOG}" 2>&1 &
CUEING_PID=$!

wait_for_topics "$(cat <<TOPICS
/competition/ownship/state
/competition/rival/state
/competition/prediction/rival_position
/guidance/selected_target
/guidance/intercept_target
/guidance/pursuit_state
/guidance/camera_cue_error_deg
TOPICS
)" 30
wait_for_state pursue 30
wait_for_topic "${BEARING_ERROR_TOPIC}" 30

echo "step 11: confirming the cueing bridge emits PX4 attitude offboard setpoints"
for ((i=1; i<=30; i++)); do
  if grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
    break
  fi
  sleep 1
done
if ! grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
  echo "camera cueing bridge did not publish any PX4 attitude offboard setpoint during scripted geometry validation" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 201
fi

echo "step 12: switching plane_01 into OFFBOARD for cueing"
run_vehicle_command "${ICONOM_VEHICLE_NAMESPACE}" "${COMMAND_TOPIC}" "${COMMAND_ACK_TOPIC}" 'mode_offboard' "${MODE_LOG}"
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${OFFBOARD_NAV_STATE}" ''
echo "step 13: running the scripted cueing window before CSV validation"
sleep "${CUE_WINDOW_SEC}"
CATCH_BEARING_ERROR="nan"
CATCH_CUE_ERROR="nan"


echo "step 14: stopping scripted geometry capture and landing plane_01"
stop_pid "${CUEING_PID}"
CUEING_PID=""
stop_pid "${MONITOR_PID}"
MONITOR_PID=""
stop_pid "${RIVAL_PID}"
RIVAL_PID=""
stop_pid "${STATE_MACHINE_PID}"
STATE_MACHINE_PID=""
stop_pid "${PLANNER_PID}"
PLANNER_PID=""
stop_pid "${SELECTOR_PID}"
SELECTOR_PID=""
stop_pid "${PREDICTOR_PID}"
PREDICTOR_PID=""
stop_pid "${OWNSHIP_ADAPTER_PID}"
OWNSHIP_ADAPTER_PID=""
run_navigation_command "${ICONOM_VEHICLE_NAMESPACE}" "${COMMAND_TOPIC}" "${COMMAND_ACK_TOPIC}" "${GLOBAL_POSITION_TOPIC}" 'nav_land' "${LAND_LOG}" ''
run_status_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${STATUS_TOPIC}" "${STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LAND_NAV_STATE}" ''
run_land_detected_waiter "${ICONOM_VEHICLE_NAMESPACE}" "${LAND_DETECTED_TOPIC}" "${LAND_DETECTED_LOG}" "${LAND_DETECTED_TIMEOUT_SEC}" 'true'

echo "step 15: validating the recorded route-comparison artifact"
GEOMETRY_SUMMARY="$(summarize_geometry_csv "${CSV_PATH}")"

echo "phase-6 scripted cue geometry succeeded"
echo "${GEOMETRY_SUMMARY}"
echo "csv_path=${CSV_PATH}"
