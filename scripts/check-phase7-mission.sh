#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
NVIDIA_OVERRIDE_FILE="${ROOT_DIR}/docker-compose.nvidia.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--profile phase4 --profile phase5 --profile symbology --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

PX4_LOG_1="${ROOT_DIR}/.tmp-phase7-mission-px4-plane01.log"
PX4_LOG_2="${ROOT_DIR}/.tmp-phase7-mission-px4-plane02.log"
PLANE1_ARM_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-arm.log"
PLANE1_TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-takeoff.log"
PLANE1_LOITER_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-loiter.log"
PLANE1_STATUS_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-status.log"
PLANE1_POSITION_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-position.log"
PLANE1_MODE_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-mode.log"
# shellcheck disable=SC2034
PLANE1_AIRBORNE_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-airborne.log"
PLANE1_LAND_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-land.log"
# shellcheck disable=SC2034
PLANE1_LAND_POSITION_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-land-position.log"
PLANE1_LAND_DETECTED_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane01-land-detected.log"
PLANE2_ARM_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-arm.log"
PLANE2_TAKEOFF_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-takeoff.log"
PLANE2_LOITER_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-loiter.log"
PLANE2_REPOSITION_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-reposition.log"
# shellcheck disable=SC2034
PLANE2_ROUTE_POINT1_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-route-point1.log"
# shellcheck disable=SC2034
PLANE2_ROUTE_POINT2_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-route-point2.log"
# shellcheck disable=SC2034
PLANE2_ROUTE_POINT3_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-route-point3.log"
# shellcheck disable=SC2034
PLANE2_ROUTE_POINT4_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-route-point4.log"
PLANE2_LAND_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-land.log"
# shellcheck disable=SC2034
PLANE2_LAND_POSITION_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-land-position.log"
PLANE2_LAND_DETECTED_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-land-detected.log"
PLANE2_STATUS_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-status.log"
PLANE2_POSITION_LOG="${ROOT_DIR}/.tmp-phase7-mission-plane02-position.log"
OWNSHIP_ADAPTER_LOG="${ROOT_DIR}/.tmp-phase7-mission-ownship.log"
RIVAL_ADAPTER_LOG="${ROOT_DIR}/.tmp-phase7-mission-rival.log"
# shellcheck disable=SC2034
EKF_FUSION_LOG="${ROOT_DIR}/.tmp-phase7-mission-ekf.log"
VISUAL_EKF_LOG="${ROOT_DIR}/.tmp-phase7-mission-visual-ekf.log"
VISUAL_ESTIMATOR_LOG="${ROOT_DIR}/.tmp-phase7-mission-position-estimator.log"
SYMBOLOGY_LOG="${ROOT_DIR}/.tmp-phase7-mission-symbology.log"
COMPETITION_CLIENT_LOG="${ROOT_DIR}/.tmp-phase7-mission-competition-client.log"
PREDICTOR_LOG="${ROOT_DIR}/.tmp-phase7-mission-predictor.log"
SELECTOR_LOG="${ROOT_DIR}/.tmp-phase7-mission-selector.log"
PLANNER_LOG="${ROOT_DIR}/.tmp-phase7-mission-planner.log"
STATE_MACHINE_LOG="${ROOT_DIR}/.tmp-phase7-mission-state-machine.log"
CUEING_LOG="${ROOT_DIR}/.tmp-phase7-mission-cueing.log"
MONITOR_LOG="${ROOT_DIR}/.tmp-phase7-mission-monitor.log"
CSV_PATH="${ROOT_DIR}/ros2_ws/.tmp-phase7-mission.csv"
CONTAINER_CSV_PATH="/workspaces/ros2_ws/.tmp-phase7-mission.csv"
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
SYMBOLOGY_PID=""
EKF_FUSION_PID=""
VISUAL_EKF_PID=""
VISUAL_ESTIMATOR_PID=""
COMPETITION_CLIENT_PID=""
COLD_BUILD="${ICONOM_PHASE7_COLD_BUILD:-${ICONOM_PHASE6_COLD_BUILD:-0}}"
service=""
MISSION_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MISSION_EVIDENCE_DIR="${ROOT_DIR}/.sisyphus/evidence"
MISSION_EVIDENCE_BASE="${MISSION_EVIDENCE_DIR}/phase7-mission-${MISSION_STAMP}"
MISSION_EVIDENCE_CSV="${MISSION_EVIDENCE_BASE}.csv"
MISSION_EVIDENCE_CZML="${MISSION_EVIDENCE_BASE}.czml"

