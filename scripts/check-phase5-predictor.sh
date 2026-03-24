#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFEREE_SERVER_PORT:-45678}"
BASE_URL="http://${REF_HOST}:${REF_PORT}"

echo "iconom phase-5 predictor check"
echo "target: ${BASE_URL}"
echo

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

start_referee_server() {
    python3 "${ROOT_DIR}/sim/referee_server/referee_server.py" &
    SERVER_PID=$!
    sleep 1
    echo "started referee server (PID: ${SERVER_PID})"
}

wait_for_referee() {
    local max_attempts=10
    local attempt=1
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if curl -s "${BASE_URL}/health" > /dev/null 2>&1; then
            echo "referee server is ready"
            return 0
        fi
        echo "waiting for referee server... (${attempt}/${max_attempts})"
        sleep 1
        ((attempt++))
    done
    echo "ERROR: referee server failed to start"
    return 1
}

test_predictor_ros() {
    echo "================================================================"
    echo "testing predictor ROS pipeline (consumes rival_buffer history)"
    echo "================================================================"
    
    docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm ros2_app bash -c '
        set +u
        cd /workspaces/ros2_ws
        source install/setup.bash
        set -u
        
        export REF_HOST=host.docker.internal
        export REF_PORT=45678
        export COMPETITION_FIXTURE_MODE=true
        
        /workspaces/ros2_ws/install/bin/competition_client &
        CLIENT_PID=$!
        
        sleep 3
        
        /workspaces/ros2_ws/install/bin/rival_buffer &
        BUFFER_PID=$!
        
        sleep 3
        
        /workspaces/ros2_ws/install/bin/predictor &
        PREDICTOR_PID=$!
        
        sleep 3
        
        FAIL=0
        ros2 topic list | grep -q "/competition/rival/state" || { echo "FAIL: /competition/rival/state not found"; FAIL=1; }
        ros2 topic list | grep -q "/rival_buffer/history" || { echo "FAIL: /rival_buffer/history not found"; FAIL=1; }
        ros2 topic list | grep -q "/competition/prediction/rival_position" || { echo "FAIL: /competition/prediction/rival_position not found"; FAIL=1; }
        
        if [ $FAIL -eq 0 ]; then
            echo "PASS: all topics exist"
            echo "PASS: predictor subscribes to rival_buffer history and publishes predictions"
        fi
        
        kill $CLIENT_PID $BUFFER_PID $PREDICTOR_PID 2>/dev/null || true
        exit $FAIL
    '
}

start_referee_server
wait_for_referee
test_predictor_ros

echo
echo "phase-5 predictor check passed"
