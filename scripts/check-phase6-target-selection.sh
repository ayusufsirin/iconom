#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REUSE_WORKSPACE="${ICONOM_PHASE6_REUSE_WORKSPACE:-0}"
COLD_BUILD="${ICONOM_PHASE6_COLD_BUILD:-0}"

usage() {
  cat <<'USAGE'
Usage: check-phase6-target-selection.sh [--incremental|--cold]

Run the current phase-6 target-selection check.

Environment:
  ICONOM_PHASE6_REUSE_WORKSPACE=0|1
  ICONOM_PHASE6_COLD_BUILD=0|1
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cold)
      COLD_BUILD=1
      shift
      ;;
    --incremental)
      COLD_BUILD=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

echo "iconom phase-6 target-selection check"
echo

if [[ "${REUSE_WORKSPACE}" == "1" ]]; then
  echo "================================================================"
  echo "reusing prepared phase-6 workspace"
  echo "================================================================"
else
  echo "================================================================"
  echo "preparing phase-6 guidance workspace ($([[ "${COLD_BUILD}" == "1" ]] && echo cold rebuild || echo incremental build))"
  echo "================================================================"
  cd "${ROOT_DIR}"
  docker compose --env-file .env.example build ros2_app
fi

echo "================================================================"
echo "running deterministic target-selector path"
echo "================================================================"
docker compose --env-file .env.example run --rm -e ICONOM_PHASE6_REUSE_WORKSPACE="${REUSE_WORKSPACE}" -e ICONOM_PHASE6_COLD_BUILD="${COLD_BUILD}" ros2_app bash -c '
    set -euo pipefail
    cd /workspaces/ros2_ws
    if [[ "${ICONOM_PHASE6_REUSE_WORKSPACE:-0}" != "1" ]]; then
        if [[ "${ICONOM_PHASE6_COLD_BUILD:-0}" == "1" ]]; then
            rm -rf build install log
        fi
        mkdir -p /workspaces/ros2_ws/src
        if [[ ! -d /workspaces/ros2_ws/src/px4_msgs ]]; then
            vcs import /workspaces/ros2_ws/src < /workspaces/ros2_ws/src/px4_msgs.repos
        fi
        colcon build --packages-up-to px4_msgs iconom_guidance --merge-install
    fi

    if [[ ! -f install/setup.bash ]]; then
        echo "missing install/setup.bash for phase-6 guidance workspace" >&2
        exit 1
    fi

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
