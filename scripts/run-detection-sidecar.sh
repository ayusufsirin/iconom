#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
COMPOSE_ARGS=(--profile symbology --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
OVERLAY_TOPIC="/plane_01/camera/image_overlay"
WAIT_TIMEOUT_SEC=60

usage() {
  cat <<'USAGE'
Usage: run-detection-sidecar.sh [OPTIONS]

Start or stop the detector container as a sidecar for chase testing.

Options:
  --stop              Stop the detector container
  --wait-for-overlay Block until /plane_01/camera/image_overlay topic is available
  --dry-run           Show what would be done without doing it
  -h, --help          Show this help message

Examples:
  # Start detector sidecar
  ./run-detection-sidecar.sh

  # Start and wait for overlay topic
  ./run-detection-sidecar.sh --wait-for-overlay

  # Stop detector sidecar
  ./run-detection-sidecar.sh --stop

  # Preview actions without executing
  ./run-detection-sidecar.sh --dry-run
USAGE
}

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

is_detector_running() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running 2>/dev/null | grep -qx "detector"
}

wait_for_overlay_topic() {
  echo "waiting for overlay topic ${OVERLAY_TOPIC} to become available..."
  local topics
  for ((i = 1; i <= WAIT_TIMEOUT_SEC; i++)); do
    topics="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set -euo pipefail; set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; set -u; ros2 topic list 2>/dev/null || true' 2>/dev/null)"
    if grep -qx "${OVERLAY_TOPIC}" <<<"${topics}"; then
      echo "overlay topic ${OVERLAY_TOPIC} is available"
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for overlay topic ${OVERLAY_TOPIC} after ${WAIT_TIMEOUT_SEC} seconds" >&2
  return 1
}

start_detector() {
  if is_detector_running; then
    echo "detector container is already running"
    return 0
  fi

  echo "starting detector container..."
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d detector
  echo "detector container started"
}

stop_detector() {
  if ! is_detector_running; then
    echo "detector container is not running"
    return 0
  fi

  echo "stopping detector container..."
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" stop detector
  echo "detector container stopped"
}

DRY_RUN=0
STOP=0
WAIT_FOR_OVERLAY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --stop)
    STOP=1
    shift
    ;;
  --wait-for-overlay)
    WAIT_FOR_OVERLAY=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
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

require_cmd docker
require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

if [[ "${STOP}" == "1" ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[DRY RUN] would stop detector container"
  else
    stop_detector
  fi
elif [[ "${WAIT_FOR_OVERLAY}" == "1" ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[DRY RUN] would start detector and wait for overlay topic"
  else
    start_detector
    wait_for_overlay_topic
  fi
else
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[DRY RUN] would start detector container"
  else
    start_detector
  fi
fi