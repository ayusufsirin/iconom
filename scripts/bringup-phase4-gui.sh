#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)

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

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${OVERRIDE_FILE}"
require_file "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ "${PLANE_01_NAMESPACE:-}" != "plane_01" ]]; then
  echo "phase-4 GUI bring-up requires PLANE_01_NAMESPACE=plane_01" >&2
  exit 61
fi

if [[ "${PLANE_02_NAMESPACE:-}" != "plane_02" ]]; then
  echo "phase-4 GUI bring-up requires PLANE_02_NAMESPACE=plane_02" >&2
  exit 62
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "phase-4 GUI bring-up currently requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 63
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; the phase-4 GUI path requires a local X11 display" >&2
  exit 64
fi

COMPOSE_ARGS=(--profile phase4 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -f "${OVERRIDE_FILE}")

cleanup() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "iconom phase-4 dual-aircraft GUI bring-up"
echo "plane_01 namespace: ${PLANE_01_NAMESPACE}"
echo "plane_02 namespace: ${PLANE_02_NAMESPACE}"
echo "px4 model: ${PX4_SIM_MODEL}"
echo "px4 world: ${PX4_GZ_WORLD:-default}"
echo "plane_01 pose: ${PLANE_01_PX4_GZ_MODEL_POSE:-0,0,0.246}"
echo "plane_02 pose: ${PLANE_02_PX4_GZ_MODEL_POSE:-0,15,0.246}"
echo "display: ${DISPLAY}"
echo
echo "this is the maintained dual-aircraft GUI path."
echo "it uses the local override stack for X11, starts one Gazebo world,"
echo "keeps both camera bridges alive, and launches both PX4 runtimes"
echo "against the same external Gazebo process with PX4_HEADLESS=0."
echo

echo "step 1: validating merged compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building required services"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build gazebo xrce_agent ros2_app ros_gz_bridge px4 px4_plane_02

echo "step 3: starting gazebo, xrce_agent, ros2_app, and both camera bridges"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d gazebo xrce_agent ros2_app ros_gz_bridge ros_gz_bridge_plane_02

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in gazebo xrce_agent ros2_app ros_gz_bridge ros_gz_bridge_plane_02; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before phase-4 GUI bring-up" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 65
  fi
done

echo "step 4: launching plane_01 against the external Gazebo GUI runtime"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps \
  -e PX4_HEADLESS=0 \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  -e PX4_GZ_MODEL_POSE="${PLANE_01_PX4_GZ_MODEL_POSE:-0,0,0.246}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh &
PX4_PID_1=$!

echo "step 5: launching plane_02 against the external Gazebo GUI runtime"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps \
  -e PX4_HEADLESS=0 \
  -e PX4_GZ_STANDALONE=1 \
  -e PX4_GZ_HOSTNAME=gazebo \
  -e PX4_GZ_MODEL_POSE="${PLANE_02_PX4_GZ_MODEL_POSE:-0,15,0.246}" \
  px4_plane_02 /usr/local/bin/px4-run-vehicle.sh &
PX4_PID_2=$!

wait "${PX4_PID_1}" "${PX4_PID_2}"
