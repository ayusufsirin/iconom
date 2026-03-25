#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ICONOM_PHASE6_MODE:-headless}"

declare -a CHECKS=()

usage() {
  cat <<'USAGE'
Usage: phase6-acceptance.sh [--headless]

Run the current phase-6 acceptance flow for pursuit guidance and live-rival cueing.

Environment:
  ICONOM_PHASE6_MODE=headless
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
  headless)
    export PX4_HEADLESS=1
    unset ICONOM_USE_GUI || true
    ;;
  *)
    echo "unsupported phase-6 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

CHECKS=(
  "${ROOT_DIR}/scripts/check-phase6-target-selection.sh"
  "${ROOT_DIR}/scripts/check-phase6-intercept-planner.sh"
  "${ROOT_DIR}/scripts/check-phase6-pursuit-state-machine.sh"
  "${ROOT_DIR}/scripts/check-phase6-live-rival-cueing.sh"
)

echo "iconom phase-6 acceptance"
echo "mode: ${MODE}"
echo
echo "this runs the maintained phase-6 validation flow for pursuit guidance and live-rival cueing."
echo

for check in "${CHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  "${check}"
  echo
done

echo "phase-6 acceptance passed"
