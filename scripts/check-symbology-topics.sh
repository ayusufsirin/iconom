#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/joseph/Projects/iconom"
ENV_FILE="${ROOT_DIR}/.env.example"

cleanup() {
  docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Phase 2: Symbology Topics Smoke Test ==="

docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/docker-compose.yml" config >/dev/null

echo "step 1: start ros2_app + ros_gz_bridge + gazebo"
docker compose --env-file "${ENV_FILE}" -f "${ROOT_DIR}/docker-compose.yml" up -d gazebo ros2_app ros_gz_bridge
sleep 10

ROS2_APP="$(docker ps --filter 'label=com.docker.compose.service=ros2_app' --format '{{.Names}}' | head -1)"
echo "ros2_app: ${ROS2_APP}"

echo "step 2: wait for camera"
for i in $(seq 1 30); do
  TOPICS=$(docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash; ros2 topic list' 2>/dev/null)
  if echo "${TOPICS}" | grep -q "/plane_01/camera/image_raw"; then
    echo "camera ready at ${i}"; break
  fi
  [[ $i -eq 30 ]] && exit 11
  sleep 1
done

echo "step 3: start symbology node in background"
nohup docker exec -t "${ROS2_APP}" bash -lc '
  source /opt/ros/humble/setup.bash
  source /workspaces/ros2_ws/install/setup.bash
  ros2 run iconom_vision camera_symbology_overlay
' > /tmp/symbology.log 2>&1 &
echo "symbology started, waiting 5s..."
sleep 5

OVERLAY="/plane_01/camera/image_overlay"
echo "step 4: verify overlay topic"
for i in $(seq 1 30); do
  TOPICS=$(docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash; ros2 topic list' 2>/dev/null)
  if echo "${TOPICS}" | grep -q "${OVERLAY}"; then
    echo "overlay found at ${i}"; break
  fi
  [[ $i -eq 30 ]] && exit 12
  sleep 1
done

echo "step 5: verify overlay publishes (20s)"
for i in $(seq 1 20); do
  HZ=$(docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash; timeout 4 ros2 topic hz '"${OVERLAY}"' 2>&1')
  if echo "${HZ}" | grep -q "Hz"; then
    echo "publishing at ${i}"; break
  fi
  [[ $i -eq 20 ]] && { echo "HZ failed: ${HZ}"; exit 13; }
  sleep 1
done

echo "=== PHASE 2 PASSED ==="
