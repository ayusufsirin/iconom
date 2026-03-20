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

GZ_IP_VALUE="${GZ_IP:-$(hostname -I | awk '{print $1}')}"
if [[ -z "${GZ_IP_VALUE}" ]]; then
  echo "failed to determine Gazebo transport IP for the px4 container" >&2
  exit 44
fi

echo "starting PX4 single-vehicle runtime"
echo "  vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "  px4 namespace: ${PX4_UXRCE_DDS_NS}"
echo "  xrce agent host: ${PX4_UXRCE_DDS_HOST:-127.0.0.1}"
echo "  gazebo transport ip: ${GZ_IP_VALUE}"
echo "  px4 model: ${PX4_SIM_MODEL}"
echo "  px4 world: ${PX4_GZ_WORLD:-default}"
echo "  headless: ${PX4_HEADLESS:-1}"
echo "  autostart: ${PX4_SYS_AUTOSTART:-4003}"
echo "this uses PX4's native Gazebo launch path inside the px4 container for the first real runtime milestone"

PX4_BINARY="/opt/PX4-Autopilot/build/px4_sitl_default/bin/px4"
PX4_WORKDIR="/opt/PX4-Autopilot/build/px4_sitl_default/src/modules/simulation/gz_bridge"

if [[ ! -x "${PX4_BINARY}" ]]; then
  echo "expected PX4 SITL binary not found at ${PX4_BINARY}" >&2
  exit 45
fi

cd "${PX4_WORKDIR}"

ENV_ARGS=(
  GZ_IP="${GZ_IP_VALUE}"
  PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}"
  PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}"
  PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}"
  PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}"
  PX4_UXRCE_DDS_NS="${PX4_UXRCE_DDS_NS:-plane_01}"
)

if [[ "${PX4_HEADLESS:-1}" == "1" ]]; then
  ENV_ARGS+=(HEADLESS=1)
fi

exec env "${ENV_ARGS[@]}" "${PX4_BINARY}"
