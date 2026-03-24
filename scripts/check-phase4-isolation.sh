#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
PX4_LOG_1="${ROOT_DIR}/.tmp-phase4-px4-plane01.log"
PX4_LOG_2="${ROOT_DIR}/.tmp-phase4-px4-plane02.log"
PX4_PID_1=""
PX4_PID_2=""
ROS2_APP_CONTAINER_NAME=""
PX4_CONTAINER_1=""
PX4_CONTAINER_2=""

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
  if [[ -n "${PX4_PID_1}" ]] && kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
    kill "${PX4_PID_1}" >/dev/null 2>&1 || true
    wait "${PX4_PID_1}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${PX4_PID_2}" ]] && kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
    kill "${PX4_PID_2}" >/dev/null 2>&1 || true
    wait "${PX4_PID_2}" >/dev/null 2>&1 || true
  fi
  rm -f "${PX4_LOG_1}" "${PX4_LOG_2}"
  "${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_cmd docker
require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

echo "iconom phase-4 isolation check"
echo
echo "this brings up the first truthful dual-aircraft runtime slice:"
echo "  - plane_01 and plane_02 PX4 runtimes start against one Gazebo world"
echo "  - both ROS telemetry roots appear"
echo "  - both camera bridges publish isolated topics"

echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building required services"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" build gazebo xrce_agent ros2_app ros_gz_bridge px4

echo "step 4: starting gazebo, xrce_agent, ros2_app, and both camera bridges"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d gazebo xrce_agent ros2_app ros_gz_bridge ros_gz_bridge_plane_02

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps --services --status running)"
for service in gazebo xrce_agent ros2_app ros_gz_bridge ros_gz_bridge_plane_02; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before phase-4 isolation check" >&2
    "${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" logs "${service}" || true
    exit 61
  fi
done

ROS2_APP_CONTAINER_NAME="$(docker ps --filter 'label=com.docker.compose.service=ros2_app' --format '{{.Names}}' | head -n 1 || true)"
if [[ -z "${ROS2_APP_CONTAINER_NAME}" ]]; then
  echo "failed to identify the live ros2_app container" >&2
  exit 62
fi

echo "step 5: launching plane_01 PX4 runtime"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" run --rm --no-deps -T   -e PX4_HEADLESS="${PX4_HEADLESS:-1}"   -e PX4_GZ_STANDALONE=1   -e PX4_GZ_HOSTNAME=gazebo   px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${PX4_LOG_1}" 2>&1 &
PX4_PID_1=$!

echo "step 6: launching plane_02 PX4 runtime"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" run --rm --no-deps -T   -e PX4_HEADLESS="${PX4_HEADLESS:-1}"   -e PX4_GZ_STANDALONE=1   -e PX4_GZ_HOSTNAME=gazebo   px4_plane_02 /usr/local/bin/px4-run-vehicle.sh </dev/null >"${PX4_LOG_2}" 2>&1 &
PX4_PID_2=$!

echo "step 7: discovering the live px4 runtime containers"
for ((i=1; i<=90; i++)); do
  if [[ -n "${PX4_PID_1}" ]] && ! kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID_1}" || PX4_EXIT=$?
    echo "plane_01 px4 runtime exited before container discovery" >&2
    echo "plane_01 exit code: ${PX4_EXIT}" >&2
    tail -n 200 "${PX4_LOG_1}" >&2 || true
    exit 63
  fi

  if [[ -n "${PX4_PID_2}" ]] && ! kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID_2}" || PX4_EXIT=$?
    echo "plane_02 px4 runtime exited before container discovery" >&2
    echo "plane_02 exit code: ${PX4_EXIT}" >&2
    tail -n 200 "${PX4_LOG_2}" >&2 || true
    exit 64
  fi

  PX4_CONTAINER_1="$(docker ps --filter 'label=com.docker.compose.service=px4' --format '{{.Names}}' | grep 'run' | head -n 1 || true)"
  PX4_CONTAINER_2="$(docker ps --filter 'label=com.docker.compose.service=px4_plane_02' --format '{{.Names}}' | grep 'run' | head -n 1 || true)"

  if [[ -n "${PX4_CONTAINER_1}" && -n "${PX4_CONTAINER_2}" ]]; then
    break
  fi

  sleep 1
done

if [[ -z "${PX4_CONTAINER_1}" || -z "${PX4_CONTAINER_2}" ]]; then
  echo "failed to identify both live px4 runtime containers" >&2
  tail -n 120 "${PX4_LOG_1}" >&2 || true
  tail -n 120 "${PX4_LOG_2}" >&2 || true
  exit 65
fi

echo "plane_01 runtime container: ${PX4_CONTAINER_1}"
echo "plane_02 runtime container: ${PX4_CONTAINER_2}"

echo "step 8: polling ROS 2 graph for dual telemetry and camera isolation"
PLANE1_STATUS='/plane_01/fmu/out/vehicle_status_v1'
PLANE2_STATUS='/plane_02/fmu/out/vehicle_status_v1'
PLANE1_CAMERA='/plane_01/camera/image_raw'
PLANE2_CAMERA='/plane_02/camera/image_raw'
PLANE1_CAMERA_INFO='/plane_01/camera/camera_info'
PLANE2_CAMERA_INFO='/plane_02/camera/camera_info'

for ((i=1; i<=120; i++)); do
  if [[ -n "${PX4_PID_1}" ]] && ! kill -0 "${PX4_PID_1}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID_1}" || PX4_EXIT=$?
    echo "plane_01 px4 runtime exited before topic isolation completed" >&2
    echo "plane_01 exit code: ${PX4_EXIT}" >&2
    tail -n 120 "${PX4_LOG_1}" >&2 || true
    exit 66
  fi

  if [[ -n "${PX4_PID_2}" ]] && ! kill -0 "${PX4_PID_2}" >/dev/null 2>&1; then
    PX4_EXIT=0
    wait "${PX4_PID_2}" || PX4_EXIT=$?
    echo "plane_02 px4 runtime exited before topic isolation completed" >&2
    echo "plane_02 exit code: ${PX4_EXIT}" >&2
    tail -n 120 "${PX4_LOG_2}" >&2 || true
    exit 67
  fi

  TOPICS="$(docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${PLANE1_STATUS}" <<<"${TOPICS}"     && grep -qx "${PLANE2_STATUS}" <<<"${TOPICS}"     && grep -qx "${PLANE1_CAMERA}" <<<"${TOPICS}"     && grep -qx "${PLANE2_CAMERA}" <<<"${TOPICS}"     && grep -qx "${PLANE1_CAMERA_INFO}" <<<"${TOPICS}"     && grep -qx "${PLANE2_CAMERA_INFO}" <<<"${TOPICS}"; then
    break
  fi

  sleep 1
done

for topic in "${PLANE1_STATUS}" "${PLANE2_STATUS}" "${PLANE1_CAMERA}" "${PLANE2_CAMERA}" "${PLANE1_CAMERA_INFO}" "${PLANE2_CAMERA_INFO}"; do
  if ! docker exec "${ROS2_APP_CONTAINER_NAME}" bash -lc "set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; set -u; ros2 topic list 2>/dev/null | grep -qx '${topic}'"; then
    echo "missing expected isolated topic: ${topic}" >&2
    exit 68
  fi
done

echo "phase-4 runtime isolation is alive"
echo "  plane_01 status topic: ${PLANE1_STATUS}"
echo "  plane_02 status topic: ${PLANE2_STATUS}"
echo "  plane_01 camera topic: ${PLANE1_CAMERA}"
echo "  plane_02 camera topic: ${PLANE2_CAMERA}"
