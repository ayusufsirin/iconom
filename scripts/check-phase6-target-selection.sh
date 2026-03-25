#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "iconom phase-6 target-selection check"
echo

echo "================================================================"
echo "building iconom_guidance package"
echo "================================================================"
cd "${ROOT_DIR}"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running deterministic target-selector path"
echo "================================================================"
docker compose --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    rm -rf build install log
    mkdir -p /workspaces/ros2_ws/src
    if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
        vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
    fi
    colcon build --packages-up-to px4_msgs iconom_guidance --merge-install

    set +u
    source install/setup.bash
    set -u

    /workspaces/ros2_ws/install/bin/target_selector > /tmp/iconom-phase6-target-selector.log 2>&1 &
    SELECTOR_PID=$!

    cleanup_selector() {
        kill ${SELECTOR_PID} 2>/dev/null || true
        wait ${SELECTOR_PID} 2>/dev/null || true
    }
    trap cleanup_selector EXIT

    sleep 2

    ros2 topic pub --once /competition/ownship/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_01},
      pose: {
        position: {x: 0.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-ownship.log 2>&1

    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 100.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-rival-far.log 2>&1

    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_03},
      pose: {
        position: {x: 10.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-rival-near.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /guidance/selected_target > /tmp/iconom-phase6-selected-target-1.log

    grep -q "frame_id: plane_03" /tmp/iconom-phase6-selected-target-1.log
    grep -q "x: 10.0" /tmp/iconom-phase6-selected-target-1.log
    echo "PASS: target selector chose the nearer rival plane_03"

    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 2.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-rival-reselect.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /guidance/selected_target > /tmp/iconom-phase6-selected-target-2.log

    grep -q "frame_id: plane_02" /tmp/iconom-phase6-selected-target-2.log
    grep -q "x: 2.0" /tmp/iconom-phase6-selected-target-2.log
    echo "PASS: target selector reselected plane_02 when it became the nearer rival"
'

echo
echo "phase-6 target-selection check passed"
