#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ARGS=(
  --env-file "$ROOT_DIR/.env.example"
  -f "$ROOT_DIR/docker-compose.yml"
  -f "$ROOT_DIR/docker-compose.override.yml"
)
CAMERA_TOPIC="${CAMERA_TOPIC:-/plane_01/camera/image_raw}"
SERVICE_NAME="${SERVICE_NAME:-ros2_app}"

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; run this from the same X11 session as the Gazebo GUI." >&2
  exit 1
fi

if ! docker compose "${COMPOSE_ARGS[@]}" ps --status running "$SERVICE_NAME" >/dev/null 2>&1; then
  echo "$SERVICE_NAME is not running. Start the GUI stack first." >&2
  exit 1
fi

echo "opening docker-side camera viewer for $CAMERA_TOPIC"

docker compose "${COMPOSE_ARGS[@]}" exec   -e DISPLAY="$DISPLAY"   -e QT_X11_NO_MITSHM="1"   -e XDG_RUNTIME_DIR="/tmp/runtime-root"   "$SERVICE_NAME" bash -lc "source /opt/ros/humble/setup.bash && ros2 run rqt_image_view rqt_image_view --ros-args -r image:=${CAMERA_TOPIC}"
