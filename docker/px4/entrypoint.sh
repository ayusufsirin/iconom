#!/usr/bin/env bash
set -euo pipefail

PX4_BIN="/opt/PX4-Autopilot/build/px4_sitl_default/bin/px4"

if [[ ! -x "${PX4_BIN}" ]]; then
  echo "px4 binary missing: ${PX4_BIN}" >&2
  exit 20
fi

"${PX4_BIN}" --help >/dev/null

echo "px4 slice ready"
echo "  PX4_GIT_REF=${PX4_GIT_REF:-unknown}"
echo "  PX4_UXRCE_DDS_NS=${PX4_UXRCE_DDS_NS:-}"
echo "  UXRCE_DDS_KEY=${UXRCE_DDS_KEY:-}"
echo "  XRCE_AGENT_UDP_PORT=${XRCE_AGENT_UDP_PORT:-}"
echo "  MAVLINK_OFFBOARD_BASE_PORT=${MAVLINK_OFFBOARD_BASE_PORT:-}"
echo "  MAVLINK_GCS_PORT=${MAVLINK_GCS_PORT:-}"
echo "  PX4_SIM_MODEL=${PX4_SIM_MODEL:-}"
echo "gazebo is not implemented yet; runtime validation stops at binary and config checks"

exec bash -lc "sleep infinity"
