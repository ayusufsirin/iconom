#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG="${ROOT_DIR}/.tmp-px4-camera.log"
BRIDGE_LOG="${ROOT_DIR}/.tmp-ros-gz-bridge.log"
PX4_PID=""
PX4_CONTAINER_NAME=""
ROS2_APP_CONTAINER_NAME=""
BRIDGE_CONTAINER_NAME="iconom-camera-bridge-test"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 2
  fi
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "missing required file: $1" >&2
    exit 2
  fi
}

cleanup() {
  if [[ -n "${PX4_PID}" ]] && kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    kill "${PX4_PID}" >/dev/null 2>&1 || true
    wait "${PX4_PID}" >/dev/null 2>&1 || true
  fi
  docker rm -f "${BRIDGE_CONTAINER_NAME}" >/dev/null 2>&1 || true
  rm -f "${PX4_LOG}" "${BRIDGE_LOG}"
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

require_cmd docker

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "camera check requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 71
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "camera check requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 72
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "camera check requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 73
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
trap cleanup EXIT

CAMERA_TOPIC="${CAMERA_TOPIC:-/plane_01/camera/image_raw}"
CAMERA_INFO_TOPIC="${CAMERA_INFO_TOPIC:-/plane_01/camera/camera_info}"
DISCOVERY_WAIT_SEC="${CAMERA_DISCOVERY_WAIT_SEC:-60}"

echo "iconom camera bridge check"
echo "camera topic target: ${CAMERA_TOPIC}"
echo "camera info target: ${CAMERA_INFO_TOPIC}"
echo "wait timeout: ${DISCOVERY_WAIT_SEC}s"
echo
echo "this checks the first single-vehicle camera slice:"
echo "  - PX4 runtime starts with the patched rc_cessna camera model"
echo "  - Gazebo exposes live camera transport topics"
echo "  - ros_gz_bridge forwards them into ROS 2"
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building gazebo, xrce_agent, ros2_app, ros_gz_bridge, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo xrce_agent ros2_app ros_gz_bridge px4

echo "step 4: starting gazebo, xrce_agent, and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in gazebo xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before camera check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 74
  fi
done

ROS2_APP_CONTAINER_NAME="$(docker ps --filter 'label=com.docker.compose.service=ros2_app' --format '{{.Names}}' | head -n 1 || true)"
if [[ -z "${ROS2_APP_CONTAINER_NAME}" ]]; then
  echo "failed to identify the live ros2_app container" >&2
  exit 74
fi

echo "step 5: launching the current PX4 runtime path in the background"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  -e PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG}" 2>&1 &
PX4_PID=$!

echo "step 6: discovering the live PX4 runtime container"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before container discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    tail -n 200 "${PX4_LOG}" >&2 || true
    exit 75
  fi

  PX4_CONTAINER_NAME="$(docker ps --format '{{.Names}}' | grep '^iconom-px4-run-' | head -n 1 || true)"
  if [[ -n "${PX4_CONTAINER_NAME}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${PX4_CONTAINER_NAME}" ]]; then
  echo "failed to identify the live px4 runtime container" >&2
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 75
fi

echo "live px4 runtime container: ${PX4_CONTAINER_NAME}"

echo "step 7: discovering Gazebo camera topics"
GZ_IMAGE_TOPIC=""
GZ_CAMERA_INFO_TOPIC=""
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  if [[ -n "${PX4_PID}" ]] && ! kill -0 "${PX4_PID}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID}" || PX4_EXIT=$?
    echo "px4 runtime exited before camera topic discovery" >&2
    echo "px4 runtime exit code: ${PX4_EXIT}" >&2
    tail -n 200 "${PX4_LOG}" >&2 || true
    exit 75
  fi

  GZ_TOPICS="$(docker exec "${PX4_CONTAINER_NAME}" bash -lc 'gz topic -l 2>/dev/null || true')"
  GZ_IMAGE_TOPIC="$(grep '/link/camera_link/sensor/imager/image$' <<<"${GZ_TOPICS}" | head -n 1 || true)"
  GZ_CAMERA_INFO_TOPIC="$(grep '/link/camera_link/sensor/imager/camera_info$' <<<"${GZ_TOPICS}" | head -n 1 || true)"

  if [[ -n "${GZ_IMAGE_TOPIC}" && -n "${GZ_CAMERA_INFO_TOPIC}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${GZ_IMAGE_TOPIC}" || -z "${GZ_CAMERA_INFO_TOPIC}" ]]; then
  echo "failed to discover Gazebo camera topics within ${DISCOVERY_WAIT_SEC}s" >&2
  echo "--- px4 runtime log ---" >&2
  tail -n 200 "${PX4_LOG}" >&2 || true
  exit 76
