#!/usr/bin/env bash

sim_now_sec() {
  local clock_output sec nanosec
  clock_output="$(ros2_exec '
      set -euo pipefail
      set +u
      source /opt/ros/humble/setup.bash
      source /workspaces/ros2_ws/install/setup.bash
      set -u
      timeout 10 ros2 topic echo --once /clock 2>/dev/null || true
    ')"
  sec="$(awk '/^[[:space:]]*sec:/{print $2; exit}' <<<"${clock_output}")"
  nanosec="$(awk '/^[[:space:]]*nanosec:/{print $2; exit}' <<<"${clock_output}")"
  if [[ -z "${sec}" || -z "${nanosec}" ]]; then
    return 1
  fi
  awk -v sec="${sec}" -v nanosec="${nanosec}" 'BEGIN { printf "%.9f\n", sec + (nanosec / 1000000000.0) }'
}

wait_for_sim_seconds() {
  local duration_sec="$1"
  local label="$2"
  local wall_start wall_now start_sec current_sec elapsed_sec wall_timeout_sec

  if [[ -n "${PHASE6_SIM_WAIT_WALL_TIMEOUT_SEC:-}" ]]; then
    wall_timeout_sec="${PHASE6_SIM_WAIT_WALL_TIMEOUT_SEC}"
  else
    wall_timeout_sec="$(awk -v duration="${duration_sec}" 'BEGIN { timeout = (duration * 5.0) + 60.0; if (timeout < 120.0) timeout = 120.0; printf "%d\n", int(timeout + 0.999) }')"
  fi

  wall_start="$(date +%s)"
  start_sec="$(sim_now_sec)" || {
    echo "could not read /clock while waiting for ${label}" >&2
    return 1
  }

  while true; do
    current_sec="$(sim_now_sec)" || {
      sleep 0.5
      wall_now="$(date +%s)"
      if (( wall_now - wall_start > wall_timeout_sec )); then
        echo "timed out waiting for /clock while waiting for ${label}" >&2
        return 1
      fi
      continue
    }
    elapsed_sec="$(awk -v start="${start_sec}" -v current="${current_sec}" 'BEGIN { print current - start }')"
    if awk -v elapsed="${elapsed_sec}" -v duration="${duration_sec}" 'BEGIN { exit !(elapsed >= duration) }'; then
      return 0
    fi
    wall_now="$(date +%s)"
    if (( wall_now - wall_start > wall_timeout_sec )); then
      echo "timed out waiting ${duration_sec}s of sim time for ${label}" >&2
      return 1
    fi
    sleep 0.5
  done
}
