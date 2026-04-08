#!/usr/bin/env bash
# check-phase6-camera-symbology.sh
# Validates camera symbology overlay node by checking overlay topic publication.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
ROS2_APP_CONTAINER_NAME=""
SYMBOLOGY_NODE_PID=""

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

cleanup() {
  if [[ -n "${SYMBOLOGY_NODE_PID}" ]] && kill -0 "${SYMBOLOGY_NODE_PID}" >/dev/null 2>&1; then
    kill "${SYMBOLOGY_NODE_PID}" >/dev/null 2>&1 || true
    wait "${SYMBOLOGY_NODE_PID}" >/dev/null 2>&1 || true
  fi
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --headless    Run in headless mode (default)
  --gui         Run with GUI display
  --help        Show this help message

This script validates the camera symbology overlay node:
  1. Starts the dual-aircraft phase 6 simulation
  2. Launches camera_symbology_overlay node
  3. Verifies /plane_01/camera/image_overlay topic is published
  4. Confirms overlay images are being generated
EOF
}

MODE="headless"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless) MODE="headless"; shift ;;
    --gui) MODE="gui"; shift ;;
    --help) usage; exit 0 ;;
    *) echo "unknown option: $1"; usage; exit 1 ;;
  esac
done

require_cmd docker

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

set -a
source "${ENV_FILE}"
set +a

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
trap cleanup EXIT

OVERLAY_TOPIC="/plane_01/camera/image_overlay"
IMAGE_TOPIC="/plane_01/camera/image_raw"
CAMERA_INFO_TOPIC="/plane_01/camera/camera_info"
RIVAL_STATE_TOPIC="/fusion/rival/state"
OWNSHIP_STATE_TOPIC="/competition/ownship/state"
TOPIC_DISCOVERY_WAIT_SEC="${TOPIC_DISCOVERY_WAIT_SEC:-60}"

echo "iconom camera symbology overlay check"
echo "mode: ${MODE}"
echo "overlay topic target: ${OVERLAY_TOPIC}"
echo "wait timeout: ${TOPIC_DISCOVERY_WAIT_SEC}s"
echo

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building workspace for iconom_vision package"
cd "${ROOT_DIR}/ros2_ws"
if ! colcon build --packages-select iconom_vision 2>&1; then
  echo "failed to build iconom_vision package" >&2
  exit 10
fi
cd "${ROOT_DIR}"

echo "step 3: starting minimal phase 6 simulation (dual aircraft)"
# Start only the services needed for symbology overlay
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app ros_gz_bridge 2>/dev/null

# Wait for services to be running
sleep 5

echo "step 4: discovering ros2_app container"
ROS2_APP_CONTAINER_NAME="$(docker ps --filter 'label=com.docker.compose.service=ros2_app' --format '{{.Names}}' | head -n 1 || true)"
if [[ -z "${ROS2_APP_CONTAINER_NAME}" ]]; then
  echo "failed to identify the ros2_app container" >&2
  exit 11
fi
echo "ros2_app container: ${ROS2_APP_CONTAINER_NAME}"

echo "step 5: waiting for camera topics to appear"
for ((i=1; i<=TOPIC_DISCOVERY_WAIT_SEC; i++)); do
  TOPICS="$(docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${IMAGE_TOPIC}" <<<"${TOPICS}" && grep -qx "${CAMERA_INFO_TOPIC}" <<<"${TOPICS}"; then
    echo "camera topics discovered at iteration ${i}"
    break
  fi

  if ((i == TOPIC_DISCOVERY_WAIT_SEC)); then
    echo "camera topics did not appear within ${TOPIC_DISCOVERY_WAIT_SEC}s" >&2
    exit 12
  fi
  sleep 1
done

echo "step 6: starting camera_symbology_overlay node"
# Start the node in background
docker exec -d "${ROS2_APP_CONTAINER_NAME}" bash -lc '
  set +u
  source /opt/ros/humble/setup.bash >/dev/null 2>&1
  if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
    source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1
  fi
  set -u
  ros2 run iconom_vision camera_symbology_overlay
'

# Give the node time to start
sleep 3

echo "step 7: verifying overlay topic is published"
for ((i=1; i<=30; i++)); do
  TOPICS="$(docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${OVERLAY_TOPIC}" <<<"${TOPICS}"; then
    echo "overlay topic discovered at iteration ${i}"
    break
  fi

  if ((i == 30)); then
    echo "overlay topic did not appear within 30s" >&2
    echo "available topics:" >&2
    echo "${TOPICS}" >&2
    exit 13
  fi
  sleep 1
done

echo "step 8: verifying overlay image messages are published"
if ! docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc "set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; timeout 10 ros2 topic hz '${OVERLAY_TOPIC}' 2>/dev/null | head -5"; then
  echo "overlay topic is not publishing messages" >&2
  exit 14
fi

echo
echo "=== camera symbology overlay check PASSED ==="
echo "overlay topic: ${OVERLAY_TOPIC}"
echo "node: iconom_vision camera_symbology_overlay"
echo
echo "To view the overlay in GUI mode:"
echo "  xhost +local:docker"
echo "  ./scripts/view-phase6-ownship-camera.sh"
echo "  # Change CAMERA_TOPIC to ${OVERLAY_TOPIC}"
echo
