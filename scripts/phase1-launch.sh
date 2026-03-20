#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEADLESS_SCRIPT="${ROOT_DIR}/scripts/bringup-single-vehicle.sh"
GUI_SCRIPT="${ROOT_DIR}/scripts/bringup-single-vehicle-gui.sh"

MODE="${ICONOM_PHASE1_MODE:-headless}"

usage() {
  cat <<'EOF'
Usage: phase1-launch.sh [--gui | --headless]

Launch the current phase-1 single-vehicle simulation and keep it running.

Environment:
  ICONOM_PHASE1_MODE=headless|gui
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gui)
      MODE="gui"
      shift
      ;;
    --headless)
      MODE="headless"
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
  gui)
    echo "phase-1 launch mode: gui"
    exec "${GUI_SCRIPT}"
    ;;
  headless)
    echo "phase-1 launch mode: headless"
    exec "${HEADLESS_SCRIPT}"
    ;;
  *)
    echo "unsupported phase-1 launch mode: ${MODE}" >&2
    exit 2
    ;;
esac
