#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
    cd "${ROOT_DIR}"
    docker compose --profile phase5 --env-file .env.example down --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "iconom phase-5 rival history buffer check"
echo

echo "================================================================"
echo "building iconom_competition package"
echo "================================================================"
cd "${ROOT_DIR}"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running real rival_buffer ROS path"
echo "================================================================"
docker compose --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    rm -rf build install log
    colcon build --packages-select px4_msgs iconom_competition --merge-install

    set +u
    source install/setup.bash
    set -u

    /workspaces/ros2_ws/install/bin/rival_buffer > /tmp/iconom-phase5-rival-buffer.log 2>&1 &
    BUFFER_PID=$!

    cleanup_buffer() {
        kill ${BUFFER_PID} 2>/dev/null || true
        wait ${BUFFER_PID} 2>/dev/null || true
    }
    trap cleanup_buffer EXIT

    sleep 2

    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 10.0, y: 20.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase5-rival-history-pub-1.log 2>&1
    sleep 0.5
    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 11.0, y: 22.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.1, w: 0.99}
      }
    }" >/tmp/iconom-phase5-rival-history-pub-2.log 2>&1
    sleep 0.5
    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 12.0, y: 24.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.2, w: 0.98}
      }
    }" >/tmp/iconom-phase5-rival-history-pub-3.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /rival_buffer/history > /tmp/iconom-phase5-rival-history.log

    grep -q "frame_id: plane_02" /tmp/iconom-phase5-rival-history.log
    echo "PASS: rival_buffer published history for the injected rival id"

    POSITION_COUNT=$(grep -c "position:" /tmp/iconom-phase5-rival-history.log || true)
    if [[ ${POSITION_COUNT} -lt 3 ]]; then
        echo "FAIL: rival history output did not contain the expected buffered poses"
        cat /tmp/iconom-phase5-rival-history.log
        exit 1
    fi

    grep -q "x: 10.0" /tmp/iconom-phase5-rival-history.log
    grep -q "x: 11.0" /tmp/iconom-phase5-rival-history.log
    grep -q "x: 12.0" /tmp/iconom-phase5-rival-history.log
    echo "PASS: rival_buffer retained multiple injected rival samples"
'

echo
echo "phase-5 rival history check passed"
