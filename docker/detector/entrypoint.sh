#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

colcon build --merge-install --packages-select iconom_vision

set +u
source /workspaces/ros2_ws/install/setup.bash
set -u

exec ros2 run iconom_vision aircraft_detector