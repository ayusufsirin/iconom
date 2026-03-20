#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
  set +u
  source /workspaces/ros2_ws/install/setup.bash
  set -u
fi

exec "$@"
