#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--profile phase4 --profile phase5 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

PX4_LOG_1="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-px4-plane01.log"
PX4_LOG_2="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-px4-plane02.log"
PLANE1_ARM_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-arm.log"
PLANE1_TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-takeoff.log"
PLANE1_LOITER_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-loiter.log"
PLANE1_STATUS_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-status.log"
PLANE1_POSITION_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-position.log"
PLANE1_MODE_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-mode.log"
PLANE1_AIRBORNE_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-airborne.log"
PLANE1_LAND_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-land.log"
PLANE1_LAND_POSITION_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-land-position.log"
PLANE1_LAND_DETECTED_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane01-land-detected.log"
PLANE2_ARM_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-arm.log"
PLANE2_TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-takeoff.log"
PLANE2_LOITER_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-loiter.log"
PLANE2_REPOSITION_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-reposition.log"
PLANE2_ROUTE_POINT1_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-route-point1.log"
PLANE2_ROUTE_POINT2_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-route-point2.log"
PLANE2_ROUTE_POINT3_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-route-point3.log"
PLANE2_ROUTE_POINT4_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-route-point4.log"
PLANE2_LAND_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-land.log"
PLANE2_LAND_POSITION_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-land-position.log"
PLANE2_LAND_DETECTED_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-land-detected.log"
PLANE2_STATUS_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-status.log"
PLANE2_POSITION_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-plane02-position.log"
OWNSHIP_ADAPTER_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-ownship.log"
RIVAL_ADAPTER_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-rival.log"
PREDICTOR_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-predictor.log"
SELECTOR_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-selector.log"
PLANNER_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-planner.log"
STATE_MACHINE_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-state-machine.log"
CUEING_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-cueing.log"
MONITOR_LOG="${ROOT_DIR}/.tmp-phase6-live-rival-geometry-monitor.log"
CSV_PATH="${ROOT_DIR}/ros2_ws/.tmp-phase6-live-rival-geometry.csv"
CONTAINER_CSV_PATH="/workspaces/ros2_ws/.tmp-phase6-live-rival-geometry.csv"
PX4_PID_1=""
PX4_PID_2=""
OWNSHIP_ADAPTER_PID=""
RIVAL_ADAPTER_PID=""
PREDICTOR_PID=""
SELECTOR_PID=""
PLANNER_PID=""
STATE_MACHINE_PID=""
CUEING_PID=""
MONITOR_PID=""
RIVAL_ROUTE_PID=""
COLD_BUILD="${ICONOM_PHASE6_COLD_BUILD:-0}"

usage() {
  cat <<'USAGE'
Usage: check-phase6-live-rival-geometry.sh [--incremental|--cold]

Run the standalone phase-6 live-rival geometry hardening check.

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
  -h | --help)
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
  stop_pid "${STATE_MACHINE_PID}"
  stop_pid "${PLANNER_PID}"
  stop_pid "${SELECTOR_PID}"
  stop_pid "${PREDICTOR_PID}"
  stop_pid "${RIVAL_ADAPTER_PID}"
  stop_pid "${OWNSHIP_ADAPTER_PID}"
  stop_pid "${RIVAL_ROUTE_PID}"
  stop_pid "${PX4_PID_2}"
  stop_pid "${PX4_PID_1}"
  if [[ "${exit_code}" == "0" ]]; then
    rm -f "${ROOT_DIR}"/.tmp-phase6-live-rival-geometry-*.log
  else
    echo "phase-6 live-rival-geometry logs kept under ${ROOT_DIR}/.tmp-phase6-live-rival-geometry-*.log" >&2
    echo "phase-6 live-rival-geometry CSV kept at ${CSV_PATH}" >&2
  fi
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap 'cleanup "$?"' EXIT

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

