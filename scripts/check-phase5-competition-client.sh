#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_PORT="${REFEREE_SERVER_PORT:-45678}"
BASE_URL="http://localhost:${REF_PORT}"

cleanup() {
    cd "${ROOT_DIR}"
    docker compose --profile phase5 --env-file .env.example down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "iconom phase-5 competition client check"
echo "target: ${BASE_URL}"
echo

wait_for_referee() {
    local max_attempts=20
    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if curl -s "${BASE_URL}/health" >/dev/null 2>&1; then
            echo "referee server is ready"
            return 0
        fi
        echo "waiting for referee server... (${attempt}/${max_attempts})"
        sleep 1
        ((attempt++))
    done
    echo "ERROR: referee server failed to start" >&2
    return 1
}

echo "================================================================"
echo "starting compose-backed referee server"
echo "================================================================"
cd "${ROOT_DIR}"
docker compose --profile phase5 --env-file .env.example up -d referee_server
wait_for_referee

echo "================================================================"
echo "preparing ros2_app image"
echo "================================================================"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running real competition_client HTTP path"
echo "================================================================"
docker compose --profile phase5 --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail

    set +u
    source /opt/ros/humble/setup.bash
    set -u

    export PYTHONPATH=/workspaces/ros2_ws/src/iconom_competition${PYTHONPATH:+:$PYTHONPATH}
    export REF_HOST=referee_server
    export REF_PORT=45678
    unset COMPETITION_FIXTURE_MODE || true

    python3 -u /workspaces/ros2_ws/src/iconom_competition/iconom_competition/competition_client.py > /tmp/iconom-phase5-competition-client.log 2>&1 &
    CLIENT_PID=$!

    cleanup_client() {
        kill ${CLIENT_PID} 2>/dev/null || true
        wait ${CLIENT_PID} 2>/dev/null || true
    }
    trap cleanup_client EXIT

    sleep 3

    ros2 topic pub --once /competition/ownship/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_01},
      pose: {
        position: {x: 10.0, y: 20.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase5-ownship-pub.log 2>&1

    timeout 20 ros2 topic echo --once /competition/rival/state > /tmp/iconom-phase5-rival-state.log

    grep -q "authenticated, token:" /tmp/iconom-phase5-competition-client.log
    echo "PASS: competition_client authenticated with referee"

    grep -q "server time:" /tmp/iconom-phase5-competition-client.log
    echo "PASS: competition_client fetched server time"

    grep -q "telemetry sent, rival:" /tmp/iconom-phase5-competition-client.log
    echo "PASS: competition_client sent telemetry through the real HTTP path"

    grep -q "frame_id: plane_02" /tmp/iconom-phase5-rival-state.log
    echo "PASS: competition_client published rival state from referee-backed telemetry"
'

echo
echo "phase-5 competition client check passed"