usage() {
  cat <<'USAGE'
Usage: check-phase7-mission.sh [--incremental|--cold]

Run the standalone phase-7 mission hardening check.

Options:
  --incremental   Use cached build (default)
  --cold          Force clean build
Environment:
  ICONOM_PHASE7_COLD_BUILD=0|1
  PHASE6_LIVE_RIVAL_ROUTE_POINTS="north,east;north,east;..."
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
  stop_pid "${SYMBOLOGY_PID}"
  stop_pid "${VISUAL_EKF_PID}"
  stop_pid "${VISUAL_ESTIMATOR_PID}"
  stop_pid "${EKF_FUSION_PID}"
  stop_pid "${CUEING_PID}"
  stop_pid "${MONITOR_PID}"
  stop_pid "${STATE_MACHINE_PID}"
  stop_pid "${PLANNER_PID}"
  stop_pid "${SELECTOR_PID}"
  stop_pid "${PREDICTOR_PID}"
  stop_pid "${RIVAL_ADAPTER_PID}"
  stop_pid "${OWNSHIP_ADAPTER_PID}"
  stop_pid "${COMPETITION_CLIENT_PID}"
  stop_pid "${RIVAL_ROUTE_PID}"
  stop_pid "${PX4_PID_2}"
  stop_pid "${PX4_PID_1}"
  if [[ "${exit_code}" == "0" ]]; then
    rm -f "${ROOT_DIR}"/.tmp-phase7-mission-*.log
  else
    echo "phase-7 mission logs kept under ${ROOT_DIR}/.tmp-phase7-mission-*.log" >&2
    echo "phase-7 mission CSV kept at ${CSV_PATH}" >&2
  fi
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}
trap 'cleanup "$?"' EXIT

ros2_exec() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc "$1"
}

# shellcheck disable=SC1090
source "${ROOT_DIR}/scripts/phase6-sim-time.sh"

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

route_points_default() {
  printf '%s;%s;%s;%s' "${PLANE2_ROUTE_POINT1_NORTH_M},${PLANE2_ROUTE_POINT1_EAST_M}" "${PLANE2_ROUTE_POINT2_NORTH_M},${PLANE2_ROUTE_POINT2_EAST_M}" "${PLANE2_ROUTE_POINT3_NORTH_M},${PLANE2_ROUTE_POINT3_EAST_M}" "${PLANE2_ROUTE_POINT4_NORTH_M},${PLANE2_ROUTE_POINT4_EAST_M}"
}

print_live_rival_route() {
  local route_spec="${PLANE2_ROUTE_POINTS_RAW:-$(route_points_default)}"
  local -a route_points=()
  local route_point=""
  local north_m=""
  local east_m=""
  local extra=""
  local leg_index=0

  IFS=';' read -r -a route_points <<<"${route_spec}"
  echo "resolved live-rival route:"
  for route_point in "${route_points[@]}"; do
    route_point="${route_point//[$'\t\r\n ']/}"
    [[ -z "${route_point}" ]] && continue
    IFS=',' read -r north_m east_m extra <<<"${route_point}"
    if [[ -z "${north_m}" || -z "${east_m}" || -n "${extra:-}" ]]; then
      echo "invalid PHASE6_LIVE_RIVAL_ROUTE_POINTS entry: '${route_point}' (expected north,east)" >&2
      exit 2
    fi
    leg_index=$((leg_index + 1))
    printf '  - point %d: north=%s east=%s alt=%s groundspeed=%s dwell=%s
' "${leg_index}" "${north_m}" "${east_m}" "${PLANE2_ROUTE_POINT_ALT_M}" "${PLANE2_ROUTE_GROUNDSPEED_M_S}" "${PLANE2_ROUTE_LEG_DWELL_SEC}"
  done
  if [[ "${leg_index}" -lt 2 ]]; then
    echo "live-rival route must contain at least 2 waypoints" >&2
    exit 2
  fi
}

run_route_leg() {
  local leg_index="$1"
  local north_m="$2"
  local east_m="$3"
  local output_file="$4"

  run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'do_reposition' "${PLANE2_SYS_ID}" "${output_file}" "    export PX4_TARGET_OFFSET_NORTH_M='${north_m}'
    export PX4_TARGET_OFFSET_EAST_M='${east_m}'
    export PX4_TARGET_OFFSET_ALT_M='${PLANE2_ROUTE_POINT_ALT_M}'
    export PX4_LOITER_RADIUS_M='${PLANE2_ROUTE_LOITER_RADIUS_M}'
    export PX4_GROUNDSPEED_M_S='${PLANE2_ROUTE_GROUNDSPEED_M_S}'"
}

