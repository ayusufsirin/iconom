#!/usr/bin/env bash
set -euo pipefail

source /opt/ros/humble/setup.bash

if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
  source /workspaces/ros2_ws/install/setup.bash
fi

exec "$@"
