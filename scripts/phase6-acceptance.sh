#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ICONOM_PHASE6_MODE:-headless}"
COLD_BUILD="${ICONOM_PHASE6_COLD_BUILD:-0}"

declare -a PRECHECKS=()
FINAL_CHECK=""

bootstrap_prechecks() {
  local build_label="incremental build"
  if [[ "${COLD_BUILD}" == "1" ]]; then
    build_label="cold rebuild"
  fi

  echo "================================================================"
  echo "bootstrapping shared phase-6 guidance workspace (${build_label})"
  echo "================================================================"
  docker compose --env-file .env.example build ros2_app
  docker compose --env-file .env.example run --rm -e ICONOM_PHASE6_COLD_BUILD="${COLD_BUILD}" ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    if [[ "${ICONOM_PHASE6_COLD_BUILD:-0}" == "1" ]]; then
      rm -rf build install log
    fi
    mkdir -p /workspaces/ros2_ws/src
    if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
      vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
    fi
    colcon build --packages-up-to px4_msgs iconom_guidance --merge-install
  '
  echo
}

usage() {
  cat <<'USAGE'
Usage: phase6-acceptance.sh [--headless|--gui] [--incremental|--cold]

Run the current phase-6 acceptance flow for pursuit guidance and live-rival cueing.

Environment:
  ICONOM_PHASE6_MODE=headless|gui
  ICONOM_PHASE6_COLD_BUILD=0|1
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

case "${MODE}" in
  headless)
    export PX4_HEADLESS=1
    unset ICONOM_USE_GUI || true
    ;;
  gui)
    if [[ -z "${DISPLAY:-}" ]]; then
      echo "DISPLAY is not set; phase-6 GUI acceptance requires a local X11 display" >&2
      exit 2
    fi
    export PX4_HEADLESS=0
    export ICONOM_USE_GUI=1
    ;;
  *)
    echo "unsupported phase-6 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

PRECHECKS=(
  "${ROOT_DIR}/scripts/check-phase6-target-selection.sh"
  "${ROOT_DIR}/scripts/check-phase6-intercept-planner.sh"
  "${ROOT_DIR}/scripts/check-phase6-pursuit-state-machine.sh"
)
FINAL_CHECK="${ROOT_DIR}/scripts/check-phase6-live-rival-cueing.sh"

echo "iconom phase-6 acceptance"
echo "mode: ${MODE}"
echo "build mode: $([[ "${COLD_BUILD}" == "1" ]] && echo cold || echo incremental)"
echo
echo "this runs the maintained phase-6 validation flow for pursuit guidance and live-rival cueing."
echo

bootstrap_prechecks
for check in "${PRECHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  ICONOM_PHASE6_REUSE_WORKSPACE=1 ICONOM_PHASE6_COLD_BUILD=0 PX4_HEADLESS=1 ICONOM_USE_GUI= "${check}"
  echo
done

echo "================================================================"
echo "running $(basename "${FINAL_CHECK}")"
echo "================================================================"
if [[ "${MODE}" == "gui" ]]; then
  ICONOM_PHASE6_COLD_BUILD="${COLD_BUILD}" ICONOM_USE_GUI=1 PX4_HEADLESS=0 "${FINAL_CHECK}"
else
  ICONOM_PHASE6_COLD_BUILD="${COLD_BUILD}" PX4_HEADLESS=1 ICONOM_USE_GUI= "${FINAL_CHECK}"
fi
echo

echo "phase-6 acceptance passed"