run_live_rival_route() {
  local route_spec="${PLANE2_ROUTE_POINTS_RAW:-$(route_points_default)}"
  local -a route_points=()
  local route_point=""
  local north_m=""
  local east_m=""
  local extra=""
  local leg_index=0

  IFS=';' read -r -a route_points <<<"${route_spec}"
  for route_point in "${route_points[@]}"; do
    route_point="${route_point//[$'\t\r\n ']/}"
    [[ -z "${route_point}" ]] && continue
    IFS=',' read -r north_m east_m extra <<<"${route_point}"
    if [[ -z "${north_m}" || -z "${east_m}" || -n "${extra:-}" ]]; then
      echo "invalid PHASE6_LIVE_RIVAL_ROUTE_POINTS entry: '${route_point}' (expected north,east)" >&2
      return 2
    fi
    leg_index=$((leg_index + 1))
    run_route_leg "${leg_index}" "${north_m}" "${east_m}" "${ROOT_DIR}/.tmp-phase7-mission-plane02-route-leg${leg_index}.log"
    if ((leg_index < ${#route_points[@]})); then
      wait_for_sim_seconds "${PLANE2_ROUTE_LEG_DWELL_SEC}" "live-rival route leg ${leg_index} dwell"
    fi
  done

  if [[ "${leg_index}" -lt 2 ]]; then
    echo "live-rival route must contain at least 2 waypoints" >&2
    return 2
  fi
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

run_land_sequence() {
  local namespace="$1"
  local command_topic="$2"
  local ack_topic="$3"
  local global_position_topic="$4"
  local sys_id="$5"
  local land_log="$6"
  local status_log="$7"
  local land_detected_log="$8"

  if ! run_navigation_command "${namespace}" "${command_topic}" "${ack_topic}" "${global_position_topic}" 'nav_land' "${sys_id}" "${land_log}" ''; then
    run_vehicle_command "${namespace}" "${command_topic}" "${ack_topic}" 'mode_loiter' "${sys_id}" "${land_log}.fallback-loiter"
    run_navigation_command "${namespace}" "${command_topic}" "${ack_topic}" "${global_position_topic}" 'nav_land' "${sys_id}" "${land_log}" ''
  fi

  run_status_waiter "${namespace}" "/${namespace}/fmu/out/vehicle_status_v1" "${status_log}" "${STATUS_TIMEOUT_SEC}" '' "${LAND_NAV_STATE}" ''
  run_land_detected_waiter "${namespace}" "/${namespace}/fmu/out/vehicle_land_detected" "${land_detected_log}" "${LAND_DETECTED_TIMEOUT_SEC}" 'true'
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

wait_for_compose_services() {
  local timeout_sec="$1"
  local running_services
  local compose_service
  for ((i = 1; i <= timeout_sec; i++)); do
    running_services="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
    local all_running=1
    for compose_service in gazebo referee_server xrce_agent ros2_app ros_gz_bridge detector; do
      if ! grep -qx "${compose_service}" <<<"${running_services}"; then
        all_running=0
        break
      fi
    done
    if [[ "${all_running}" == "1" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for compose services to reach running state" >&2
  return 1
}

read_cue_error() {
  ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; timeout 10 ros2 topic echo --once /guidance/camera_cue_error_deg 2>/dev/null || true' | awk '/data:/{print $2; exit}'
}

read_longitudinal_phase() {
  ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; timeout 10 ros2 topic echo --once /guidance/longitudinal_phase 2>/dev/null || true' | awk '/data:/{print $2; exit}'
}

read_pursuit_state() {
  ros2_exec 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; timeout 10 ros2 topic echo --once /guidance/pursuit_state 2>/dev/null || true' | awk '/data:/{print $2; exit}'
}

wait_for_longitudinal_phase() {
  local expected_phase="$1"
  local timeout_sec="$2"
  local sample
  for ((i = 1; i <= timeout_sec; i++)); do
    sample="$(read_longitudinal_phase)"
    if [[ "${sample}" == "${expected_phase}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for longitudinal phase ${expected_phase}" >&2
  return 1
}

validate_visual_lock_during_route() {
  local route_pid="$1"
  local allow_non_lock_samples="$2"
  local post_route_hold_sec="$3"
  local phase
  local cue_error
  local non_lock_samples=0
  local lock_samples=0
  local total_samples=0

  while kill -0 "${route_pid}" >/dev/null 2>&1; do
    phase="$(read_pursuit_state)"
    cue_error="$(read_cue_error)"
    if [[ -n "${phase}" || -n "${cue_error}" ]]; then
      total_samples=$((total_samples + 1))
      if [[ "${phase}" == "pursue" && -n "${cue_error}" ]]; then
        lock_samples=$((lock_samples + 1))
      else
        non_lock_samples=$((non_lock_samples + 1))
      fi
      if ((non_lock_samples > allow_non_lock_samples)); then
        echo "visual lock dropped too often during chase (non-locked samples=${non_lock_samples}, allowed=${allow_non_lock_samples})" >&2
        return 1
      fi
    fi
    sleep 1
  done

  for ((i = 1; i <= post_route_hold_sec; i++)); do
    phase="$(read_pursuit_state)"
    cue_error="$(read_cue_error)"
    if [[ -n "${phase}" || -n "${cue_error}" ]]; then
      total_samples=$((total_samples + 1))
      if [[ "${phase}" == "pursue" && -n "${cue_error}" ]]; then
        lock_samples=$((lock_samples + 1))
      else
        non_lock_samples=$((non_lock_samples + 1))
      fi
      if ((non_lock_samples > allow_non_lock_samples)); then
        echo "visual lock dropped after chase route completion (non-locked samples=${non_lock_samples}, allowed=${allow_non_lock_samples})" >&2
        return 1
      fi
    fi
    sleep 1
  done

  if ((lock_samples == 0 || total_samples == 0)); then
    echo "visual lock validation had no pursue+cue samples" >&2
    return 1
  fi

  echo "visual lock validation samples: total=${total_samples} locked=${lock_samples} non_lock=${non_lock_samples}"
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
USE_NVIDIA="${ICONOM_USE_NVIDIA:-0}"
if [[ "${USE_GUI}" == "1" || "${PX4_HEADLESS:-1}" == "0" ]]; then
  require_file "${OVERRIDE_FILE}"
  if [[ -z "${DISPLAY:-}" ]]; then
    echo "DISPLAY is not set; GUI live-rival cueing requires a local X11 display" >&2
    exit 219
  fi
  COMPOSE_ARGS+=(-f "${OVERRIDE_FILE}")
fi

if [[ "${USE_NVIDIA}" == "1" ]]; then
  require_file "${NVIDIA_OVERRIDE_FILE}"
  COMPOSE_ARGS+=(-f "${NVIDIA_OVERRIDE_FILE}")
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
# shellcheck disable=SC2034
BEARING_ERROR_TOPIC="/guidance/bearing_error_deg"
# shellcheck disable=SC2034
INITIAL_BEARING_ERROR_MIN_DEG="${PHASE6_INITIAL_BEARING_ERROR_MIN_DEG:-45.0}"
# shellcheck disable=SC2034
INITIAL_CUE_ERROR_MIN_DEG="${PHASE6_INITIAL_CUE_ERROR_MIN_DEG:-35.0}"
# shellcheck disable=SC2034
FINAL_BEARING_ERROR_MAX_DEG="${PHASE6_FINAL_BEARING_ERROR_MAX_DEG:-25.0}"
# shellcheck disable=SC2034
FINAL_CUE_ERROR_MAX_DEG="${PHASE6_FINAL_CUE_ERROR_MAX_DEG:-25.0}"
# shellcheck disable=SC2034
BEARING_IMPROVEMENT_MIN_DEG="${PHASE6_BEARING_IMPROVEMENT_MIN_DEG:-40.0}"
# shellcheck disable=SC2034
RIVAL_MIN_ROUTE_DISTANCE_M="${PHASE6_RIVAL_MIN_ROUTE_DISTANCE_M:-20.0}"
# shellcheck disable=SC2034
CUE_HOLD_SEC="${PHASE6_TRACK_HOLD_MIN_SEC:-${PHASE6_CUE_HOLD_SEC:-10}}"
# shellcheck disable=SC2034
CUE_ERROR_TIMEOUT_SEC="${PHASE6_CUE_ERROR_TIMEOUT_SEC:-90}"
# shellcheck disable=SC2034
CUE_WINDOW_SEC="${PHASE6_CUE_WINDOW_SEC:-110}"
LAND_NAV_STATE="${PX4_EXPECTED_LAND_NAV_STATE:-18}"
# shellcheck disable=SC2034
LAND_MIN_DELTA_Z="${PX4_EXPECTED_LAND_MIN_DELTA_Z:-10.0}"
LAND_DETECTED_TIMEOUT_SEC="${PX4_LAND_DETECTED_TIMEOUT_SEC:-120}"
# shellcheck disable=SC2034
CATCH_MIN_ALTITUDE_M="${PHASE6_CATCH_MIN_ALTITUDE_M:-10.0}"
# shellcheck disable=SC2034
INITIAL_RANGE_MIN_M="${PHASE6_INITIAL_RANGE_MIN_M:-80.0}"
# shellcheck disable=SC2034
RANGE_REDUCTION_MIN_M="${PHASE6_RANGE_REDUCTION_MIN_M:-40.0}"
# shellcheck disable=SC2034
FINAL_RANGE_MAX_M="${PHASE6_FINAL_RANGE_MAX_M:-60.0}"
# shellcheck disable=SC2034
TAIL_ANGLE_MAX_DEG="${PHASE6_TAIL_ANGLE_MAX_DEG:-45.0}"
# shellcheck disable=SC2034
HEADING_ALIGNMENT_MAX_DEG="${PHASE6_HEADING_ALIGNMENT_MAX_DEG:-35.0}"
PLANE2_ROUTE_POINT1_NORTH_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT1_NORTH_M:-120.0}"
PLANE2_ROUTE_POINT1_EAST_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT1_EAST_M:-0.0}"
PLANE2_ROUTE_POINT2_NORTH_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT2_NORTH_M:-240.0}"
PLANE2_ROUTE_POINT2_EAST_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT2_EAST_M:-0.0}"
PLANE2_ROUTE_POINT3_NORTH_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT3_NORTH_M:-360.0}"
PLANE2_ROUTE_POINT3_EAST_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT3_EAST_M:-0.0}"
PLANE2_ROUTE_POINT4_NORTH_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT4_NORTH_M:-480.0}"
PLANE2_ROUTE_POINT4_EAST_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT4_EAST_M:-0.0}"
PLANE2_ROUTE_POINT_ALT_M="${PHASE6_LIVE_RIVAL_STRAIGHT_POINT_ALT_M:-0.0}"
PLANE2_ROUTE_LEG_DWELL_SEC="${PHASE6_LIVE_RIVAL_STRAIGHT_LEG_DWELL_SEC:-8}"
PLANE2_ROUTE_LOITER_RADIUS_M="${PHASE6_LIVE_RIVAL_STRAIGHT_LOITER_RADIUS_M:-20.0}"
PLANE2_ROUTE_GROUNDSPEED_M_S="${PHASE6_LIVE_RIVAL_STRAIGHT_GROUNDSPEED_M_S:-12.0}"
PLANE2_ROUTE_POINTS_RAW="${PHASE6_LIVE_RIVAL_ROUTE_POINTS:-}"
CUE_THRUST_X="${PHASE6_CUE_THRUST_X:-0.66}"
CUE_MIN_THRUST_X="${PHASE6_CUE_MIN_THRUST_X:-0.36}"
CUE_RANGE_THRUST_GAIN="${PHASE6_CUE_RANGE_THRUST_GAIN:-0.075}"
CUE_RANGE_DAMPING_GAIN="${PHASE6_CUE_RANGE_DAMPING_GAIN:-0.04}"
CUE_RANGE_INTEGRAL_GAIN="${PHASE6_CUE_RANGE_INTEGRAL_GAIN:-0.04}"
CUE_RANGE_INTEGRAL_LIMIT="${PHASE6_CUE_RANGE_INTEGRAL_LIMIT:-180.0}"
TARGET_CHASE_RANGE_M="${PHASE6_TARGET_CHASE_RANGE_M:-1.0}"
CHASE_RANGE_TOLERANCE_M="${PHASE6_CHASE_RANGE_TOLERANCE_M:-1.0}"
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
/clock
TOPICS
)

echo "iconom phase-7 mission hardening check"
echo "gui mode: ${USE_GUI}"
echo "nvidia mode: ${USE_NVIDIA}"
if [[ -n "${PLANE2_ROUTE_POINTS_RAW}" ]]; then
  echo "live-rival route points: ${PLANE2_ROUTE_POINTS_RAW}"
else
  echo "live-rival route points: default straight route"
fi
echo
echo "this runs a full phase-7 visual mission profile in the shared simulation stack:"
echo "  - plane_01 and plane_02 start in the shared phase-4 runtime"
echo "  - detector + estimator + visual ekf + symbology overlay are launched first"
echo "  - guidance stack is launched before takeoff"
echo "  - rival then ownship arm, takeoff, and transition to loiter"
echo "  - ownship reaches pursue + follow_lock, transitions to offboard, and chases a routed rival"
echo "  - visual lock must stay in follow_lock during the chase window"
echo "  - both aircraft complete a successful landing"
echo
print_live_rival_route
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, referee_server, xrce_agent, ros2_app, ros_gz_bridge, detector, px4, and px4_plane_02"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo referee_server xrce_agent ros2_app ros_gz_bridge detector px4 px4_plane_02

echo "step 4: starting gazebo, referee_server, xrce_agent, ros2_app, ros_gz_bridge, and detector"
for service in gazebo referee_server xrce_agent ros2_app ros_gz_bridge detector; do
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d --no-deps "${service}"
  sleep 2
done

wait_for_compose_services 60

echo "step 5: preparing PX4 message, control, competition, guidance, and vision packages"
# shellcheck disable=SC2140
ros2_exec "
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  cd /workspaces/ros2_ws
  if [[ ${COLD_BUILD} == 1 ]]; then
    rm -rf build install log
  fi
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  colcon build --merge-install --packages-up-to px4_msgs iconom_control iconom_competition iconom_guidance iconom_vision
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

echo "step 8: launching visual pipeline nodes (estimator, visual EKF, overlay)"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; ros2 run iconom_vision position_estimator --ros-args -p detections_topic:=/vision/detections -p camera_info_topic:=/plane_01/camera/camera_info -p ownship_topic:=/competition/ownship/state -p rival_pose_topic:=/vision/rival_pose -p use_sim_time:=true" >"${VISUAL_ESTIMATOR_LOG}" 2>&1 &
VISUAL_ESTIMATOR_PID=$!

ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; env PYTHONPATH=/workspaces/ros2_ws/src/iconom_competition:\${PYTHONPATH:-} python3 -m iconom_competition.ekf_fusion --ros-args -p high_rate_input_topic:=/vision/rival_pose -p high_rate_input_requires_follow_lock:=false -p publish_rate_hz:=30.0 -p use_sim_time:=true" >"${VISUAL_EKF_LOG}" 2>&1 &
VISUAL_EKF_PID=$!

ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; ros2 run iconom_vision camera_symbology_overlay --ros-args -p image_topic:=/plane_01/camera/image_raw -p camera_info_topic:=/plane_01/camera/camera_info -p ownship_topic:=/competition/ownship/state -p use_sim_time:=true" >"${SYMBOLOGY_LOG}" 2>&1 &
SYMBOLOGY_PID=$!

wait_for_topics $'/vision/detections\n/vision/rival_pose\n/fusion/rival/state\n/plane_01/camera/image_overlay' 45

echo "step 9: launching guidance stack nodes"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; export REF_HOST='referee_server'; export REF_PORT='45678'; export AIRCRAFT_ID='${PLANE1_NAMESPACE}'; /workspaces/ros2_ws/install/bin/ownship_telemetry_adapter --ros-args -p use_sim_time:=true" >"${OWNSHIP_ADAPTER_LOG}" 2>&1 &
OWNSHIP_ADAPTER_PID=$!

ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; export REF_HOST='referee_server'; export REF_PORT='45678'; /workspaces/ros2_ws/install/bin/competition_client --ros-args -p use_sim_time:=true" >"${COMPETITION_CLIENT_LOG}" 2>&1 &
COMPETITION_CLIENT_PID=$!

RIVAL_PUBLISH_RATE_HZ="${RIVAL_PUBLISH_RATE_HZ:-20.0}"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; export RIVAL_AIRCRAFT_ID='${PLANE2_NAMESPACE}'; /workspaces/ros2_ws/install/bin/live_rival_state_adapter --ros-args -p use_sim_time:=true -p publish_rate_hz:=\"${RIVAL_PUBLISH_RATE_HZ}\"" >"${RIVAL_ADAPTER_LOG}" 2>&1 &
RIVAL_ADAPTER_PID=$!

TARGET_SELECTOR_RATE_HZ="${TARGET_SELECTOR_RATE_HZ:-20}"
SELECTOR_PERIOD_SEC=$(echo "scale=4; 1 / ${TARGET_SELECTOR_RATE_HZ}" | bc)
INTERCEPT_PLANNER_RATE_HZ="${INTERCEPT_PLANNER_RATE_HZ:-20}"
PLANNER_PERIOD_SEC=$(echo "scale=4; 1 / ${INTERCEPT_PLANNER_RATE_HZ}" | bc)
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/predictor --ros-args -p use_sim_time:=true" >"${PREDICTOR_LOG}" 2>&1 &
PREDICTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/target_selector --ros-args -p use_sim_time:=true -p publish_period_sec:=\"${SELECTOR_PERIOD_SEC}\"" >"${SELECTOR_LOG}" 2>&1 &
SELECTOR_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/intercept_planner --ros-args -p use_sim_time:=true -p max_intercept_distance:=80.0 -p publish_period_sec:=\"${PLANNER_PERIOD_SEC}\"" >"${PLANNER_LOG}" 2>&1 &
PLANNER_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/pursuit_state_machine --ros-args -p use_sim_time:=true" >"${STATE_MACHINE_LOG}" 2>&1 &
STATE_MACHINE_PID=$!
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/camera_cueing_bridge --ros-args -p use_sim_time:=true -p vehicle_namespace:='${PLANE1_NAMESPACE}' -p publish_rate_hz:=20.0 -p thrust_x:=${CUE_THRUST_X} -p roll_angle_gain:=${CUE_ROLL_ANGLE_GAIN} -p max_roll_deg:=${CUE_MAX_ROLL_DEG} -p pitch_angle_deg:=${CUE_PITCH_ANGLE_DEG} -p pitch_angle_gain:=${CUE_PITCH_ANGLE_GAIN} -p max_pitch_deg:=${CUE_MAX_PITCH_DEG} -p altitude_error_deadband_m:=${CUE_ALTITUDE_ERROR_DEADBAND_M} -p min_thrust_x:=${CUE_MIN_THRUST_X} -p range_thrust_gain:=${CUE_RANGE_THRUST_GAIN} -p range_damping_gain:=${CUE_RANGE_DAMPING_GAIN} -p range_integral_gain:=${CUE_RANGE_INTEGRAL_GAIN} -p range_integral_limit:=${CUE_RANGE_INTEGRAL_LIMIT} -p target_chase_range_m:=${TARGET_CHASE_RANGE_M} -p chase_range_tolerance_m:=${CHASE_RANGE_TOLERANCE_M} -p capture_error_deg:=${CUE_CAPTURE_ERROR_DEG}" >"${CUEING_LOG}" 2>&1 &
CUEING_PID=$!

wait_for_topics $'/competition/ownship/state\n/competition/rival/state\n/competition/prediction/rival_position\n/guidance/selected_target\n/guidance/intercept_target\n/guidance/pursuit_state\n/guidance/camera_cue_error_deg\n/guidance/longitudinal_phase' 45

echo "step 10: bringing plane_02 to loiter as the live rival"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' '' ''
run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" 'arm' "${PLANE2_SYS_ID}" "${PLANE2_ARM_LOG}"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '2' '' ''
run_navigation_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" 'nav_takeoff' "${PLANE2_SYS_ID}" "${PLANE2_TAKEOFF_LOG}" "export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${TAKEOFF_NAV_STATE}" ''
run_local_position_waiter "${PLANE2_NAMESPACE}" "${PLANE2_LOCAL_POSITION_TOPIC}" "${PLANE2_POSITION_LOG}" 40 "${TAKEOFF_MIN_DELTA_XY_NORM}" "${TAKEOFF_MAX_DELTA_Z}"
run_vehicle_command "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" 'mode_loiter' "${PLANE2_SYS_ID}" "${PLANE2_LOITER_LOG}"
run_status_waiter "${PLANE2_NAMESPACE}" "${PLANE2_STATUS_TOPIC}" "${PLANE2_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LOITER_NAV_STATE}" ''

echo "step 11: bringing plane_01 to loiter as ownship"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' '' ''
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'arm' "${PLANE1_SYS_ID}" "${PLANE1_ARM_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '2' '' ''
run_navigation_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${PLANE1_GLOBAL_POSITION_TOPIC}" 'nav_takeoff' "${PLANE1_SYS_ID}" "${PLANE1_TAKEOFF_LOG}" "export PX4_TARGET_OFFSET_ALT_M='${TAKEOFF_ALT_OFFSET_M}'"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${TAKEOFF_NAV_STATE}" ''
run_local_position_waiter "${PLANE1_NAMESPACE}" "${PLANE1_LOCAL_POSITION_TOPIC}" "${PLANE1_POSITION_LOG}" 40 "${TAKEOFF_MIN_DELTA_XY_NORM}" "${TAKEOFF_MAX_DELTA_Z}"
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'mode_loiter' "${PLANE1_SYS_ID}" "${PLANE1_LOITER_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${LOITER_NAV_STATE}" ''

echo "step 12: waiting for pursue state"
wait_for_state pursue 90

echo "step 12b: starting the visual tracking geometry monitor"
ros2_exec "set -euo pipefail; set +u; source /opt/ros/humble/setup.bash; source /workspaces/ros2_ws/install/setup.bash; set -u; /workspaces/ros2_ws/install/bin/cue_geometry_monitor --ros-args -p use_sim_time:=true -p publish_period_sec:=0.2 -p output_csv:='${CONTAINER_CSV_PATH}'" >"${MONITOR_LOG}" 2>&1 &
MONITOR_PID=$!

sleep 2
if ! kill -0 "${MONITOR_PID}" >/dev/null 2>&1; then
  echo "geometry monitor failed to start" >&2
  cat "${MONITOR_LOG}" >&2 || true
  exit 207
fi

echo "step 13: confirming cueing bridge emits PX4 attitude offboard setpoints"
for ((i = 1; i <= 30; i++)); do
  if grep -q 'published trailing-slot cueing setpoint' "${CUEING_LOG}"; then
    break
  fi
  sleep 1
done
if ! grep -q 'published trailing-slot cueing setpoint' "${CUEING_LOG}"; then
  echo "camera cueing bridge did not publish any PX4 attitude offboard setpoint against visual fused target" >&2
  cat "${CUEING_LOG}" >&2 || true
  exit 206
fi

echo "step 14: switching plane_01 into OFFBOARD for cueing"
run_vehicle_command "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" 'mode_offboard' "${PLANE1_SYS_ID}" "${PLANE1_MODE_LOG}"
run_status_waiter "${PLANE1_NAMESPACE}" "${PLANE1_STATUS_TOPIC}" "${PLANE1_STATUS_LOG}" "${STATUS_TIMEOUT_SEC}" '' "${OFFBOARD_NAV_STATE}" ''

echo "step 15: starting the live-rival route on plane_02"
run_live_rival_route >"${PLANE2_REPOSITION_LOG}" 2>&1 &
RIVAL_ROUTE_PID=$!

echo "step 16: validating visual tracking lock throughout chase"
VISUAL_LOCK_ALLOWED_DROPS="${PHASE7_VISUAL_LOCK_ALLOWED_DROPS:-6}"
VISUAL_LOCK_POST_ROUTE_HOLD_SEC="${PHASE7_VISUAL_LOCK_POST_ROUTE_HOLD_SEC:-8}"
LOCK_SUMMARY="$(validate_visual_lock_during_route "${RIVAL_ROUTE_PID}" "${VISUAL_LOCK_ALLOWED_DROPS}" "${VISUAL_LOCK_POST_ROUTE_HOLD_SEC}")"
echo "${LOCK_SUMMARY}"
if ! wait "${RIVAL_ROUTE_PID}"; then
  echo "rival route command sequence failed" >&2
  exit 208
fi
RIVAL_ROUTE_PID=""

echo "step 17: landing both aircraft"
stop_pid "${MONITOR_PID}"
MONITOR_PID=""
stop_pid "${CUEING_PID}"
CUEING_PID=""
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
stop_pid "${COMPETITION_CLIENT_PID}"
COMPETITION_CLIENT_PID=""
stop_pid "${VISUAL_ESTIMATOR_PID}"
VISUAL_ESTIMATOR_PID=""
stop_pid "${VISUAL_EKF_PID}"
VISUAL_EKF_PID=""
stop_pid "${SYMBOLOGY_PID}"
SYMBOLOGY_PID=""
run_land_sequence "${PLANE1_NAMESPACE}" "${PLANE1_COMMAND_TOPIC}" "${PLANE1_ACK_TOPIC}" "${PLANE1_GLOBAL_POSITION_TOPIC}" "${PLANE1_SYS_ID}" "${PLANE1_LAND_LOG}" "${PLANE1_STATUS_LOG}" "${PLANE1_LAND_DETECTED_LOG}"
run_land_sequence "${PLANE2_NAMESPACE}" "${PLANE2_COMMAND_TOPIC}" "${PLANE2_ACK_TOPIC}" "${PLANE2_GLOBAL_POSITION_TOPIC}" "${PLANE2_SYS_ID}" "${PLANE2_LAND_LOG}" "${PLANE2_STATUS_LOG}" "${PLANE2_LAND_DETECTED_LOG}"

mkdir -p "${MISSION_EVIDENCE_DIR}"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" cp "ros2_app:${CONTAINER_CSV_PATH}" "${CSV_PATH}"
cp "${CSV_PATH}" "${MISSION_EVIDENCE_CSV}"
python3 "${ROOT_DIR}/scripts/export-phase6-czml.py" "${MISSION_EVIDENCE_CSV}" -o "${MISSION_EVIDENCE_CZML}"

echo "phase-7 mission profile succeeded"
echo "visual lock summary: ${LOCK_SUMMARY}"
echo "mission csv: ${MISSION_EVIDENCE_CSV}"
echo "mission czml: ${MISSION_EVIDENCE_CZML}"