fi

echo "discovered Gazebo image topic: ${GZ_IMAGE_TOPIC}"
echo "discovered Gazebo camera info topic: ${GZ_CAMERA_INFO_TOPIC}"

echo "step 8: starting ros_gz_bridge in the background"
docker rm -f "${BRIDGE_CONTAINER_NAME}" >/dev/null 2>&1 || true
docker run -d --name "${BRIDGE_CONTAINER_NAME}" \
  --network "container:${PX4_CONTAINER_NAME}" \
  -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" \
  -e USE_SIM_TIME="${USE_SIM_TIME:-true}" \
  -e GZ_IMAGE_TOPIC="${GZ_IMAGE_TOPIC}" \
  -e GZ_CAMERA_INFO_TOPIC="${GZ_CAMERA_INFO_TOPIC}" \
  -e CAMERA_TOPIC="${CAMERA_TOPIC}" \
  -e CAMERA_INFO_TOPIC="${CAMERA_INFO_TOPIC}" \
  iconom-ros_gz_bridge bash -lc '
    set -euo pipefail
    set +u
    source /opt/ros/humble/setup.bash
    set -u
    exec ros2 run ros_gz_bridge parameter_bridge \
      "${GZ_IMAGE_TOPIC}@sensor_msgs/msg/Image[gz.msgs.Image" \
      "${GZ_CAMERA_INFO_TOPIC}@sensor_msgs/msg/CameraInfo[gz.msgs.CameraInfo" \
      --ros-args \
      -r "${GZ_IMAGE_TOPIC}:=${CAMERA_TOPIC}" \
      -r "${GZ_CAMERA_INFO_TOPIC}:=${CAMERA_INFO_TOPIC}"
  ' >/dev/null

echo "step 9: polling ROS 2 graph for camera topics"
for ((i=1; i<=DISCOVERY_WAIT_SEC; i++)); do
  BRIDGE_STATUS="$(docker inspect --format '{{.State.Status}}' "${BRIDGE_CONTAINER_NAME}" 2>/dev/null || true)"
  if [[ -n "${BRIDGE_STATUS}" && "${BRIDGE_STATUS}" != "running" ]]; then
    BRIDGE_EXIT="$(docker inspect --format '{{.State.ExitCode}}' "${BRIDGE_CONTAINER_NAME}" 2>/dev/null || echo 1)"
    docker logs --tail=200 "${BRIDGE_CONTAINER_NAME}" >"${BRIDGE_LOG}" 2>&1 || true
    echo "ros_gz_bridge exited before camera topics became visible" >&2
    echo "ros_gz_bridge exit code: ${BRIDGE_EXIT}" >&2
    cat "${BRIDGE_LOG}" >&2 || true
    exit 77
  fi

  TOPICS="$(docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${CAMERA_TOPIC}" <<<"${TOPICS}" && grep -qx "${CAMERA_INFO_TOPIC}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

if ! docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc "set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; set -u; ros2 topic list 2>/dev/null | grep -qx '${CAMERA_TOPIC}'"; then
  echo "camera image topic did not appear in ROS 2: ${CAMERA_TOPIC}" >&2
  echo "--- ros_gz_bridge log ---" >&2
  docker logs --tail=200 "${BRIDGE_CONTAINER_NAME}" >"${BRIDGE_LOG}" 2>&1 || true
  cat "${BRIDGE_LOG}" >&2 || true
  exit 78
fi

if ! docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc "set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; set -u; timeout 15 ros2 topic echo --once '${CAMERA_INFO_TOPIC}' >/dev/null"; then
  echo "camera info messages did not flow through ROS 2: ${CAMERA_INFO_TOPIC}" >&2
  echo "--- ros_gz_bridge log ---" >&2
  docker logs --tail=200 "${BRIDGE_CONTAINER_NAME}" >"${BRIDGE_LOG}" 2>&1 || true
  cat "${BRIDGE_LOG}" >&2 || true
  exit 79
fi

echo "camera bridge is alive"
echo "  ros image topic: ${CAMERA_TOPIC}"
echo "  ros camera info topic: ${CAMERA_INFO_TOPIC}"
