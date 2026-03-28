#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PHASE6_CZML_VIEWER_PORT:-8765}"
HOST="${PHASE6_CZML_VIEWER_HOST:-127.0.0.1}"

cat <<MSG
iconom phase-6 CZML viewer
serving repo root at http://${HOST}:${PORT}/

Open:
  http://${HOST}:${PORT}/docs/phase6-czml-viewer.html

Useful replay path inside the viewer:
  /ros2_ws/.tmp-phase6-live-rival-geometry.csv.czml
MSG

cd "${ROOT_DIR}"
exec python3 -m http.server "${PORT}" --bind "${HOST}"
