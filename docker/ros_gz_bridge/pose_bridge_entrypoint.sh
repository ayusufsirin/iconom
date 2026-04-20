#!/usr/bin/env bash
set -euo pipefail

echo "checking gz CLI..."
if ! which gz >/dev/null 2>&1; then
  echo "error: gz CLI not found" >&2
  exit 1
fi
echo "checking gz CLI... OK"

echo "checking Python 3..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 not found" >&2
  exit 1
fi
echo "checking Python 3... OK"

echo "checking ROS setup..."
if ! bash -lc 'source /opt/ros/humble/setup.bash >/dev/null 2>&1 && command -v ros2 >/dev/null 2>&1'; then
  echo "error: unable to source /opt/ros/humble/setup.bash or find ros2" >&2
  exit 1
fi
set +u
source /opt/ros/humble/setup.bash
set -u
echo "checking ROS setup... OK"

echo "pose bridge service ready"

exec python3 /usr/local/bin/pose_bridge.py --ros-args \
  -p ownship_topic:=${OWNSHIP_TOPIC:-/competition/ownship/state} \
  -p rival_topic:=${RIVAL_TOPIC:-/fusion/rival/state}
