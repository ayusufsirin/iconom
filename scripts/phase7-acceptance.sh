#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${ROOT_DIR}/.sisyphus/evidence"
MODE="${ICONOM_PHASE7_MODE:-headless}"

FINAL_PREFIX="task-final-phase7-harness"

DETECTION_CHECK="${ROOT_DIR}/scripts/check-phase7-detection.sh"
POSITION_CHECK="${ROOT_DIR}/scripts/check-phase7-position-estimation.sh"
FUSION_CHECK="${ROOT_DIR}/scripts/check-phase7-fusion.sh"

usage() {
  cat <<'USAGE'
Usage: phase7-acceptance.sh [--headless|--gui]

Run the maintained phase-7 acceptance flow.

Environment:
  ICONOM_PHASE7_MODE=headless|gui
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless)
      MODE="headless"
      shift
      ;;
    --gui)
      MODE="gui"
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

case "${MODE}" in
  headless)
    export PX4_HEADLESS=1
    unset ICONOM_USE_GUI || true
    ;;
  gui)
    if [[ -z "${DISPLAY:-}" ]]; then
      echo "DISPLAY is not set; phase-7 GUI acceptance requires a local X11 display" >&2
      exit 2
    fi
    export PX4_HEADLESS=0
    export ICONOM_USE_GUI=1
    ;;
  *)
    echo "unsupported phase-7 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

mkdir -p "${EVIDENCE_DIR}"

log() {
  printf '%s\n' "$*"
}

run_and_log() {
  local label="$1"
  shift
  local log_file="${EVIDENCE_DIR}/${FINAL_PREFIX}-${label}.log"

  log "================================================================"
  log "running ${label}"
  log "================================================================"
  : > "${log_file}"
  "$@" 2>&1 | tee -a "${log_file}"
  log
}

copy_artifact() {
  local src="$1"
  local dst="$2"

  if [[ -f "${src}" ]]; then
    cp "${src}" "${dst}"
  fi
}

run_downstream_smoke_test() {
  local smoke_log="${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke.log"
  local ros2_app_service="iconom-ros2_app-1"
  local smoke_script

  log "================================================================"
  log "running downstream fused-input smoke test"
  log "================================================================"

  docker compose -f "${ROOT_DIR}/docker-compose.yml" up -d ros2_app >/dev/null

  docker exec "${ros2_app_service}" bash -lc '
    set -eo pipefail
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
    fi
    cd /workspaces/ros2_ws
    colcon build --merge-install --packages-select iconom_guidance >/tmp/task-final-phase7-harness-smoke-build.log 2>&1
    source install/setup.bash >/dev/null 2>&1 || true

    ros2 topic pub -r 10 /competition/ownship/state geometry_msgs/msg/PoseStamped "{header: {frame_id: map}, pose: {orientation: {w: 1.0}}}" >/tmp/task-final-phase7-harness-smoke-ownship-pub.log 2>&1 &
    ownship_pub_pid=$!
    ros2 topic pub -r 10 /fusion/rival/state geometry_msgs/msg/PoseStamped "{header: {frame_id: map}, pose: {position: {x: 5.0, y: 1.0, z: 10.0}, orientation: {w: 1.0}}}" >/tmp/task-final-phase7-harness-smoke-fused-pub.log 2>&1 &
    fused_pub_pid=$!
    ros2 topic pub -r 10 /guidance/pursuit_state std_msgs/msg/String "{data: pursue}" >/tmp/task-final-phase7-harness-smoke-pursuit-pub.log 2>&1 &
    pursuit_pub_pid=$!

    /workspaces/ros2_ws/install/bin/camera_cueing_bridge --ros-args \
      -p use_fused_input:=true \
      -p fused_state_topic:=/fusion/rival/state \
      >/tmp/task-final-phase7-harness-smoke-bridge.log 2>&1 &
    bridge_pid=$!

    trap "kill ${bridge_pid} ${ownship_pub_pid} ${fused_pub_pid} ${pursuit_pub_pid} 2>/dev/null || true" EXIT
    sleep 3

    timeout 20 ros2 topic echo --once /guidance/camera_cue_error_deg >/tmp/task-final-phase7-harness-smoke-echo.log 2>&1
    timeout 20 ros2 topic info /guidance/camera_cue_error_deg >/tmp/task-final-phase7-harness-smoke-info.log 2>&1
  ' >>"${smoke_log}" 2>&1

  copy_artifact "/tmp/task-final-phase7-harness-smoke-build.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-build.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-publisher.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-publisher.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-ownship-pub.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-ownship-pub.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-fused-pub.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-fused-pub.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-pursuit-pub.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-pursuit-pub.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-bridge.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-bridge.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-echo.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-echo.log"
  copy_artifact "/tmp/task-final-phase7-harness-smoke-info.log" "${EVIDENCE_DIR}/${FINAL_PREFIX}-smoke-info.log"
}

