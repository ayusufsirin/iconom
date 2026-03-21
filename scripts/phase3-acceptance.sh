#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-nav-loiter.sh"

MODE="${ICONOM_PHASE3_MODE:-headless}"

usage() {
  cat <<'EOF'
Usage: phase3-acceptance.sh [--gui | --headless]

Run the current phase-3 acceptance flow against the single-vehicle stack.

Environment:
  ICONOM_PHASE3_MODE=headless|gui
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

export PX4_HEADLESS=1
unset ICONOM_USE_GUI || true

case "${MODE}" in
  gui)
    export ICONOM_USE_GUI=1
    export PX4_HEADLESS=0
    ;;
  headless)
    ;;
  *)
    echo "unsupported phase-3 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

echo "iconom phase-3 acceptance"
echo "mode: ${MODE}"
echo
echo "this runs the maintained phase-3 guidance validation for the single-vehicle stack."
echo
"${CHECK_SCRIPT}"
echo
echo "phase-3 acceptance passed"
