#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${ICONOM_PHASE5_MODE:-headless}"

declare -a CHECKS=()

usage() {
  cat <<'USAGE'
Usage: phase5-acceptance.sh [--headless]

Run the current phase-5 acceptance flow for the server-aware fighter substrate.

Environment:
  ICONOM_PHASE5_MODE=headless
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
    unset ICONOM_USE_GUI || true
    ;;
  *)
    echo "unsupported phase-5 acceptance mode: ${MODE}" >&2
    exit 2
    ;;
esac

CHECKS=(
  "${ROOT_DIR}/scripts/check-phase5-referee-server.sh"
  "${ROOT_DIR}/scripts/check-phase5-competition-client.sh"
  "${ROOT_DIR}/scripts/check-phase5-telemetry-adapter.sh"
  "${ROOT_DIR}/scripts/check-phase5-rival-history.sh"
  "${ROOT_DIR}/scripts/check-phase5-predictor.sh"
)

echo "iconom phase-5 acceptance"
echo "mode: ${MODE}"
echo
echo "this runs the maintained phase-5 validation flow for the server-aware fighter substrate."
echo

for check in "${CHECKS[@]}"; do
  echo "================================================================"
  echo "running $(basename "${check}")"
  echo "================================================================"
  "${check}"
  echo
done

echo "phase-5 acceptance passed"
