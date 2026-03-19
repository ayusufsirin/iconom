#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
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
require_file "${ENV_FILE}"

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "single-vehicle baseline requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 31
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "single-vehicle baseline requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 32
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "single-vehicle baseline requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 33
fi

if [[ -z "${GAZEBO_WORLD_FILE:-}" ]]; then
  echo "single-vehicle baseline requires GAZEBO_WORLD_FILE to be set" >&2
  exit 34
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

cleanup() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "iconom single-vehicle integration baseline"
echo "vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "px4 namespace: ${PX4_UXRCE_DDS_NS}"
echo "px4 model contract: ${PX4_SIM_MODEL}"
echo "gazebo world: ${GAZEBO_WORLD_FILE}"
echo
echo "this check validates the first integrated bring-up contract for one vehicle."
echo "it does not claim that PX4 has spawned into Gazebo or that camera/ROS bridge topics are complete."
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building the integrated single-vehicle stack"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent gazebo ros2_app px4

echo "step 3: starting xrce_agent, gazebo, ros2_app, and px4 together"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent gazebo ros2_app px4

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in xrce_agent gazebo ros2_app px4; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state in the integrated bring-up" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 40
  fi
done

echo "step 4: validating baseline launch contract inside running containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T px4 bash -lc 'test -x /opt/PX4-Autopilot/build/px4_sitl_default/bin/px4 && test "${PX4_UXRCE_DDS_NS}" = "plane_01" && test "${PX4_SIM_MODEL}" = "gz_rc_cessna"'
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T gazebo bash -lc 'test -f "${GAZEBO_WORLD_FILE}" && ros2 pkg prefix ros_gz_bridge >/dev/null'
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'test -d /workspaces/ros2_ws && source /opt/ros/humble/setup.bash && ros2 --help >/dev/null'
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T xrce_agent bash -lc 'test -x /opt/microxrce/bin/MicroXRCEAgent'

echo "integrated baseline contract is wired"
echo "remaining gaps:"
echo "  - px4 is not yet launched into gazebo with an actual spawned vehicle"
echo "  - camera sensors are not wired"
echo "  - ros_gz topic bridging is installed but not validated for runtime topics"
echo "  - the full fixed-wing mission target is not complete" >&2
exit 3
