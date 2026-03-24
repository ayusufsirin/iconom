#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFEREE_SERVER_PORT:-45678}"
BASE_URL="http://${REF_HOST}:${REF_PORT}"

echo "iconom phase-5 rival history buffer check"
echo "target: ${BASE_URL}"
echo

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
    docker compose -f "${ROOT_DIR}/docker-compose.yml" kill ros2_app 2>/dev/null || true
    docker compose -f "${ROOT_DIR}/docker-compose.yml" rm -f ros2_app 2>/dev/null || true
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

test_rival_history_ros() {
    echo "================================================================"
    echo "testing rival history buffer ROS pipeline"
    echo "================================================================"
    
    docker compose -f "${ROOT_DIR}/docker-compose.yml" build ros2_app --no-cache 2>/dev/null || true
    
    docker compose -f "${ROOT_DIR}/docker-compose.yml" run --rm ros2_app timeout 60 bash -c "
        set -euo pipefail
        cd /workspaces/ros2_ws
        rm -rf install
        colcon build --packages-select px4_msgs iconom_competition --merge-install 2>&1 || { echo 'build failed'; exit 1; }
        echo 'packages built'
        
        set +u; source install/setup.bash; set -u
        
        export REF_HOST=host.docker.internal
        export REF_PORT=45678
        export COMPETITION_FIXTURE_MODE=true
        
        /workspaces/ros2_ws/install/bin/competition_client &
        CLIENT_PID=\$!
        
        sleep 2
        
        /workspaces/ros2_ws/install/bin/rival_buffer &
        BUFFER_PID=\$!
        
        sleep 3
        
        if ros2 topic list | grep -q '/competition/rival/state'; then
            echo 'PASS: /competition/rival/state exists'
        else
            echo 'FAIL: /competition/rival/state not found'
            kill \$CLIENT_PID \$BUFFER_PID 2>/dev/null || true
            exit 1
        fi
        
        if ros2 topic list | grep -q '/rival_buffer/history'; then
            echo 'PASS: /rival_buffer/history exists'
        else
            echo 'FAIL: /rival_buffer/history not found'
            kill \$CLIENT_PID \$BUFFER_PID 2>/dev/null || true
            exit 1
        fi
        
        echo 'PASS: rival_buffer publishes to /rival_buffer/history'
        
        kill \$CLIENT_PID \$BUFFER_PID 2>/dev/null || true
        exit 0
    "
}

start_referee_server
wait_for_referee
test_rival_history_ros

echo
echo "phase-5 rival history buffer check passed"
