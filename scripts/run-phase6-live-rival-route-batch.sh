#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="${ROOT_DIR}/scripts/check-phase6-live-rival-geometry.sh"
EXPORT_SCRIPT="${ROOT_DIR}/scripts/export-phase6-czml.py"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
DEFAULT_CSV_PATH="${ROOT_DIR}/ros2_ws/.tmp-phase6-live-rival-geometry.csv"
OUTPUT_DIR="${ROOT_DIR}/ros2_ws/phase6-route-batch-$(date -u +%Y%m%d-%H%M%S)"
BUILD_MODE="--incremental"
GUI_MODE="${ICONOM_USE_GUI:-0}"
PX4_HEADLESS_VALUE="1"
if [[ "${GUI_MODE}" == "1" ]]; then
  PX4_HEADLESS_VALUE="0"
fi

ROUTE_CASES=(
  'R0_straight_baseline|120,0;240,0;360,0;480,0|current straight-path regression baseline'
  'R1_straight_longer|160,0;320,0;480,0;640,0|longer straight route for post-lock hold diagnosis'
  'R2_gentle_single_turn|120,0;240,20;360,40;480,60|gentle single-turn route for mild curvature retention'
  'R3_two_leg_L_turn|140,0;280,0;280,120;280,240|two-leg L route for transition stress'
)

usage() {
  echo "Usage: run-phase6-live-rival-route-batch.sh [--incremental|--cold] [--output-dir DIR]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --incremental) BUILD_MODE="--incremental"; shift ;;
    --cold) BUILD_MODE="--cold"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

compose_down() {
  local -a compose_args=(--profile phase4 --profile phase5 --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
  if [[ "${GUI_MODE}" == "1" ]]; then
    compose_args+=(-f "${OVERRIDE_FILE}")
  fi
  docker compose "${compose_args[@]}" down --remove-orphans >/dev/null 2>&1 || true
}

summarize_run_log() {
  local run_log="$1"
  env python3 - "${run_log}" <<'PY'
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
if not log_path.is_file():
    print("missing run log")
    raise SystemExit(0)

lines = [line.strip() for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines() if line.strip()]
summary = "completed"
for line in reversed(lines):
    if (
        "no sustained catch window" in line
        or "initial range" in line
        or "timed out" in line
        or "did not" in line
        or "failed" in line
        or "succeeded" in line
        or "logs kept" in line
        or "required" in line
        or "Conflict." in line
    ):
        summary = line
        break
print(summary.replace(",", ";"))
PY
}

summarize_csv() {
  local csv_path="$1"
  env python3 - "${csv_path}" <<'PY'
import csv
import math
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
if not csv_path.is_file():
    print("missing,missing,missing,none,missing,missing,missing")
    raise SystemExit(0)

with csv_path.open(newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle))

if not rows:
    print("empty,empty,empty,none,empty,empty,empty")
    raise SystemExit(0)

def f(name, row):
    value = row.get(name, "")
    return float(value) if value not in ("", None) else float("nan")

min_range = float("inf")
min_cue = float("inf")
min_bearing = float("inf")
phases = []
first_settle = ""
first_follow_lock = ""
first_follow_hold = ""

for row in rows:
    own_x = f("own_x", row)
    own_y = f("own_y", row)
    own_z = f("own_z", row)
    rival_x = f("rival_x", row)
    rival_y = f("rival_y", row)
    rival_z = f("rival_z", row)
    if not any(math.isnan(v) for v in (own_x, own_y, own_z, rival_x, rival_y, rival_z)):
        current_range = math.sqrt((rival_x - own_x) ** 2 + (rival_y - own_y) ** 2 + (rival_z - own_z) ** 2)
        min_range = min(min_range, current_range)
    cue = f("camera_cue_error_deg", row)
    if not math.isnan(cue):
        min_cue = min(min_cue, cue)
    bearing = f("bearing_error_deg", row)
    if not math.isnan(bearing):
        min_bearing = min(min_bearing, bearing)
    phase = (row.get("longitudinal_phase") or "").strip().lower()
    if phase and phase not in phases:
        phases.append(phase)
    range_text = row.get("range_3d_m", "")
    if not first_settle and phase == "settle":
        first_settle = range_text or "missing"
    if not first_follow_lock and phase == "follow_lock":
        first_follow_lock = range_text or "missing"
    if not first_follow_hold and phase == "follow_hold":
        first_follow_hold = range_text or "missing"

def fmt(value):
    if value in ("", None):
        return "missing"
    if isinstance(value, float):
        return "missing" if math.isinf(value) or math.isnan(value) else f"{value:.3f}"
    return str(value)

print(
    ",".join(
        [
            fmt(min_range),
            fmt(min_cue),
            fmt(min_bearing),
            "|".join(phases) if phases else "none",
            fmt(first_settle),
            fmt(first_follow_lock),
            fmt(first_follow_hold),
        ]
    )
)
PY
}

