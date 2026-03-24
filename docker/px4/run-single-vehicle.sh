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

if [[ "${PX4_INSTANCE:-0}" != "0" ]]; then
  echo "single-vehicle runtime requires PX4_INSTANCE=0" >&2
  exit 44
fi

if [[ "${ICONOM_GZ_MODEL_NAME:-rc_cessna_0}" != "rc_cessna_0" ]]; then
  echo "single-vehicle runtime requires ICONOM_GZ_MODEL_NAME=rc_cessna_0" >&2
  exit 45
fi

exec /usr/local/bin/px4-run-vehicle.sh
