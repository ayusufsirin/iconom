#!/usr/bin/env bash
set -euo pipefail

if [[ "${ICONOM_VEHICLE_NAMESPACE:-}" != "plane_01" ]]; then
  echo "single-vehicle runtime requires ICONOM_VEHICLE_NAMESPACE=plane_01" >&2
  exit 41
fi

if [[ "${PX4_UXRCE_DDS_NS:-}" != "plane_01" ]]; then
  echo "single-vehicle runtime requires PX4_UXRCE_DDS_NS=plane_01" >&2
  exit 42
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "single-vehicle runtime requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 43
fi

cd /opt/PX4-Autopilot

echo "starting PX4 single-vehicle runtime"
echo "  vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "  px4 namespace: ${PX4_UXRCE_DDS_NS}"
echo "  px4 model: ${PX4_SIM_MODEL}"
echo "  px4 world: ${PX4_GZ_WORLD:-default}"
echo "  headless: ${PX4_HEADLESS:-1}"
echo "  autostart: ${PX4_SYS_AUTOSTART:-4003}"
echo "this uses PX4's native Gazebo launch path inside the px4 container for the first real runtime milestone"

exec env \
  HEADLESS="${PX4_HEADLESS:-1}" \
  PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}" \
  PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}" \
  PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}" \
  PX4_UXRCE_DDS_NS="${PX4_UXRCE_DDS_NS:-plane_01}" \
  make px4_sitl gz_rc_cessna
