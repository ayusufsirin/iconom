#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PHASE6_CAMERA_WEB_PORT:-8766}"
HOST="${PHASE6_CAMERA_WEB_HOST:-127.0.0.1}"

cat <<MSG
iconom phase-6 camera web viewer
starting docker camera_web service at http://${HOST}:${PORT}/

Open:
  http://${HOST}:${PORT}/docs/phase6-camera-viewer.html

Expected rosbridge websocket:
  ws://127.0.0.1:${ROSBRIDGE_PORT:-9090}
MSG

cd "${ROOT_DIR}"
exec docker compose \
  --env-file .env.example \
  -f docker-compose.yml \
  -f docker-compose.override.yml \
  up -d camera_web