run_live_rival_rectangle_route() {
  run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'do_reposition' "${PLANE2_SYS_ID}" "${PLANE2_ROUTE_POINT1_LOG}" "    export PX4_TARGET_OFFSET_NORTH_M='${PLANE2_ROUTE_POINT1_NORTH_M}'
    export PX4_TARGET_OFFSET_EAST_M='${PLANE2_ROUTE_POINT1_EAST_M}'
    export PX4_TARGET_OFFSET_ALT_M='${PLANE2_ROUTE_POINT_ALT_M}'
    export PX4_LOITER_RADIUS_M='${PLANE2_ROUTE_LOITER_RADIUS_M}'
    export PX4_GROUNDSPEED_M_S='${PLANE2_ROUTE_GROUNDSPEED_M_S}'"
  sleep "${PLANE2_ROUTE_LEG_DWELL_SEC}"

  run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'do_reposition' "${PLANE2_SYS_ID}" "${PLANE2_ROUTE_POINT2_LOG}" "    export PX4_TARGET_OFFSET_NORTH_M='${PLANE2_ROUTE_POINT2_NORTH_M}'
    export PX4_TARGET_OFFSET_EAST_M='${PLANE2_ROUTE_POINT2_EAST_M}'
    export PX4_TARGET_OFFSET_ALT_M='${PLANE2_ROUTE_POINT_ALT_M}'
    export PX4_LOITER_RADIUS_M='${PLANE2_ROUTE_LOITER_RADIUS_M}'
    export PX4_GROUNDSPEED_M_S='${PLANE2_ROUTE_GROUNDSPEED_M_S}'"
  sleep "${PLANE2_ROUTE_LEG_DWELL_SEC}"

  run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'do_reposition' "${PLANE2_SYS_ID}" "${PLANE2_ROUTE_POINT3_LOG}" "    export PX4_TARGET_OFFSET_NORTH_M='${PLANE2_ROUTE_POINT3_NORTH_M}'
    export PX4_TARGET_OFFSET_EAST_M='${PLANE2_ROUTE_POINT3_EAST_M}'
    export PX4_TARGET_OFFSET_ALT_M='${PLANE2_ROUTE_POINT_ALT_M}'
    export PX4_LOITER_RADIUS_M='${PLANE2_ROUTE_LOITER_RADIUS_M}'
    export PX4_GROUNDSPEED_M_S='${PLANE2_ROUTE_GROUNDSPEED_M_S}'"
  sleep "${PLANE2_ROUTE_LEG_DWELL_SEC}"

  run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'do_reposition' "${PLANE2_SYS_ID}" "${PLANE2_ROUTE_POINT4_LOG}" "    export PX4_TARGET_OFFSET_NORTH_M='${PLANE2_ROUTE_POINT4_NORTH_M}'
    export PX4_TARGET_OFFSET_EAST_M='${PLANE2_ROUTE_POINT4_EAST_M}'
    export PX4_TARGET_OFFSET_ALT_M='${PLANE2_ROUTE_POINT_ALT_M}'
    export PX4_LOITER_RADIUS_M='${PLANE2_ROUTE_LOITER_RADIUS_M}'
    export PX4_GROUNDSPEED_M_S='${PLANE2_ROUTE_GROUNDSPEED_M_S}'"
}

run_local_position_waiter() {
  local namespace="$1"
  local local_position_topic="$2"
  local output_file="$3"
  local timeout_sec="$4"
  local min_delta_xy_norm="$5"
  local max_delta_z="$6"
  local min_delta_z="${7:-}"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_LOCAL_POSITION_TOPIC='${local_position_topic}'
    export PX4_LOCAL_POSITION_TIMEOUT_SEC='${timeout_sec}'
    export PX4_MIN_DELTA_XY_NORM='${min_delta_xy_norm}'
    export PX4_MAX_DELTA_Z='${max_delta_z}'
    export PX4_MIN_DELTA_Z='${min_delta_z}'
    ros2 run iconom_control vehicle_local_position_waiter
  " >"${output_file}" 2>&1
}

run_land_detected_waiter() {
  local namespace="$1"
  local land_detected_topic="$2"
  local output_file="$3"
  local timeout_sec="$4"
  local expected_landed="$5"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    export ICONOM_VEHICLE_NAMESPACE='${namespace}'
    export PX4_LAND_DETECTED_TOPIC='${land_detected_topic}'
    export PX4_LAND_DETECTED_TIMEOUT_SEC='${timeout_sec}'
    export PX4_EXPECTED_LANDED='${expected_landed}'
    ros2 run iconom_control vehicle_land_detected_waiter
  " >"${output_file}" 2>&1
}