mkdir -p "${OUTPUT_DIR}"
SUMMARY_PATH="${OUTPUT_DIR}/summary.csv"
printf 'route_name,description,exit_code,summary,min_range_3d_m,min_cue_error_deg,min_bearing_error_deg,phases_seen,first_settle_range_m,first_follow_lock_range_m,first_follow_hold_range_m,csv_path,czml_path,log_path\n' >"${SUMMARY_PATH}"

echo "output_dir=${OUTPUT_DIR}"
echo "build_mode=${BUILD_MODE}"

for case_spec in "${ROUTE_CASES[@]}"; do
  IFS='|' read -r run_name route_spec route_description <<<"${case_spec}"
  run_dir="${OUTPUT_DIR}/${run_name}"
  log_path="${run_dir}/check.log"
  csv_path="${run_dir}/live-rival-geometry.csv"
  czml_path="${run_dir}/live-rival-geometry.czml"
  mkdir -p "${run_dir}"

  compose_down
  rm -f "${DEFAULT_CSV_PATH}" "${DEFAULT_CSV_PATH}.czml"

  {
    echo "run_name=${run_name}"
    echo "route_spec=${route_spec}"
    echo "route_description=${route_description}"
    echo "gui_mode=${GUI_MODE}"
    echo "build_mode=${BUILD_MODE}"
    echo
  } >"${log_path}"

  echo
  echo "=== ${run_name} ==="
  echo "route points=${route_spec}"

  set +e
  env \
    ICONOM_USE_GUI="${GUI_MODE}" \
    PX4_HEADLESS="${PX4_HEADLESS_VALUE}" \
    PHASE6_LIVE_RIVAL_ROUTE_POINTS="${route_spec}" \
    "${CHECK_SCRIPT}" "${BUILD_MODE}" >>"${log_path}" 2>&1
  exit_code=$?
  set -e

  if [[ -f "${DEFAULT_CSV_PATH}" ]]; then
    cp "${DEFAULT_CSV_PATH}" "${csv_path}"
    env python3 "${EXPORT_SCRIPT}" "${csv_path}" --output "${czml_path}" >>"${log_path}" 2>&1 || true
  fi

  summary="$(summarize_run_log "${log_path}")"
  metrics="$(summarize_csv "${csv_path}")"
  printf '%s,"%s",%s,"%s",%s,%s,%s,"%s"\n' \
    "${run_name}" \
    "${route_description}" \
    "${exit_code}" \
    "${summary}" \
    "${metrics}" \
    "${csv_path}" \
    "${czml_path}" \
    "${log_path}" >>"${SUMMARY_PATH}"

  compose_down
  sleep 5
  echo "run=${run_name} exit_code=${exit_code} summary=${summary}"
done

echo
echo "phase-6 live-rival route batch complete"
echo "summary_path=${SUMMARY_PATH}"
echo "artifact directory: ${OUTPUT_DIR}"
