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

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "single-vehicle GUI bring-up requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 61
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "single-vehicle GUI bring-up requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 62
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "single-vehicle GUI bring-up requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 63
fi

if [[ -z "${DISPLAY:-}" ]]; then
  echo "DISPLAY is not set; the integrated PX4 GUI path requires a local X11 display" >&2
  exit 64
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" -f "${OVERRIDE_FILE}")

cleanup() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "iconom one-vehicle PX4-in-Gazebo GUI bring-up"
echo "vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "px4 namespace: ${PX4_UXRCE_DDS_NS}"
echo "px4 model: ${PX4_SIM_MODEL}"
echo "px4 world: ${PX4_GZ_WORLD:-default}"
echo "display: ${DISPLAY}"
echo
echo "this is the integrated aircraft GUI path."
echo "it uses the local override stack for X11 and forces PX4_HEADLESS=0."
echo "the current runtime still launches Gazebo from inside the px4 container."
echo
echo "step 1: validating merged compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building required services"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent ros2_app px4

echo "step 3: starting xrce_agent and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before GUI bring-up" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 65
  fi
done

echo "step 4: launching the actual PX4-in-Gazebo GUI runtime"
echo "command: docker compose run --rm --no-deps px4 /usr/local/bin/px4-run-single-vehicle.sh"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps \
  -e PX4_HEADLESS=0 \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh
