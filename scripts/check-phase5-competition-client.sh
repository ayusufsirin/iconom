#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFEREE_SERVER_PORT:-45678}"
BASE_URL="http://${REF_HOST}:${REF_PORT}"

echo "iconom phase-5 competition client check"
echo "target: ${BASE_URL}"
echo

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
    if [[ -n "${CLIENT_PID:-}" ]]; then
        kill "${CLIENT_PID}" 2>/dev/null || true
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

build_and_run_competition_package() {
    echo "================================================================"
    echo "building and testing iconom_competition package"
    echo "================================================================"
    docker compose build ros2_app --no-cache 2>/dev/null || true
    docker compose run --rm ros2_app bash -c "
        set -euo pipefail
        cd /workspaces/ros2_ws
        rm -rf install
        colcon build --packages-select px4_msgs iconom_competition --merge-install 2>&1 || {
            echo 'build failed'
            exit 1
        }
        echo 'package built successfully'
        
        set +u; source install/setup.bash; set -u
        export REF_HOST=host.docker.internal
        export REF_PORT=45678
        export COMPETITION_FIXTURE_MODE=true
        /workspaces/ros2_ws/install/bin/competition_client &
        CLIENT_PID=$!
        CLIENT_PID=\$!
        sleep 3
        if ros2 topic list | grep -q '/competition/rival/state'; then
            echo 'PASS: /competition/rival/state exists'
        else
            echo 'FAIL: /competition/rival/state not found'
            kill \$CLIENT_PID 2>/dev/null || true
            exit 1
        fi
        if ros2 topic list | grep -q '/competition/ownship/state'; then
            echo 'PASS: /competition/ownship/state exists'
        else
            echo 'FAIL: /competition/ownship/state not found'
            kill \$CLIENT_PID 2>/dev/null || true
            exit 1
        fi
        echo 'PASS: client published topics'
        kill \$CLIENT_PID 2>/dev/null || true
        exit 0
    "
}

test_client_connection() {
    echo "================================================================"
    echo "checking client can reach referee"
    echo "================================================================"
    
    python3 -c "
import requests
import json

base_url = '${BASE_URL}'

# test login
resp = requests.post(f'{base_url}/login', json={'username': 'test_pilot', 'password': 'test_pass_123'})
assert resp.status_code == 200, f'login failed: {resp.status_code}'
data = resp.json()
assert 'token' in data, 'no token in login response'
print('PASS: client can login')

# test time
resp = requests.get(f'{base_url}/time')
assert resp.status_code == 200, f'time failed: {resp.status_code}'
data = resp.json()
assert 'server_time' in data, 'no server_time in response'
print('PASS: client can fetch server time')

# test telemetry
resp = requests.post(f'{base_url}/telemetry', json={'aircraft_id': 'plane_01', 'position': {'x': 0, 'y': 0, 'z': 10}})
assert resp.status_code == 200, f'telemetry failed: {resp.status_code}'
data = resp.json()
assert 'rival_state' in data, 'no rival_state in response'
print('PASS: client can send telemetry and receive rival state')
"
}

start_referee_server
wait_for_referee

echo "================================================================"
echo "testing client connection to referee"
echo "================================================================"
test_client_connection

echo "================================================================"
echo "building and testing ROS competition client"
echo "================================================================"
build_and_run_competition_package

echo
echo "phase-5 competition client check passed"
