#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "iconom phase-6 intercept-planner check"
echo

echo "================================================================"
echo "building iconom_guidance package"
echo "================================================================"
cd "${ROOT_DIR}"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running bounded intercept-planner path"
echo "================================================================"
docker compose --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    rm -rf build install log
    colcon build --packages-select iconom_guidance --merge-install

    set +u
    source install/setup.bash
    set -u

    /workspaces/ros2_ws/install/bin/intercept_planner > /tmp/iconom-phase6-intercept-planner.log 2>&1 &
    PLANNER_PID=$!

    cleanup_planner() {
        kill ${PLANNER_PID} 2>/dev/null || true
        wait ${PLANNER_PID} 2>/dev/null || true
    }
    trap cleanup_planner EXIT

    sleep 2

    ros2 topic pub --once /competition/ownship/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_01},
      pose: {
        position: {x: 0.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-intercept-ownship.log 2>&1

    ros2 topic pub --once /guidance/selected_target geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_03},
      pose: {
        position: {x: 100.0, y: 0.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-intercept-selected.log 2>&1

    ros2 topic pub --once /competition/prediction/rival_position geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_03},
      pose: {
        position: {x: 40.0, y: 30.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-intercept-predicted.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /guidance/intercept_target > /tmp/iconom-phase6-intercept-target-1.log

    grep -q "frame_id: plane_03" /tmp/iconom-phase6-intercept-target-1.log
    grep -q "x: 20.0" /tmp/iconom-phase6-intercept-target-1.log
    grep -q "y: 15.0" /tmp/iconom-phase6-intercept-target-1.log
    echo "PASS: intercept planner clamped the predicted rival target to the bounded intercept distance"

    ros2 topic pub --once /competition/prediction/rival_position geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_03},
      pose: {
        position: {x: 12.0, y: 5.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-intercept-predicted-near.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /guidance/intercept_target > /tmp/iconom-phase6-intercept-target-2.log

    grep -q "frame_id: plane_03" /tmp/iconom-phase6-intercept-target-2.log
    grep -q "x: 12.0" /tmp/iconom-phase6-intercept-target-2.log
    grep -q "y: 5.0" /tmp/iconom-phase6-intercept-target-2.log
    echo "PASS: intercept planner preserved the predicted rival target when it was already within bounds"
'

echo
echo "phase-6 intercept-planner check passed"
