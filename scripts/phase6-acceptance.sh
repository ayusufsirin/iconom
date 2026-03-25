#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ICONOM_PHASE6_MODE:-headless}"

declare -a PRECHECKS=()
FINAL_CHECK=""

usage() {
  cat <<'USAGE'
Usage: phase6-acceptance.sh [--headless|--gui]

Run the current phase-6 acceptance flow for pursuit guidance and live-rival cueing.

Environment:
  ICONOM_PHASE6_MODE=headless|gui
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
echo
echo "this runs the maintained phase-6 validation flow for pursuit guidance and live-rival cueing."
echo

for check in "${PRECHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  PX4_HEADLESS=1 ICONOM_USE_GUI= "${check}"
  echo
done

echo "================================================================"
echo "running $(basename "${FINAL_CHECK}")"
echo "================================================================"
if [[ "${MODE}" == "gui" ]]; then
  ICONOM_USE_GUI=1 PX4_HEADLESS=0 "${FINAL_CHECK}"
else
  PX4_HEADLESS=1 ICONOM_USE_GUI= "${FINAL_CHECK}"
fi
echo

echo "phase-6 acceptance passed"
