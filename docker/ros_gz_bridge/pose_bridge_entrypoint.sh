#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

echo "ros_gz_bridge pose bridge service ready"
echo "  Bridging /world/default/pose/info via Python bridge"

exec python3 /usr/local/bin/pose_bridge.py