assert_airborne_catch_state() {
  local namespace="$1"
  local local_position_topic="$2"
  local land_detected_topic="$3"
  local output_file="$4"
  local min_altitude_m="$5"

  ros2_exec "
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    set -u
    python3 - <<'PY'
import re
import subprocess
import sys

def echo_once(topic: str) -> str:
    result = subprocess.run(
        ['bash', '-lc', f'timeout 10 ros2 topic echo --once {topic} 2>/dev/null || true'],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout

local_position = echo_once('${local_position_topic}')
land_detected = echo_once('${land_detected_topic}')

z_match = re.search(r'^\s*z:\s*([-0-9.]+)\s*$', local_position, re.MULTILINE)
landed_match = re.search(r'^\s*landed:\s*(true|false)\s*$', land_detected, re.MULTILINE)

if z_match is None:
    print('failed to read vehicle_local_position z for airborne catch gate', file=sys.stderr)
    print(local_position, file=sys.stderr)
    raise SystemExit(1)
if landed_match is None:
    print('failed to read vehicle_land_detected landed flag for airborne catch gate', file=sys.stderr)
    print(land_detected, file=sys.stderr)
    raise SystemExit(1)

z_value = float(z_match.group(1))
landed = landed_match.group(1).lower() == 'true'
altitude_agl = -z_value
print(f'airborne catch gate: z={z_value:.2f} altitude_agl={altitude_agl:.2f} landed={landed}')
if altitude_agl < float(${min_altitude_m}):
    print(f'catch happened too low: altitude_agl={altitude_agl:.2f}m < required {float(${min_altitude_m}):.2f}m', file=sys.stderr)
    raise SystemExit(1)
if landed:
    print('catch happened after ownship had already landed', file=sys.stderr)
    raise SystemExit(1)
PY
  " >"${output_file}" 2>&1
}

wait_for_topics() {
  local topics="$1"
  local timeout_sec="$2"
  local graph
  for ((i = 1; i <= timeout_sec; i++)); do
    if [[ -n "${PX4_PID_1}" ]] && ! kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
      wait "${PX4_PID_1}" || true
      echo "plane_01 px4 runtime exited before live-rival cueing topic discovery" >&2
      cat "${PX4_LOG_1}" >&2 || true
      exit 201
    fi
    if [[ -n "${PX4_PID_2}" ]] && ! kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
      wait "${PX4_PID_2}" || true
      echo "plane_02 px4 runtime exited before live-rival cueing topic discovery" >&2
      cat "${PX4_LOG_2}" >&2 || true
      exit 202
    fi

    graph="$(ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; ros2 topic list 2>/dev/null || true')"
    local missing=0
    while IFS= read -r topic; do
      [[ -z "${topic}" ]] && continue
      if ! grep -qx "${topic}" <<<"${graph}"; then
        missing=1
        break
      fi
    done <<<"${topics}"
    if [[ "${missing}" == "0" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "required live-rival cueing topics did not appear before timeout" >&2
  exit 203
}

wait_for_state() {
  local expected="$1"
  local timeout_sec="$2"
  local output
  for ((i = 1; i <= timeout_sec; i++)); do
    output="$(ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; timeout 5 ros2 topic echo --once /guidance/pursuit_state 2>/dev/null || true')"
    if grep -q "data: ${expected}" <<<"${output}"; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for pursuit state ${expected}" >&2
  return 1
}

read_cue_error() {
  ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; timeout 10 ros2 topic echo --once /guidance/camera_cue_error_deg 2>/dev/null || true' | awk '/data:/{print $2; exit}'
}

wait_for_cue_error_hold_below() {
  local threshold_deg="$1"
  local hold_sec="$2"
  local timeout_sec="$3"
  local sample
  local best=""
  local hold_count=0
  for ((i = 1; i <= timeout_sec; i++)); do
    sample="$(read_cue_error)"
    if [[ -n "${sample}" ]]; then
      if [[ -z "${best}" ]] || awk "BEGIN { exit !(${sample} < ${best}) }"; then
        best="${sample}"
      fi
      if python3 - <<PY; then
value = float(${sample})
threshold = float(${threshold_deg})
raise SystemExit(0 if value <= threshold else 1)
PY
        hold_count=$((hold_count + 1))
        if ((hold_count >= hold_sec)); then
          printf '%s' "${sample}"
          return 0
        fi
      else
        hold_count=0
      fi
    else
      hold_count=0
    fi
    sleep 1
  done
  echo "timed out waiting for cue error <= ${threshold_deg} deg for ${hold_sec}s (best observed ${best} deg)" >&2
  return 1
}

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
    echo "DISPLAY is not set; GUI live-rival cueing requires a local X11 display" >&2
    exit 219
  fi
  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

PLANE1_NAMESPACE='plane_01'
PLANE2_NAMESPACE='plane_02'
PLANE1_SYS_ID='1'
PLANE2_SYS_ID='2'
PLANE1_COMMAND_TOPIC='/plane_01/fmu/in/vehicle_command'
PLANE2_COMMAND_TOPIC='/plane_02/fmu/in/vehicle_command'
PLANE1_ACK_TOPIC='/plane_01/fmu/out/vehicle_command_ack'
PLANE2_ACK_TOPIC='/plane_02/fmu/out/vehicle_command_ack'
PLANE1_STATUS_TOPIC='/plane_01/fmu/out/vehicle_status_v1'
PLANE2_STATUS_TOPIC='/plane_02/fmu/out/vehicle_status_v1'
PLANE1_LOCAL_POSITION_TOPIC='/plane_01/fmu/out/vehicle_local_position'
PLANE2_LOCAL_POSITION_TOPIC='/plane_02/fmu/out/vehicle_local_position'
PLANE1_GLOBAL_POSITION_TOPIC='/plane_01/fmu/out/vehicle_global_position'
PLANE2_GLOBAL_POSITION_TOPIC='/plane_02/fmu/out/vehicle_global_position'
DISCOVERY_WAIT_SEC="${PX4_COMMAND_DISCOVERY_WAIT_SEC:-60}"
STATUS_TIMEOUT_SEC="${PX4_STATUS_TIMEOUT_SEC:-25}"
TAKEOFF_ALT_OFFSET_M="${PX4_TARGET_OFFSET_ALT_M:-30.0}"
TAKEOFF_NAV_STATE="${PX4_EXPECTED_TAKEOFF_NAV_STATE:-17}"
LOITER_NAV_STATE="${PX4_EXPECTED_LOITER_NAV_STATE:-4}"
OFFBOARD_NAV_STATE="${PX4_EXPECTED_OFFBOARD_NAV_STATE:-14}"
TAKEOFF_MIN_DELTA_XY_NORM="${PX4_EXPECTED_TAKEOFF_MIN_DELTA_XY_NORM:-5.0}"
TAKEOFF_MAX_DELTA_Z="${PX4_EXPECTED_TAKEOFF_MAX_DELTA_Z:--0.5}"
BEARING_ERROR_TOPIC="/guidance/bearing_error_deg"
INITIAL_BEARING_ERROR_MIN_DEG="${PHASE6_INITIAL_BEARING_ERROR_MIN_DEG:-45.0}"
INITIAL_CUE_ERROR_MIN_DEG="${PHASE6_INITIAL_CUE_ERROR_MIN_DEG:-35.0}"
FINAL_BEARING_ERROR_MAX_DEG="${PHASE6_FINAL_BEARING_ERROR_MAX_DEG:-25.0}"
FINAL_CUE_ERROR_MAX_DEG="${PHASE6_FINAL_CUE_ERROR_MAX_DEG:-25.0}"
BEARING_IMPROVEMENT_MIN_DEG="${PHASE6_BEARING_IMPROVEMENT_MIN_DEG:-40.0}"
RIVAL_MIN_ROUTE_DISTANCE_M="${PHASE6_RIVAL_MIN_ROUTE_DISTANCE_M:-20.0}"
CUE_HOLD_SEC="${PHASE6_TRACK_HOLD_MIN_SEC:-${PHASE6_CUE_HOLD_SEC:-10}}"
CUE_ERROR_TIMEOUT_SEC="${PHASE6_CUE_ERROR_TIMEOUT_SEC:-90}"
CUE_WINDOW_SEC="${PHASE6_CUE_WINDOW_SEC:-55}"
LAND_NAV_STATE="${PX4_EXPECTED_LAND_NAV_STATE:-18}"
LAND_MIN_DELTA_Z="${PX4_EXPECTED_LAND_MIN_DELTA_Z:-10.0}"
LAND_DETECTED_TIMEOUT_SEC="${PX4_LAND_DETECTED_TIMEOUT_SEC:-120}"
CATCH_MIN_ALTITUDE_M="${PHASE6_CATCH_MIN_ALTITUDE_M:-10.0}"
INITIAL_RANGE_MIN_M="${PHASE6_INITIAL_RANGE_MIN_M:-80.0}"
RANGE_REDUCTION_MIN_M="${PHASE6_RANGE_REDUCTION_MIN_M:-40.0}"
FINAL_RANGE_MAX_M="${PHASE6_FINAL_RANGE_MAX_M:-60.0}"
TAIL_ANGLE_MAX_DEG="${PHASE6_TAIL_ANGLE_MAX_DEG:-45.0}"
HEADING_ALIGNMENT_MAX_DEG="${PHASE6_HEADING_ALIGNMENT_MAX_DEG:-35.0}"
PLANE2_ROUTE_POINT1_NORTH_M="${PHASE6_LIVE_RIVAL_RECT_POINT1_NORTH_M:-120.0}"
PLANE2_ROUTE_POINT1_EAST_M="${PHASE6_LIVE_RIVAL_RECT_POINT1_EAST_M:-0.0}"
PLANE2_ROUTE_POINT2_NORTH_M="${PHASE6_LIVE_RIVAL_RECT_POINT2_NORTH_M:-120.0}"
PLANE2_ROUTE_POINT2_EAST_M="${PHASE6_LIVE_RIVAL_RECT_POINT2_EAST_M:-0.0}"
PLANE2_ROUTE_POINT3_NORTH_M="${PHASE6_LIVE_RIVAL_RECT_POINT3_NORTH_M:-120.0}"
PLANE2_ROUTE_POINT3_EAST_M="${PHASE6_LIVE_RIVAL_RECT_POINT3_EAST_M:-0.0}"
PLANE2_ROUTE_POINT4_NORTH_M="${PHASE6_LIVE_RIVAL_RECT_POINT4_NORTH_M:-120.0}"
PLANE2_ROUTE_POINT4_EAST_M="${PHASE6_LIVE_RIVAL_RECT_POINT4_EAST_M:-0.0}"
PLANE2_ROUTE_POINT_ALT_M="${PHASE6_LIVE_RIVAL_RECT_POINT_ALT_M:-0.0}"
PLANE2_ROUTE_LEG_DWELL_SEC="${PHASE6_LIVE_RIVAL_RECT_LEG_DWELL_SEC:-6}"
PLANE2_ROUTE_LOITER_RADIUS_M="${PHASE6_LIVE_RIVAL_RECT_LOITER_RADIUS_M:-30.0}"
PLANE2_ROUTE_GROUNDSPEED_M_S="${PHASE6_LIVE_RIVAL_RECT_GROUNDSPEED_M_S:-12.0}"
CUE_THRUST_X="${PHASE6_CUE_THRUST_X:-0.66}"
CUE_ROLL_ANGLE_GAIN="${PHASE6_CUE_ROLL_ANGLE_GAIN:-0.80}"
CUE_MAX_ROLL_DEG="${PHASE6_CUE_MAX_ROLL_DEG:-35.0}"
CUE_PITCH_ANGLE_DEG="${PHASE6_CUE_PITCH_ANGLE_DEG:-2.0}"
CUE_PITCH_ANGLE_GAIN="${PHASE6_CUE_PITCH_ANGLE_GAIN:-0.02}"
CUE_MAX_PITCH_DEG="${PHASE6_CUE_MAX_PITCH_DEG:-12.0}"
CUE_ALTITUDE_ERROR_DEADBAND_M="${PHASE6_CUE_ALTITUDE_ERROR_DEADBAND_M:-3.0}"
CUE_CAPTURE_ERROR_DEG="${PHASE6_CUE_CAPTURE_ERROR_DEG:-20.0}"

REQUIRED_TOPICS=$(
  cat <<TOPICS
${PLANE1_COMMAND_TOPIC}
${PLANE2_COMMAND_TOPIC}
${PLANE1_ACK_TOPIC}
${PLANE2_ACK_TOPIC}
${PLANE1_STATUS_TOPIC}
${PLANE2_STATUS_TOPIC}
${PLANE1_LOCAL_POSITION_TOPIC}
${PLANE2_LOCAL_POSITION_TOPIC}
${PLANE1_GLOBAL_POSITION_TOPIC}
${PLANE2_GLOBAL_POSITION_TOPIC}
TOPICS
)

echo "iconom phase-6 live-rival geometry hardening check"
echo "gui mode: ${USE_GUI}"
echo
echo "this checks the standalone real-sim live-rival geometry hardening slice:"
echo "  - plane_01 and plane_02 start in the shared phase-4 runtime"
echo "  - both aircraft take off and stabilize"
echo "  - plane_02 publishes live rival state into /competition/rival/state"
echo "  - plane_01 runs the maintained phase-6 cueing path against the real plane_02 target"
echo "  - plane_02 flies a long straight live-rival route to support sustained stern-chase hold"
echo "  - recorded ownship-versus-rival geometry shows a sustained airborne stern-chase hold in the forward cone with meaningful range closure, final proximity, and heading alignment"
echo "  - after cueing, both aircraft must complete a successful landing"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, referee_server, xrce_agent, ros2_app, px4, and px4_plane_02"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo referee_server xrce_agent ros2_app px4 px4_plane_02

echo "step 4: starting gazebo, referee_server, xrce_agent, and ros2_app"
for service in gazebo referee_server xrce_agent ros2_app; do
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d --no-deps "${service}"
  sleep 2
done

RUNNING_SERVICES="$(${COMPOSE_CMD[@]} ${COMPOSE_ARGS[@]} ps --services --status running)"
for service in gazebo referee_server xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before phase-6 live-rival cueing" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 111
  fi
done

echo "step 5: preparing PX4 message, control, competition, and guidance packages"
ros2_exec "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  cd /workspaces/ros2_ws
  if [[ "${COLD_BUILD}" == "1" ]]; then
    rm -rf build install log
  fi
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  colcon build --merge-install --packages-up-to px4_msgs iconom_control iconom_competition iconom_guidance
"

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

echo "step 7: polling ROS 2 graph for dual-aircraft topics"
wait_for_topics "${REQUIRED_TOPICS}" "${DISCOVERY_WAIT_SEC}"

echo "step 8: bringing plane_02 to loiter as the live rival"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' '' 'true'
run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" 'arm' "${PLANE2_SYS_ID}" "${PLANE2_ARM_LOG}"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '2' '' ''
run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'nav_takeoff' "${PLANE2_SYS_ID}" "${PLANE2_TAKEOFF_LOG}" "export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${TAKEOFF_NAV_STATE}" ''
run_local_position_waiter "${PLANE2_NAMESPACE}" "${PLANE2_LOCAL_POSITION_TOPIC}" "${PLANE2_POSITION_LOG}" 40 "${TAKEOFF_MIN_DELTA_XY_NORM}" "${TAKEOFF_MAX_DELTA_Z}"
run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" 'mode_loiter' "${PLANE2_SYS_ID}" "${PLANE2_LOITER_LOG}"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LOITER_NAV_STATE}" ''

echo "step 9: bringing plane_01 to loiter as ownship"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' '' 'true'
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'arm' "${PLANE1_SYS_ID}" "${PLANE1_ARM_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '2' '' ''
run_navigation_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${PLANE1_GLOBAL_POSITION_TOPIC}" 'nav_takeoff' "${PLANE1_SYS_ID}" "${PLANE1_TAKEOFF_LOG}" "export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${TAKEOFF_NAV_STATE}" ''
run_local_position_waiter "${PLANE1_NAMESPACE}" "${PLANE1_LOCAL_POSITION_TOPIC}" "${PLANE1_POSITION_LOG}" 40 "${TAKEOFF_MIN_DELTA_XY_NORM}" "${TAKEOFF_MAX_DELTA_Z}"
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'mode_loiter' "${PLANE1_SYS_ID}" "${PLANE1_LOITER_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LOITER_NAV_STATE}" ''

echo "step 10: starting the live plane_01 ownship adapter"
ros2_exec "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export REF_HOST='referee_server'
  export REF_PORT='45678'
  export AIRCRAFT_ID='${PLANE1_NAMESPACE}'
  /workspaces/ros2_ws/install/bin/ownship_telemetry_adapter
" >"${OWNSHIP_ADAPTER_LOG}" 2>&1 &
OWNSHIP_ADAPTER_PID=$!

echo "step 11: starting the live plane_02 rival adapter"
ros2_exec "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  export RIVAL_AIRCRAFT_ID='${PLANE2_NAMESPACE}'
  /workspaces/ros2_ws/install/bin/live_rival_state_adapter
" >"${RIVAL_ADAPTER_LOG}" 2>&1 &
RIVAL_ADAPTER_PID=$!

echo "step 12: starting predictor and phase-6 guidance nodes"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/predictor" >"${PREDICTOR_LOG}" 2>&1 &
PREDICTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/target_selector" >"${SELECTOR_LOG}" 2>&1 &
SELECTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/intercept_planner --ros-args -p max_intercept_distance:=80.0" >"${PLANNER_LOG}" 2>&1 &
PLANNER_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/pursuit_state_machine" >"${STATE_MACHINE_LOG}" 2>&1 &
STATE_MACHINE_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/camera_cueing_bridge --ros-args -p vehicle_namespace:='${PLANE1_NAMESPACE}' -p publish_rate_hz:=20.0 -p thrust_x:=${CUE_THRUST_X} -p roll_angle_gain:=${CUE_ROLL_ANGLE_GAIN} -p max_roll_deg:=${CUE_MAX_ROLL_DEG} -p pitch_angle_deg:=${CUE_PITCH_ANGLE_DEG} -p pitch_angle_gain:=${CUE_PITCH_ANGLE_GAIN} -p max_pitch_deg:=${CUE_MAX_PITCH_DEG} -p altitude_error_deadband_m:=${CUE_ALTITUDE_ERROR_DEADBAND_M} -p capture_error_deg:=${CUE_CAPTURE_ERROR_DEG}" >"${CUEING_LOG}" 2>&1 &
CUEING_PID=$!

wait_for_topics $'/competition/ownship/state\n/competition/rival/state\n/competition/prediction/rival_position\n/guidance/selected_target\n/guidance/intercept_target\n/guidance/pursuit_state\n/guidance/camera_cue_error_deg' 30
wait_for_state pursue 30

echo "step 12b: starting the live-rival geometry monitor"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/cue_geometry_monitor --ros-args -p publish_period_sec:=0.2 -p forward_cone_deg:=${FINAL_CUE_ERROR_MAX_DEG} -p output_csv:='${CONTAINER_CSV_PATH}'" >"${MONITOR_LOG}" 2>&1 &
MONITOR_PID=$!
wait_for_topics "" 30

echo "step 13: starting the live-rival rectangular route on plane_02"
run_live_rival_rectangle_route >"${PLANE2_REPOSITION_LOG}" 2>&1 &
RIVAL_ROUTE_PID=$!
echo "step 14: sampling the initial cue error"
INITIAL_CUE_ERROR="$(read_cue_error)"
if [[ -z "${INITIAL_CUE_ERROR}" ]]; then
  echo "could not read the initial live-rival cue error" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 204
fi
if ! python3 - <<PY; then
value = float(${INITIAL_CUE_ERROR})
threshold = float(${INITIAL_CUE_ERROR_MIN_DEG})
raise SystemExit(0 if value >= threshold else 1)
PY
  echo "initial cue error ${INITIAL_CUE_ERROR} deg was below the expected off-axis threshold ${INITIAL_CUE_ERROR_MIN_DEG} deg" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 205
fi

echo "initial cue error: ${INITIAL_CUE_ERROR} deg"

echo "step 15: confirming the cueing bridge emits PX4 attitude offboard setpoints"
for ((i = 1; i <= 30; i++)); do
  if grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
    break
  fi
  sleep 1
done
if ! grep -q 'published cueing offboard setpoint' "${CUEING_LOG}"; then
  echo "camera cueing bridge did not publish any PX4 attitude offboard setpoint against the live rival" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 206
fi

echo "step 16: switching plane_01 into OFFBOARD for cueing"
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'mode_offboard' "${PLANE1_SYS_ID}" "${PLANE1_MODE_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${OFFBOARD_NAV_STATE}" ''

echo "step 17: running the live-rival geometry capture window before CSV validation"
sleep "${CUE_WINDOW_SEC}"

echo "step 18: stopping live-rival geometry capture and landing both aircraft"
stop_pid "${CUEING_PID}"
CUEING_PID=""
stop_pid "${MONITOR_PID}"
MONITOR_PID=""
stop_pid "${STATE_MACHINE_PID}"
STATE_MACHINE_PID=""
stop_pid "${PLANNER_PID}"
PLANNER_PID=""
stop_pid "${SELECTOR_PID}"
SELECTOR_PID=""
stop_pid "${PREDICTOR_PID}"
PREDICTOR_PID=""
stop_pid "${RIVAL_ADAPTER_PID}"
RIVAL_ADAPTER_PID=""
stop_pid "${OWNSHIP_ADAPTER_PID}"
OWNSHIP_ADAPTER_PID=""
stop_pid "${RIVAL_ROUTE_PID}"
RIVAL_ROUTE_PID=""
run_navigation_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${PLANE1_GLOBAL_POSITION_TOPIC}" 'nav_land' "${PLANE1_SYS_ID}" "${PLANE1_LAND_LOG}" ''
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LAND_NAV_STATE}" ''
run_land_detected_waiter "${PLANE1_NAMESPACE}" "/${PLANE1_NAMESPACE}/fmu/out/vehicle_land_detected" "${PLANE1_LAND_DETECTED_LOG}" "${LAND_DETECTED_TIMEOUT_SEC}" 'true'
run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'nav_land' "${PLANE2_SYS_ID}" "${PLANE2_LAND_LOG}" ''
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LAND_NAV_STATE}" ''
run_land_detected_waiter "${PLANE2_NAMESPACE}" "/${PLANE2_NAMESPACE}/fmu/out/vehicle_land_detected" "${PLANE2_LAND_DETECTED_LOG}" "${LAND_DETECTED_TIMEOUT_SEC}" 'true'

echo "step 19: validating the recorded live-rival geometry artifact"
GEOMETRY_SUMMARY="$("${ROOT_DIR}/scripts/evaluate-phase6-geometry.py" "${CSV_PATH}" --initial-bearing-min-deg "${INITIAL_BEARING_ERROR_MIN_DEG}" --bearing-improvement-min-deg "${BEARING_IMPROVEMENT_MIN_DEG}" --rival-route-min-distance-m "${RIVAL_MIN_ROUTE_DISTANCE_M}" --final-bearing-max-deg "${FINAL_BEARING_ERROR_MAX_DEG}" --final-cue-max-deg "${FINAL_CUE_ERROR_MAX_DEG}" --catch-min-altitude-m "${CATCH_MIN_ALTITUDE_M}" --hold-sec "${CUE_HOLD_SEC}" --initial-range-min-m "${INITIAL_RANGE_MIN_M}" --range-reduction-min-m "${RANGE_REDUCTION_MIN_M}" --final-range-max-m "${FINAL_RANGE_MAX_M}" --tail-angle-max-deg "${TAIL_ANGLE_MAX_DEG}" --heading-alignment-max-deg "${HEADING_ALIGNMENT_MAX_DEG}")"

echo "phase-6 live-rival geometry and recovery succeeded"
echo "initial cue error: ${INITIAL_CUE_ERROR} deg"
echo "${GEOMETRY_SUMMARY}"
echo "csv_path=${CSV_PATH}"
