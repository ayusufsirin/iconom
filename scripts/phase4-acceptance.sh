#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ICONOM_PHASE4_MODE:-headless}"
RUN_RUNTIME_CONTRACT="${ICONOM_PHASE4_RUN_RUNTIME_CONTRACT:-1}"

declare -a CHECKS=()

usage() {
  cat <<'USAGE'
Usage: phase4-acceptance.sh [--headless] [--skip-runtime-contract]

Run the current phase-4 acceptance flow against the maintained dual-aircraft stack.

Environment:
  ICONOM_PHASE4_MODE=headless
  ICONOM_PHASE4_RUN_RUNTIME_CONTRACT=0|1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless)
      MODE="headless"
      shift
      ;;
    --skip-runtime-contract)
      RUN_RUNTIME_CONTRACT="0"
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
    echo "unsupported phase-4 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

if [[ "${RUN_RUNTIME_CONTRACT}" == "1" ]]; then
  CHECKS+=("${ROOT_DIR}/scripts/check-phase4-runtime-contract.sh")
fi

CHECKS+=(
  "${ROOT_DIR}/scripts/check-phase4-isolation.sh"
  "${ROOT_DIR}/scripts/check-phase4-command-isolation.sh"
  "${ROOT_DIR}/scripts/check-phase4-mode-isolation.sh"
  "${ROOT_DIR}/scripts/check-phase4-nav-isolation.sh"
  "${ROOT_DIR}/scripts/check-phase4-dual-nav-loop.sh"
)

echo "iconom phase-4 acceptance"
echo "mode: ${MODE}"
echo "runtime contract check: ${RUN_RUNTIME_CONTRACT}"
echo
echo "this runs the maintained phase-4 validation flow for the dual-aircraft baseline."
echo

for check in "${CHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  "${check}"
  echo
done

echo "phase-4 acceptance passed"
