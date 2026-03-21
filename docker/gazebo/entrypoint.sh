#!/usr/bin/env bash
set -euo pipefail

WORLD_FILE="${GAZEBO_WORLD_FILE:-/opt/iconom/sim/worlds/empty.sdf}"

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "gazebo world file missing: ${WORLD_FILE}" >&2
  exit 30
fi

command -v gz >/dev/null

echo "gazebo slice ready"
echo "  GAZEBO_WORLD_FILE=${WORLD_FILE}"
echo "  GZ_SIM_RESOURCE_PATH=${GZ_SIM_RESOURCE_PATH:-}"
echo "  USE_SIM_TIME=${USE_SIM_TIME:-}"
echo "standalone Gazebo Harmonic runtime is ready for PX4 attachment"

exec "$@"
