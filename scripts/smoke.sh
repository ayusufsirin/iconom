#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"

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

echo "iconom smoke scaffold"
echo "root: ${ROOT_DIR}"

require_cmd docker

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "missing required command: docker compose or docker-compose" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${OVERRIDE_FILE}"

echo "compose command: ${COMPOSE_CMD[*]}"
echo "compose files:"
echo "  - ${COMPOSE_FILE}"
echo "  - ${OVERRIDE_FILE}"
echo
echo "intended smoke sequence:"
echo "  1. bring up the canonical compose stack in headless mode"
echo "  2. confirm px4, gazebo, xrce_agent, and ros2_app services are healthy"
echo "  3. verify the ROS camera topic exists"
echo "  4. verify the PX4 telemetry topic path exists"
echo "  5. exit cleanly and tear the stack down"
echo
echo "status: scaffold only"
echo "smoke test not yet implemented; compose contract is in place but PX4/Gazebo/ROS images and checks are not built yet" >&2
exit 3
