#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_CMD=(docker compose)
BRINGUP_LOG="${ROOT_DIR}/.tmp-px4-bringup.log"
BRINGUP_PID=""

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
  if [[ -n "${BRINGUP_PID}" ]] && kill -0 "${BRINGUP_PID}" >/dev/null 2>&1; then
    kill "${BRINGUP_PID}" >/dev/null 2>&1 || true
    wait "${BRINGUP_PID}" >/dev/null 2>&1 || true
  fi
  rm -f "${BRINGUP_LOG}"
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
  echo "telemetry check requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 61
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "telemetry check requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 62
fi

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
trap cleanup EXIT

TELEMETRY_TOPIC="${PX4_TELEMETRY_TOPIC:-/plane_01/fmu/out/vehicle_status}"
TELEMETRY_PREFIX="${PX4_TELEMETRY_TOPIC_PREFIX:-/plane_01/fmu/out}"
WAIT_SEC="${PX4_TELEMETRY_WAIT_SEC:-45}"

echo "iconom PX4 telemetry check"
echo "topic target: ${TELEMETRY_TOPIC}"
echo "topic prefix: ${TELEMETRY_PREFIX}"
echo "wait timeout: ${WAIT_SEC}s"
echo
echo "this checks telemetry discovery prerequisites and attempts to observe one PX4 topic in ROS 2."
echo "camera integration is intentionally out of scope here."
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: clearing any stale iconom containers"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true

echo "step 3: building xrce_agent, ros2_app, and px4"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent ros2_app px4

echo "step 4: starting xrce_agent and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
for service in xrce_agent ros2_app; do
  if ! grep -qx "${service}" <<<"${RUNNING_SERVICES}"; then
    echo "${service} did not reach running state before telemetry check" >&2
    "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs "${service}" || true
    exit 63
  fi
done

echo "step 5: bootstrapping the ros2_app workspace for PX4 telemetry types"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc '
  set -euo pipefail
  set +u
  source /opt/ros/humble/setup.bash
  set -u
  mkdir -p /workspaces/ros2_ws/src
  if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
    vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
  fi
  colcon build --merge-install --base-paths /workspaces/ros2_ws/src --packages-up-to px4_msgs
  set +u
  source /workspaces/ros2_ws/install/setup.bash
  set -u
  ros2 interface show px4_msgs/msg/VehicleStatus >/dev/null
'

echo "step 6: launching the current PX4 runtime path in the background"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" run --rm --no-deps -T \
  -e PX4_HEADLESS="${PX4_HEADLESS:-1}" \
  -e PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  -e PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  -e PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  -e PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}" \
  px4 /usr/local/bin/px4-run-single-vehicle.sh </dev/null >"${BRINGUP_LOG}" 2>&1 &
BRINGUP_PID=$!

echo "step 7: polling ROS 2 graph for PX4 telemetry"
for ((i=1; i<=WAIT_SEC; i++)); do
  if [[ -n "${BRINGUP_PID}" ]] && ! kill -0 "${BRINGUP_PID}" >/dev/null 2>&1; then
    BRINGUP_EXIT=0
    wait "${BRINGUP_PID}" || BRINGUP_EXIT=$?
    echo "px4 runtime exited before telemetry topic discovery" >&2
    echo "px4 runtime exit code: ${BRINGUP_EXIT}" >&2
    cat "${BRINGUP_LOG}" >&2 || true
    exit 64
  fi

  TOPICS="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" exec -T ros2_app bash -lc 'set +u; source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; set -u; ros2 topic list 2>/dev/null || true')"

  if grep -qx "${TELEMETRY_TOPIC}" <<<"${TOPICS}"; then
    echo "telemetry topic visible: ${TELEMETRY_TOPIC}"
    exit 0
  fi

  DISCOVERED_TOPIC="$(grep "^${TELEMETRY_PREFIX}/" <<<"${TOPICS}" | head -n 1 || true)"
  if [[ -n "${DISCOVERED_TOPIC}" ]]; then
    echo "telemetry topic visible under prefix: ${DISCOVERED_TOPIC}"
    exit 0
  fi

  sleep 1
done

echo "no PX4 telemetry topic became visible under ${TELEMETRY_PREFIX} within ${WAIT_SEC}s" >&2
echo "--- px4 runtime log ---" >&2
cat "${BRINGUP_LOG}" >&2 || true
exit 65
