#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "iconom phase-5 predictor check"
echo

echo "================================================================"
echo "building iconom_competition package"
echo "================================================================"
cd "${ROOT_DIR}"
docker compose --env-file .env.example build ros2_app

echo "================================================================"
echo "running real predictor ROS path"
echo "================================================================"
docker compose --env-file .env.example run --rm ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    rm -rf build install log
    colcon build --packages-select px4_msgs iconom_competition --merge-install

    set +u
    source install/setup.bash
    set -u

    /workspaces/ros2_ws/install/bin/predictor > /tmp/iconom-phase5-predictor.log 2>&1 &
    PREDICTOR_PID=$!

    cleanup_predictor() {
        kill ${PREDICTOR_PID} 2>/dev/null || true
        wait ${PREDICTOR_PID} 2>/dev/null || true
    }
    trap cleanup_predictor EXIT

    sleep 2

    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 0.0, y: 0.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase5-predictor-pub-1.log 2>&1
    sleep 1
    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 10.0, y: 0.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase5-predictor-pub-2.log 2>&1
    sleep 1
    ros2 topic pub --once /competition/rival/state geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_02},
      pose: {
        position: {x: 20.0, y: 0.0, z: 30.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase5-predictor-pub-3.log 2>&1

    sleep 2
    timeout 20 ros2 topic echo --once /competition/prediction/rival_position > /tmp/iconom-phase5-prediction.log

    python3 -c "from pathlib import Path; import re; pred = Path(\"/tmp/iconom-phase5-prediction.log\").read_text(); pred_match = re.search(r\"\\n\\s*x:\\s*([-0-9.]+)\", pred); assert \"frame_id: plane_02\" in pred, \"FAIL: prediction frame_id was not plane_02\"; assert pred_match, \"FAIL: predicted x position not found\"; pred_x = float(pred_match.group(1)); assert pred_x > 20.0, f\"FAIL: predicted x position {pred_x} did not advance beyond the last injected sample 20.0\"; print(\"PASS: predictor published a rival prediction for plane_02\"); print(f\"PASS: predicted x position advanced beyond the last injected sample: {pred_x} > 20.0\")"
'

echo
echo "phase-5 predictor check passed"
