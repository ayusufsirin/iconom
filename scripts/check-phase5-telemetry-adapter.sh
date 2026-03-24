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

echo "iconom phase-5 telemetry adapter check"
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
echo "building iconom_competition package"
echo "================================================================"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running real ownship_telemetry_adapter path"
echo "================================================================"
docker compose --profile phase5 --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    rm -rf build install log
    colcon build --packages-select px4_msgs iconom_competition --merge-install

    set +u
    source install/setup.bash
    set -u

    export REF_HOST=referee_server
    export REF_PORT=45678

    /workspaces/ros2_ws/install/bin/ownship_telemetry_adapter > /tmp/iconom-phase5-telemetry-adapter.log 2>&1 &
    ADAPTER_PID=$!

    cleanup_adapter() {
        kill ${ADAPTER_PID} 2>/dev/null || true
        wait ${ADAPTER_PID} 2>/dev/null || true
    }
    trap cleanup_adapter EXIT

    sleep 3

    ros2 topic pub --once /plane_01/fmu/out/vehicle_local_position px4_msgs/msg/VehicleLocalPosition "{
      x: 10.5,
      y: 20.25,
      z: -50.0,
      vx: 15.0,
      vy: 5.0,
      vz: 0.0
    }" >/tmp/iconom-phase5-local-position-pub.log 2>&1

    timeout 20 ros2 topic echo --once /competition/ownship/state > /tmp/iconom-phase5-ownship-state.log

    grep -q "authenticated with referee, token:" /tmp/iconom-phase5-telemetry-adapter.log
    echo "PASS: ownship_telemetry_adapter authenticated with referee"

    grep -q "telemetry sent, received rival:" /tmp/iconom-phase5-telemetry-adapter.log
    echo "PASS: ownship_telemetry_adapter sent telemetry through the real HTTP path"

    grep -q "frame_id: plane_01" /tmp/iconom-phase5-ownship-state.log
    grep -q "x: 10.5" /tmp/iconom-phase5-ownship-state.log
    grep -q "y: 20.25" /tmp/iconom-phase5-ownship-state.log
    echo "PASS: ownship_telemetry_adapter published live ownship state from PX4-shaped input"
'

echo
echo "phase-5 telemetry adapter check passed"
