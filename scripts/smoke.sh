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
echo "full stack status: px4, gazebo, and ros2_app are still scaffold placeholders"
echo
echo "step 1: validating compose config"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" config >/dev/null

echo "step 2: building xrce_agent only"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" build xrce_agent

echo "step 3: starting xrce_agent only"
"${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" up -d xrce_agent

echo "step 4: checking xrce_agent state"
if ! "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" ps --services --status running | grep -qx "xrce_agent"; then
  echo "xrce_agent did not reach running state" >&2
  "${COMPOSE_CMD[@]}" "${COMPOSE_ARGS[@]}" logs xrce_agent || true
  exit 10
fi

echo "xrce_agent slice succeeded"
echo "full smoke is still not implemented because px4, gazebo, and ros2_app remain scaffold services" >&2
exit 3
