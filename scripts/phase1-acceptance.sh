#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${ICONOM_PHASE1_MODE:-headless}"
RUN_MOVEMENT="${ICONOM_PHASE1_RUN_MOVEMENT:-1}"
RUN_CAMERA_SUBSCRIBER="${ICONOM_PHASE1_RUN_CAMERA_SUBSCRIBER:-1}"

declare -a CHECKS=(
  "${ROOT_DIR}/scripts/check-px4-telemetry.sh"
  "${ROOT_DIR}/scripts/check-camera-bridge.sh"
)

usage() {
  cat <<'EOF'
Usage: phase1-acceptance.sh [--gui | --headless] [--skip-camera-subscriber] [--skip-movement]

Run the current phase-1 acceptance flow against the single-vehicle stack.

Environment:
  ICONOM_PHASE1_MODE=headless|gui
  ICONOM_PHASE1_RUN_CAMERA_SUBSCRIBER=0|1
  ICONOM_PHASE1_RUN_MOVEMENT=0|1
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
    --skip-camera-subscriber)
      RUN_CAMERA_SUBSCRIBER="0"
      shift
      ;;
    --skip-movement)
      RUN_MOVEMENT="0"
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

if [[ "${RUN_CAMERA_SUBSCRIBER}" == "1" ]]; then
  CHECKS+=("${ROOT_DIR}/scripts/check-camera-subscriber.sh")
fi

CHECKS+=(
  "${ROOT_DIR}/scripts/check-vehicle-command.sh"
  "${ROOT_DIR}/scripts/check-mode-command.sh"
  "${ROOT_DIR}/scripts/check-offboard-readiness.sh"
)

if [[ "${RUN_MOVEMENT}" == "1" ]]; then
  CHECKS+=("${ROOT_DIR}/scripts/check-offboard-movement.sh")
fi

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
    echo "unsupported phase-1 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

echo "iconom phase-1 acceptance"
echo "mode: ${MODE}"
echo "camera subscriber check: ${RUN_CAMERA_SUBSCRIBER}"
echo "offboard movement check: ${RUN_MOVEMENT}"
echo
echo "this runs the current maintained phase-1 validation flow for the single-vehicle stack."
echo

for check in "${CHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  "${check}"
  echo
done

echo "phase-1 acceptance passed"
