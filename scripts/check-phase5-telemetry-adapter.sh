#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFERE_SERVER_PORT:-45678}"
BASE_URL="http://${REF_HOST}:${REF_PORT}"

echo "iconom phase-5 telemetry adapter check"
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

test_adapter_connection() {
    echo "================================================================"
    echo "testing adapter can authenticate and send telemetry"
    echo "================================================================"
    
    python3 -c "
import requests
import json
import time

base_url = '${BASE_URL}'
aircraft_id = 'plane_01'

# authenticate
resp = requests.post(f'{base_url}/login', json={'username': 'test_pilot', 'password': 'test_pass_123'})
assert resp.status_code == 200, f'login failed: {resp.status_code}'
data = resp.json()
token = data.get('token')
print(f'PASS: authenticated, token: {token}')

# send telemetry with live-simulated position
telemetry_payload = {
    'aircraft_id': aircraft_id,
    'position': {'x': 10.5, 'y': 20.3, 'z': 50.0},
    'velocity': {'x': 15.0, 'y': 5.2, 'z': 0.0},
    'heading': 45.0,
}
resp = requests.post(f'{base_url}/telemetry', json=telemetry_payload)
assert resp.status_code == 200, f'telemetry failed: {resp.status_code}'
data = resp.json()
assert 'rival_state' in data, 'no rival_state in response'
rival = data['rival_state']
print(f'PASS: telemetry sent, received rival state: {rival.get(\"aircraft_id\")}')
print(f'  rival position: {rival.get(\"position\")}')
print(f'  rival velocity: {rival.get(\"velocity\")}')

# verify telemetry format matches contract
assert rival['aircraft_id'] == 'plane_02', 'wrong rival aircraft'
assert 'position' in rival, 'no position in rival state'
assert 'velocity' in rival, 'no velocity in rival state'
assert 'heading' in rival, 'no heading in rival state'
print('PASS: telemetry format matches competition contract')
"
}

start_referee_server
wait_for_referee
test_adapter_connection

echo
echo "phase-5 telemetry adapter check passed"
