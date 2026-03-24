#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
CONFIG_OUT="$(mktemp)"

cleanup() {
  rm -f "${CONFIG_OUT}"
}
trap cleanup EXIT

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

require_cmd docker
require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

echo "iconom phase-4 runtime contract check"
echo
echo "this checks the first phase-4 implementation slice:"
echo "  - plane_02 exists as an explicit runtime contract"
echo "  - plane_02 has its own PX4 instance, namespace, XRCE key, and camera bridge"
echo "  - the px4 image carries the generic runtime entrypoint for future dual-aircraft bring-up"

echo "step 1: rendering compose config with the phase4 profile"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config > "${CONFIG_OUT}"

echo "step 2: verifying plane_02 runtime contract in rendered config"
grep -q '^  px4_plane_02:$' "${CONFIG_OUT}"
grep -q '^  ros_gz_bridge_plane_02:$' "${CONFIG_OUT}"
grep -q 'ICONOM_VEHICLE_NAMESPACE: plane_02' "${CONFIG_OUT}"
grep -q 'PX4_UXRCE_DDS_NS: plane_02' "${CONFIG_OUT}"
grep -Eq 'PX4_INSTANCE: "?1"?$' "${CONFIG_OUT}"
grep -Eq 'UXRCE_DDS_KEY: "?2"?$' "${CONFIG_OUT}"
grep -Eq 'ICONOM_EXPECTED_UXRCE_DDS_KEY: "?2"?$' "${CONFIG_OUT}"
grep -q 'ICONOM_GZ_MODEL_NAME: rc_cessna_1' "${CONFIG_OUT}"
grep -q 'ICONOM_EXPECTED_MAV_SYS_ID: "2"' "${CONFIG_OUT}" || grep -q 'ICONOM_EXPECTED_MAV_SYS_ID: 2' "${CONFIG_OUT}"
grep -q 'ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT: "14541"' "${CONFIG_OUT}" || grep -q 'ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT: 14541' "${CONFIG_OUT}"
grep -q 'CAMERA_TOPIC: /plane_02/camera/image_raw' "${CONFIG_OUT}"
grep -q 'GZ_IMAGE_TOPIC: /world/default/model/rc_cessna_1/link/camera_link/sensor/imager/image' "${CONFIG_OUT}"

echo "step 3: building the px4 image with the phase-4 runtime contract files"
"${COMPOSE_CMD[@]}" --profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" build px4

echo "step 4: verifying the generic px4 runtime entrypoint in the built service image"
PROJECT_NAME="$(sed -n 's/^name: //p' "${CONFIG_OUT}" | head -n 1)"
if [[ -z "${PROJECT_NAME}" ]]; then
  echo "failed to resolve the compose project name from rendered config" >&2
  exit 69
fi
PX4_IMAGE_NAME="${PROJECT_NAME}-px4"
docker image inspect "${PX4_IMAGE_NAME}" >/dev/null 2>&1 || {
  echo "failed to resolve the built px4 service image ${PX4_IMAGE_NAME}" >&2
  exit 70
}
docker run --rm --entrypoint /bin/bash "${PX4_IMAGE_NAME}" -lc 'test -x /usr/local/bin/px4-run-vehicle.sh && test -x /usr/local/bin/px4-run-single-vehicle.sh'

echo "phase-4 runtime contract is wired"
echo "  plane_02 namespace: plane_02"
echo "  plane_02 px4 instance: 1"
echo "  plane_02 expected mav sys id: 2"
echo "  plane_02 expected mavlink offboard port: 14541"
echo "  plane_02 expected xrce dds key: 2"
echo "  plane_02 expected gazebo model name: rc_cessna_1"
echo "  plane_02 camera topic: /plane_02/camera/image_raw"
