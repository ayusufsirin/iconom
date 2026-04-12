#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

: "${GZ_IMAGE_TOPIC:=/world/default/model/rc_cessna_0/link/camera_link/sensor/imager/image}"
: "${GZ_CAMERA_INFO_TOPIC:=/world/default/model/rc_cessna_0/link/camera_link/sensor/imager/camera_info}"
: "${CAMERA_TOPIC:=/plane_01/camera/image_raw}"
: "${CAMERA_INFO_TOPIC:=/plane_01/camera/camera_info}"

echo "ros_gz_bridge service ready"
echo "  GZ_IMAGE_TOPIC=${GZ_IMAGE_TOPIC}"
echo "  GZ_CAMERA_INFO_TOPIC=${GZ_CAMERA_INFO_TOPIC}"
echo "  CAMERA_TOPIC=${CAMERA_TOPIC}"
echo "  CAMERA_INFO_TOPIC=${CAMERA_INFO_TOPIC}"

exec ros2 run ros_gz_bridge parameter_bridge \
  "/clock@rosgraph_msgs/msg/Clock[gz.msgs.Clock" \
  "${GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image[gz.msgs.Image" \
  "${GZ_CAMERA_INFO_TOPIC}@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo" \
  "/world/default/pose/info@geometry_msgs/msg/PoseArray[gz.msgs.Pose_V" \
  --ros-args \
  -r "${GZ_IMAGE_TOPIC}:=${CAMERA_TOPIC}" \
  -r "${GZ_CAMERA_INFO_TOPIC}:=${CAMERA_INFO_TOPIC}" \
  -r "/world/default/pose/info:=/world/pose/info"
