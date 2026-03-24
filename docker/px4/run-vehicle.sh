#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${ICONOM_VEHICLE_NAMESPACE:-}" ]]; then
  echo "ICONOM_VEHICLE_NAMESPACE must be set" >&2
  exit 41
fi

if [[ -z "${PX4_UXRCE_DDS_NS:-}" ]]; then
  echo "PX4_UXRCE_DDS_NS must be set" >&2
  exit 42
fi

if [[ "${PX4_UXRCE_DDS_NS}" != "${ICONOM_VEHICLE_NAMESPACE}" ]]; then
  echo "PX4_UXRCE_DDS_NS must match ICONOM_VEHICLE_NAMESPACE" >&2
  exit 43
fi

if [[ "${PX4_SIM_MODEL:-}" != "gz_rc_cessna" ]]; then
  echo "phase-4 runtime contract currently requires PX4_SIM_MODEL=gz_rc_cessna" >&2
  exit 44
fi

PX4_INSTANCE_VALUE="${PX4_INSTANCE:-0}"
if ! [[ "${PX4_INSTANCE_VALUE}" =~ ^[0-9]+$ ]]; then
  echo "PX4_INSTANCE must be a non-negative integer" >&2
  exit 45
fi

EXPECTED_SYS_ID="$((PX4_INSTANCE_VALUE + 1))"
EXPECTED_OFFBOARD_PORT="$(( ${MAVLINK_OFFBOARD_BASE_PORT:-14540} + PX4_INSTANCE_VALUE ))"
AUTO_MODEL_NAME="${PX4_SIM_MODEL#gz_}_${PX4_INSTANCE_VALUE}"
EXPECTED_MODEL_NAME="${PX4_GZ_MODEL_NAME:-${ICONOM_GZ_MODEL_NAME:-${AUTO_MODEL_NAME}}}"
EXPECTED_XRCE_KEY="${ICONOM_EXPECTED_UXRCE_DDS_KEY:-$((PX4_INSTANCE_VALUE + 1))}"
ACTUAL_XRCE_KEY="${UXRCE_DDS_KEY:-}"

if [[ -n "${ICONOM_EXPECTED_MAV_SYS_ID:-}" ]] && [[ "${ICONOM_EXPECTED_MAV_SYS_ID}" != "${EXPECTED_SYS_ID}" ]]; then
  echo "expected MAV sys id ${ICONOM_EXPECTED_MAV_SYS_ID} does not match PX4_INSTANCE-derived ${EXPECTED_SYS_ID}" >&2
  exit 46
fi

if [[ -n "${ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT:-}" ]] && [[ "${ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT}" != "${EXPECTED_OFFBOARD_PORT}" ]]; then
  echo "expected MAVLink offboard port ${ICONOM_EXPECTED_MAVLINK_OFFBOARD_PORT} does not match PX4_INSTANCE-derived ${EXPECTED_OFFBOARD_PORT}" >&2
  exit 47
fi

if [[ -n "${ICONOM_GZ_MODEL_NAME:-}" ]] && [[ "${ICONOM_GZ_MODEL_NAME}" != "${AUTO_MODEL_NAME}" ]]; then
  echo "expected Gazebo model name ${ICONOM_GZ_MODEL_NAME} does not match PX4_INSTANCE-derived ${AUTO_MODEL_NAME}" >&2
  exit 48
fi

if [[ -z "${ACTUAL_XRCE_KEY}" ]]; then
  echo "UXRCE_DDS_KEY must be set" >&2
  exit 49
fi

if ! [[ "${ACTUAL_XRCE_KEY}" =~ ^[0-9]+$ ]]; then
  echo "UXRCE_DDS_KEY must be a non-negative integer" >&2
  exit 50
fi

if [[ "${ACTUAL_XRCE_KEY}" != "${EXPECTED_XRCE_KEY}" ]]; then
  echo "expected UXRCE_DDS_KEY ${EXPECTED_XRCE_KEY} does not match actual ${ACTUAL_XRCE_KEY}" >&2
  exit 51
