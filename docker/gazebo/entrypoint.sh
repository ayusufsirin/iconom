#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

WORLD_FILE="${GAZEBO_WORLD_FILE:-/opt/iconom/sim/worlds/empty.sdf}"

if [[ ! -f "${WORLD_FILE}" ]]; then
  echo "gazebo world file missing: ${WORLD_FILE}" >&2
  exit 30
fi

command -v gz >/dev/null
ros2 pkg prefix ros_gz_bridge >/dev/null

echo "gazebo slice ready"
echo "  GAZEBO_WORLD_FILE=${WORLD_FILE}"
echo "  GZ_SIM_RESOURCE_PATH=${GZ_SIM_RESOURCE_PATH:-}"
echo "  USE_SIM_TIME=${USE_SIM_TIME:-}"
echo "headless Gazebo Harmonic is implemented; vehicle integration is not wired yet"

exec "$@"
