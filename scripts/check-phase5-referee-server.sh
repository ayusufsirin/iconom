#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_HOST="${REF_HOST:-localhost}"
REF_PORT="${REFERE_SERVER_PORT:-45678}"
BASE_URL="http://${REF_HOST}:${REF_PORT}"

echo "iconom phase-5 referee server check"
echo "target: ${BASE_URL}"
echo

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT

start_server() {
    python3 "${ROOT_DIR}/sim/referee_server/referee_server.py" &
    SERVER_PID=$!
    sleep 1
    echo "started referee server (PID: ${SERVER_PID})"
}

check_endpoint() {
    local method="$1"
    local path="$2"
    local data="$3"
    local expected_key="$4"
    
    if [[ "${method}" == "GET" ]]; then
        response=$(curl -s -w "\n%{http_code}" "${BASE_URL}${path}")
    else
        response=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" -d "${data}" "${BASE_URL}${path}")
    fi
    
    body=$(echo "${response}" | head -n -1)
    status=$(echo "${response}" | tail -n1)
    
    if [[ "${status}" != "200" ]]; then
        echo "FAIL: ${path} returned status ${status}"
        echo "response: ${body}"
        return 1
    fi
    
    if [[ -n "${expected_key}" ]]; then
        if ! echo "${body}" | grep -q "${expected_key}"; then
            echo "FAIL: ${path} response missing '${expected_key}'"
            echo "response: ${body}"
            return 1
        fi
    fi
    
    echo "PASS: ${path}"
    return 0
}

start_server

echo "================================================================"
echo "checking health endpoint"
echo "================================================================"
check_endpoint GET "/health" "" "status"
echo

echo "================================================================"
echo "checking server time endpoint"
echo "================================================================"
check_endpoint GET "/time" "" "server_time"
echo

echo "================================================================"
echo "checking login endpoint with fixture credentials"
echo "================================================================"
check_endpoint POST "/login" '{"username":"test_pilot","password":"test_pass_123"}' "token"
echo

echo "================================================================"
echo "checking telemetry endpoint with fixture ownship payload"
echo "================================================================"
check_endpoint POST "/telemetry" '{"aircraft_id":"plane_01","position":{"x":0,"y":0,"z":0}}' "rival_state"
echo

echo "phase-5 referee server check passed"
