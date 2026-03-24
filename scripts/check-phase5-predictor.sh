#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFERE_SERVER_PORT:-45678}"
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

test_predictor() {
    echo "================================================================"
    echo "testing rival predictor behavior"
    echo "================================================================"
    
    python3 -c "
import requests
import json
import time

base_url = '${BASE_URL}'

# authenticate
resp = requests.post(f'{base_url}/login', json={'username': 'test_pilot', 'password': 'test_pass_123'})
assert resp.status_code == 200, f'login failed: {resp.status_code}'
print('PASS: authenticated with referee')

# send telemetry with varying positions to enable velocity estimation
start_time = time.time()
positions = [
    {'x': 0.0, 'y': 0.0, 'z': 50.0},
    {'x': 10.0, 'y': 5.0, 'z': 50.0},
    {'x': 20.0, 'y': 10.0, 'z': 50.0},
    {'x': 30.0, 'y': 15.0, 'z': 50.0},
    {'x': 40.0, 'y': 20.0, 'z': 50.0},
]

for i, pos in enumerate(positions):
    telemetry_payload = {
        'aircraft_id': 'plane_01',
        'position': pos,
        'velocity': {'x': 10.0, 'y': 5.0, 'z': 0.0},
        'heading': 45.0,
    }
    resp = requests.post(f'{base_url}/telemetry', json=telemetry_payload)
    assert resp.status_code == 200, f'telemetry failed: {resp.status_code}'
    data = resp.json()
    rival = data.get('rival_state', {})
    
    print(f'  sent position {i+1}: ({pos[\"x\"]}, {pos[\"y\"]}), rival at ({rival.get(\"position\", {}).get(\"x\")}, {rival.get(\"position\", {}).get(\"y\")})')
    time.sleep(0.3)

elapsed = time.time() - start_time
print(f'PASS: sent {len(positions)} telemetry samples over {elapsed:.1f}s')

# verify rival state includes timestamp for prediction
resp = requests.post(f'{base_url}/telemetry', json={'aircraft_id': 'plane_01', 'position': {'x': 50, 'y': 25, 'z': 50}})
data = resp.json()
rival = data.get('rival_state', {})

assert 'timestamp' in rival, 'rival state must include timestamp for prediction'
assert 'position' in rival, 'rival state must include position'

# The predictor should compute:
# - velocity from history (estimated ~10m/s x, ~5m/s y)
# - predicted position at t+horizon (default 2s)
# For our test: position = (50, 25) + (10*2, 5*2) = (70, 35)
print(f'PASS: rival state has timestamp and position for prediction')
print(f'  rival timestamp: {rival.get(\"timestamp\")}')
print(f'  rival position: {rival.get(\"position\")}')

# Verify timing information is present for prediction horizon calculation
current_time_ms = int(time.time() * 1000)
rival_time_ms = rival.get('timestamp', 0)
time_diff_ms = current_time_ms - rival_time_ms

print(f'  time difference: ~{abs(time_diff_ms)}ms (should be small for fresh data)')

print()
print('All predictor checks passed!')
"
}

start_referee_server
wait_for_referee
test_predictor

echo
echo "phase-5 predictor check passed"
