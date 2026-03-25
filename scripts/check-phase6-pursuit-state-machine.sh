#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REUSE_WORKSPACE="${ICONOM_PHASE6_REUSE_WORKSPACE:-0}"
COLD_BUILD="${ICONOM_PHASE6_COLD_BUILD:-0}"

usage() {
  cat <<'USAGE'
Usage: check-phase6-pursuit-state-machine.sh [--incremental|--cold]

Run the current phase-6 pursuit-state-machine check.

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

echo "iconom phase-6 pursuit-state-machine check"
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
echo "running pursuit-state-machine path"
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

    publish_selected_target() {
        ros2 topic pub --once /guidance/selected_target geometry_msgs/msg/PoseStamped "{
          header: {frame_id: plane_03},
          pose: {
            position: {x: 10.0, y: 0.0, z: 0.0},
            orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
          }
        }" >/tmp/iconom-phase6-sm-selected.log 2>&1
    }

    wait_for_state() {
        expected="$1"
        output_file="$2"
        attempts="${3:-6}"

        for _ in $(seq 1 "${attempts}"); do
            if timeout 5 ros2 topic echo --once /guidance/pursuit_state > "${output_file}" 2>/dev/null; then
                if grep -q "data: ${expected}" "${output_file}"; then
                    return 0
                fi
            fi
            sleep 0.5
        done

        echo "expected pursuit state ${expected}" >&2
        cat "${output_file}" >&2 || true
        return 1
    }

    wait_for_goal() {
        frame_id="$1"
        expected_x="$2"
        output_file="$3"
        attempts="${4:-6}"

        for _ in $(seq 1 "${attempts}"); do
            if timeout 5 ros2 topic echo --once /guidance/pursuit_goal > "${output_file}" 2>/dev/null; then
                if grep -q "frame_id: ${frame_id}" "${output_file}" && grep -q "x: ${expected_x}" "${output_file}"; then
                    return 0
                fi
            fi
            sleep 0.5
        done

        echo "expected pursuit goal for ${frame_id} at x=${expected_x}" >&2
        cat "${output_file}" >&2 || true
        return 1
    }

    /workspaces/ros2_ws/install/bin/pursuit_state_machine --ros-args \
        -p publish_period_sec:=0.5 \
        -p selected_timeout_sec:=8.0 \
        -p intercept_timeout_sec:=5.0 \
        > /tmp/iconom-phase6-pursuit-sm.log 2>&1 &
    SM_PID=$!

    cleanup_sm() {
        kill ${SM_PID} 2>/dev/null || true
        wait ${SM_PID} 2>/dev/null || true
    }
    trap cleanup_sm EXIT

    sleep 2
    wait_for_state idle /tmp/iconom-phase6-state-idle.log
    echo "PASS: pursuit state machine starts in idle"

    publish_selected_target
    wait_for_state search /tmp/iconom-phase6-state-search.log
    echo "PASS: pursuit state machine entered search when only a selected target existed"

    ros2 topic pub --once /guidance/intercept_target geometry_msgs/msg/PoseStamped "{
      header: {frame_id: plane_03},
      pose: {
        position: {x: 5.0, y: 5.0, z: 0.0},
        orientation: {x: 0.0, y: 0.0, z: 0.0, w: 1.0}
      }
    }" >/tmp/iconom-phase6-sm-intercept.log 2>&1

    wait_for_state pursue /tmp/iconom-phase6-state-pursue.log
    wait_for_goal plane_03 5.0 /tmp/iconom-phase6-goal-pursue.log
    echo "PASS: pursuit state machine entered pursue and published the pursuit goal"

    publish_selected_target
    sleep 6
    wait_for_state reacquire /tmp/iconom-phase6-state-reacquire.log
    echo "PASS: pursuit state machine entered reacquire when the intercept target went stale"

    sleep 3
    wait_for_state idle /tmp/iconom-phase6-state-idle-2.log
    echo "PASS: pursuit state machine returned to idle when the selected target went stale"
'

echo
echo "phase-6 pursuit-state-machine check passed"
