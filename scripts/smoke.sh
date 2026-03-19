#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env.example"

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

echo "iconom smoke scaffold"
echo "root: ${ROOT_DIR}"

require_cmd docker

COMPOSE_CMD=(docker compose)

if ! "${COMPOSE_CMD[@]}" version >/dev/null 2>&1; then
  echo "docker compose (Compose v2) is unavailable or unusable on this host" >&2
  exit 2
fi

require_file "${COMPOSE_FILE}"
require_file "${ENV_FILE}"

COMPOSE_ARGS=(--env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")

cleanup() {
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "compose command: ${COMPOSE_CMD[*]}"
echo "compose files:"
echo "  - ${COMPOSE_FILE}"
echo "env file:"
echo "  - ${ENV_FILE}"
echo
echo "slice under test: xrce_agent"
echo "real services under test: xrce_agent, ros2_app"
echo "full stack status: px4 and gazebo are still scaffold placeholders"
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building xrce_agent and ros2_app"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent ros2_app

echo "step 3: starting xrce_agent only"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent

echo "step 4: checking xrce_agent state"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running | grep -qx "xrce_agent"; then
  echo "xrce_agent did not reach running state" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs xrce_agent || true
  exit 10
fi

echo "step 5: starting ros2_app only"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d ros2_app

echo "step 6: checking ros2_app state"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running | grep -qx "ros2_app"; then
  echo "ros2_app did not reach running state" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs ros2_app || true
  exit 11
fi

echo "step 7: checking xrce_agent and ros2_app together"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent ros2_app

RUNNING_SERVICES="$("${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running)"
if ! grep -qx "xrce_agent" <<<"${RUNNING_SERVICES}"; then
  echo "xrce_agent did not remain running in combined startup" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs xrce_agent || true
  exit 12
fi
if ! grep -qx "ros2_app" <<<"${RUNNING_SERVICES}"; then
  echo "ros2_app did not remain running in combined startup" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs ros2_app || true
  exit 13
fi

echo "xrce_agent and ros2_app slices succeeded"
echo "full smoke is still not implemented because px4 and gazebo remain scaffold services" >&2
exit 3