run_gui_visual_evidence() {
  if [[ "${MODE}" != "gui" ]]; then
    log "ERROR: GUI evidence required but MODE=${MODE}; must re-run with --gui"
    return 1
  fi

  run_and_log "gui-harness" "${FUSION_CHECK}" --gui

  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-overlay-combined.png" "${EVIDENCE_DIR}/${FINAL_PREFIX}-gui.png"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-truth-stream.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-truth-stream.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-raw-stream.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-raw-stream.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-fused-stream.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-fused-stream.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-aligned.csv" "${EVIDENCE_DIR}/${FINAL_PREFIX}-aligned.csv"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-aligned.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-aligned.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-metrics-summary.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-metrics-summary.json"

  if command -v ffmpeg >/dev/null 2>&1 && [[ -f "${EVIDENCE_DIR}/${FINAL_PREFIX}-gui.png" ]]; then
    ffmpeg -y -loop 1 -i "${EVIDENCE_DIR}/${FINAL_PREFIX}-gui.png" -t 3 -pix_fmt yuv420p "${EVIDENCE_DIR}/${FINAL_PREFIX}-gui.mp4" >/dev/null 2>&1 || true
  fi

  log "gui evidence captured to ${EVIDENCE_DIR}/${FINAL_PREFIX}-gui.png"
}

write_manifest() {
  local manifest="${EVIDENCE_DIR}/${FINAL_PREFIX}-manifest.txt"

  cat > "${manifest}" <<EOF
phase7 acceptance manifest
mode: ${MODE}
slice validation: headless detection -> position estimation -> fusion
downstream smoke: camera_cueing_bridge use_fused_input=true fused_state_topic=/fusion/rival/state
gui evidence: $([[ "${MODE}" == "gui" ]] && printf 'captured' || printf 'skipped')
EOF
}

main() {
  log "iconom phase-7 acceptance"
  log "mode: ${MODE}"
  log

  run_and_log "slice2-detection" "${DETECTION_CHECK}" --headless
  run_and_log "slice3-position" "${POSITION_CHECK}" --headless
  run_and_log "slice4-fusion" "${FUSION_CHECK}" --headless

  run_downstream_smoke_test
  run_gui_visual_evidence

  copy_artifact "${EVIDENCE_DIR}/task-2-slice3-harness-aligned.csv" "${EVIDENCE_DIR}/${FINAL_PREFIX}-position-aligned.csv"
  copy_artifact "${EVIDENCE_DIR}/task-2-slice3-harness-aligned.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-position-aligned.json"
  copy_artifact "${EVIDENCE_DIR}/task-2-slice3-harness-metrics-summary.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-position-metrics.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-aligned.csv" "${EVIDENCE_DIR}/${FINAL_PREFIX}-fusion-aligned.csv"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-aligned.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-fusion-aligned.json"
  copy_artifact "${EVIDENCE_DIR}/task-3-slice4-harness-metrics-summary.json" "${EVIDENCE_DIR}/${FINAL_PREFIX}-fusion-metrics.json"

  write_manifest

  log "phase-7 acceptance passed"
}

main "$@"