fi

cd /opt/PX4-Autopilot

if [[ -n "${GZ_IP:-}" ]]; then
  GZ_IP_VALUE="${GZ_IP}"
else
  GZ_IP_VALUE="$(hostname -I | awk '{print $1}')"
fi

if [[ -z "${GZ_IP_VALUE}" ]]; then
  echo "failed to determine Gazebo transport IP for the px4 container" >&2
  exit 52
fi

echo "starting PX4 runtime"
echo "  vehicle namespace: ${ICONOM_VEHICLE_NAMESPACE}"
echo "  px4 namespace: ${PX4_UXRCE_DDS_NS}"
echo "  px4 instance: ${PX4_INSTANCE_VALUE}"
echo "  expected mav sys id: ${EXPECTED_SYS_ID}"
echo "  expected mavlink offboard port: ${EXPECTED_OFFBOARD_PORT}"
echo "  expected gazebo model name: ${EXPECTED_MODEL_NAME}"
echo "  expected xrce dds key: ${EXPECTED_XRCE_KEY}"
echo "  px4 model: ${PX4_SIM_MODEL}"
echo "  px4 world: ${PX4_GZ_WORLD:-default}"
echo "  xrce agent host: ${PX4_UXRCE_DDS_HOST:-127.0.0.1}"
echo "  xrce dds key: ${ACTUAL_XRCE_KEY}"
echo "  gazebo transport ip: ${GZ_IP_VALUE}"
echo "  model pose: ${PX4_GZ_MODEL_POSE:-0,0,0}"
echo "  headless: ${PX4_HEADLESS:-1}"
echo "  autostart: ${PX4_SYS_AUTOSTART:-4003}"
echo "  standalone gazebo: ${PX4_GZ_STANDALONE:-0}"

if [[ "${PX4_GZ_STANDALONE:-0}" == "1" ]]; then
  echo "this uses an external Gazebo runtime owned by the gazebo service"
fi

PX4_BINARY="/opt/PX4-Autopilot/build/px4_sitl_default/bin/px4"
PX4_WORKDIR="/opt/PX4-Autopilot/build/px4_sitl_default/src/modules/simulation/gz_bridge"

if [[ ! -x "${PX4_BINARY}" ]]; then
  echo "expected PX4 SITL binary not found at ${PX4_BINARY}" >&2
  exit 53
fi

cd "${PX4_WORKDIR}"

ENV_ARGS=(
  GZ_IP="${GZ_IP_VALUE}"
  PX4_SYS_AUTOSTART="${PX4_SYS_AUTOSTART:-4003}"
  PX4_GZ_WORLD="${PX4_GZ_WORLD:-default}"
  PX4_SIM_MODEL="${PX4_SIM_MODEL:-gz_rc_cessna}"
  PX4_INSTANCE="${PX4_INSTANCE_VALUE}"
  PX4_UXRCE_DDS_HOST="${PX4_UXRCE_DDS_HOST:-xrce_agent}"
  PX4_UXRCE_DDS_NS="${PX4_UXRCE_DDS_NS}"
  UXRCE_DDS_KEY="${ACTUAL_XRCE_KEY}"
)

if [[ -n "${PX4_GZ_MODEL_POSE:-}" ]]; then
  ENV_ARGS+=(PX4_GZ_MODEL_POSE="${PX4_GZ_MODEL_POSE}")
fi

if [[ -n "${PX4_GZ_MODEL_NAME:-}" ]]; then
  ENV_ARGS+=(PX4_GZ_MODEL_NAME="${PX4_GZ_MODEL_NAME}")
fi

if [[ "${PX4_HEADLESS:-1}" == "1" ]]; then
  ENV_ARGS+=(HEADLESS=1)
fi

if [[ "${PX4_GZ_STANDALONE:-0}" == "1" ]]; then
  ENV_ARGS+=(PX4_GZ_STANDALONE=1)
fi

exec env "${ENV_ARGS[@]}" "${PX4_BINARY}" -i "${PX4_INSTANCE_VALUE}"
