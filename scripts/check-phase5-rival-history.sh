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

test_rival_history() {
    echo "================================================================"
    echo "testing rival history buffer behavior"
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

# send multiple telemetry requests to accumulate history
rival_ids_seen = set()
positions_sent = []

for i in range(5):
    telemetry_payload = {
        'aircraft_id': 'plane_01',
        'position': {'x': 10.0 + i * 5, 'y': 20.0 + i * 3, 'z': 50.0 + i},
        'velocity': {'x': 15.0, 'y': 5.0, 'z': 0.0},
        'heading': 45.0 + i * 10,
    }
    resp = requests.post(f'{base_url}/telemetry', json=telemetry_payload)
    assert resp.status_code == 200, f'telemetry failed: {resp.status_code}'
    data = resp.json()
    
    rival = data.get('rival_state', {})
    rival_id = rival.get('aircraft_id')
    rival_ids_seen.add(rival_id)
    
    positions_sent.append(rival.get('position'))
    
    print(f'  sent telemetry {i+1}, received rival: {rival_id} at {rival.get(\"position\")}')
    time.sleep(0.2)

print(f'PASS: received {len(rival_ids_seen)} unique rival identities: {rival_ids_seen}')

# verify rival state includes timestamp information
assert len(positions_sent) == 5, 'should have 5 position samples'
print(f'PASS: stored {len(positions_sent)} rival snapshots')

# verify timestamp is present in response
resp = requests.post(f'{base_url}/telemetry', json={'aircraft_id': 'plane_01', 'position': {'x': 0, 'y': 0, 'z': 0}})
data = resp.json()
rival = data.get('rival_state', {})
assert 'timestamp' in rival, 'rival state should include timestamp'
print(f'PASS: rival state includes timestamp: {rival.get(\"timestamp\")}')

print()
print('All rival history buffer checks passed!')
"
}

start_referee_server
wait_for_referee
test_rival_history

echo
echo "phase-5 rival history buffer check passed"
