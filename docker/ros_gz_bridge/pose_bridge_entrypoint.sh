#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

echo "ros_gz_bridge pose bridge service ready"
echo "  Bridging rc_cessna_0/pose -> /competition/ownship/state"
echo "  Bridging rc_cessna_1/pose -> /fusion/rival/state"

exec ros2 run ros_gz_bridge parameter_bridge \
  "/world/default/model/rc_cessna_0/pose@geometry_msgs/msg/PoseStamped[gz.msgs.Pose" \
  "/world/default/model/rc_cessna_1/pose@geometry_msgs/msg/PoseStamped[gz.msgs.Pose" \
  --ros-args \
  -r "/world/default/model/rc_cessna_0/pose:=/competition/ownship/state" \
  -r "/world/default/model/rc_cessna_1/pose:=/fusion/rival/state"
