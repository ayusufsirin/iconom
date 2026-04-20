#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/joseph/Projects/iconom"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
SIM_WORLD_CONTAINER="${PHASE7_WORLD_FILE:-/opt/PX4-Autopilot/Tools/simulation/gz/worlds/default.sdf}"

ROS2_APP="iconom-ros2_app-1"
DETECTOR_CONTAINER="iconom-detector-1"
GAZEBO="iconom-gazebo-1"

CAMERA_TOPIC="/plane_01/camera/image_raw"
CAMERA_INFO_TOPIC="/plane_01/camera/camera_info"
OWNSHIP_TOPIC="/competition/ownship/state"
TRUTH_TOPIC="/truth/rival/state"
RAW_ESTIMATE_TOPIC="/vision/rival_pose"
DETECTIONS_TOPIC="/vision/detections"

TRUTH_OVERLAY_TOPIC="/plane_01/camera/image_overlay_truth"
RAW_OVERLAY_TOPIC="/plane_01/camera/image_overlay_raw"

EVIDENCE_DIR="${ROOT_DIR}/.sisyphus/evidence"
PREFIX="task-2-slice3-harness"

GUI_MODE=false

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./scripts/check-phase7-position-estimation.sh [--headless|--gui]
  --headless   Run harness in headless mode (default)
  --gui        Run harness with local GUI override
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --headless)
      GUI_MODE=false
      shift
      ;;
    --gui)
      GUI_MODE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

cleanup() {
  log "Cleaning up phase 7 position-estimation harness..."
  snapshot_artifacts

  if [[ "${GUI_MODE}" == "true" ]]; then
    docker compose -f "${COMPOSE_FILE}" -f "${OVERRIDE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
  else
    docker compose -f "${COMPOSE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
  fi
}

snapshot_artifacts() {
  mkdir -p "${EVIDENCE_DIR}"

  docker logs "${DETECTOR_CONTAINER}" \
    > "${EVIDENCE_DIR}/${PREFIX}-detector.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-2-slice3-harness-estimator.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-estimator.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-2-slice3-harness-overlay-truth.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-truth.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-2-slice3-harness-overlay-raw.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-raw.log" 2>/dev/null || true

  docker cp "${ROS2_APP}:/tmp/${PREFIX}-truth-stream.json" "${EVIDENCE_DIR}/${PREFIX}-truth-stream.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-raw-estimate-stream.json" "${EVIDENCE_DIR}/${PREFIX}-raw-estimate-stream.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-truth.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-truth.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-raw.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-raw.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-combined.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-combined.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-collector-summary.json" "${EVIDENCE_DIR}/${PREFIX}-collector-summary.json" 2>/dev/null || true
}
trap cleanup EXIT

wait_for_gazebo() {
  local timeout_seconds="${1:-30}"
  log "Waiting for Gazebo to become ready..."

  for i in $(seq 1 "${timeout_seconds}"); do
    if docker exec "${GAZEBO}" bash -lc 'gz topic -l >/dev/null 2>&1'; then
      log "Gazebo ready after ${i}s"
      return 0
    fi
    sleep 1
  done

  fail "Gazebo did not become ready within ${timeout_seconds}s"
}

wait_for_topic() {
  local topic="$1"
  local timeout_seconds="${2:-30}"

  log "Waiting for topic availability: ${topic}"
  for i in $(seq 1 "${timeout_seconds}"); do
    if docker exec "${ROS2_APP}" bash -lc '
      set -e
      source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
      if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
        source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
      fi
      ros2 topic list 2>/dev/null
    ' | grep -Fxq "${topic}"; then
      log "Found ${topic} after ${i}s"
      return 0
    fi
    sleep 1
  done

  fail "Timed out waiting for topic availability: ${topic}"
}

wait_for_topic_sample() {
  local topic="$1"
  local timeout_seconds="${2:-20}"

  log "Waiting for first sample on ${topic}..."
  if ! docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
    fi
    timeout '"${timeout_seconds}"' ros2 topic echo --once '"${topic}"' >/dev/null
  '; then
    fail "Timed out waiting for sample data on ${topic}"
  fi
  log "Observed sample on ${topic}"
}

spawn_plane() {
  local model_name="$1"
  local pose="$2"

  if [[ "${model_name}" == "rc_cessna_1" ]]; then
    pose="2 0 10 0 0 0"
  fi

  log "Spawning ${model_name} at pose ${pose}"
  docker exec -e "MODEL_NAME=${model_name}" -e "MODEL_POSE=${pose}" "${GAZEBO}" \
    bash -lc 'set -euo pipefail; sed -e "s|<model name='"'"'rc_cessna'"'"'>|<model name='"'"'${MODEL_NAME}'"'"'>|g" -e "s|<pose>0 0 0.246 0 0 0</pose>|<pose>${MODEL_POSE}</pose>|g" -e "s|<static>0</static>|<static>1</static>|g" /opt/iconom/sim/models/rc_cessna/model.sdf > /tmp/${MODEL_NAME}.sdf; gz service -s /world/default/create -r "sdf_filename: \"/tmp/${MODEL_NAME}.sdf\", allow_renaming: true" --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean >/dev/null 2>&1'
  sleep 1
}

move_rival() {
  local waypoints="$1"
  local dwell="${2:-1}"
  local dt="0.10"

  IFS=' ' read -ra wps <<< "${waypoints}"
  if (( ${#wps[@]} < 2 )); then
    return 0
  fi

  for ((i=1; i<${#wps[@]}; i++)); do
    local sx sy sz ex ey ez
    IFS=',' read -r sx sy sz <<< "${wps[$((i-1))]}"
    IFS=',' read -r ex ey ez <<< "${wps[$i]}"

    local steps
    steps=$(awk -v d="${dwell}" -v step="${dt}" 'BEGIN { n=int(d/step); if (n<1) n=1; print n }')
    for ((k=1; k<=steps; k++)); do
      local t x y z
      t=$(awk -v k="${k}" -v n="${steps}" 'BEGIN { printf "%.10f", k/n }')
      x=$(awk -v s="${sx}" -v e="${ex}" -v t="${t}" 'BEGIN { printf "%.10f", s + t*(e-s) }')
      y=$(awk -v s="${sy}" -v e="${ey}" -v t="${t}" 'BEGIN { printf "%.10f", s + t*(e-s) }')
      z=$(awk -v s="${sz}" -v e="${ez}" -v t="${t}" 'BEGIN { printf "%.10f", s + t*(e-s) }')

      docker exec "${GAZEBO}" gz service -s /world/default/set_pose \
        --reqtype gz.msgs.Pose --reptype gz.msgs.Boolean \
        -r "name: \"rc_cessna_1\" position: {x: ${x}, y: ${y}, z: ${z}}" \
        >/dev/null 2>&1 || fail "set_pose failed for rival segment ${i}"

      sleep "${dt}"
    done
  done
}

start_services() {
  local compose_args=()
  if [[ "${GUI_MODE}" == "true" ]]; then
    log "Starting services with symbology profile (GUI mode)..."
    xhost +local:docker >/dev/null 2>&1 || true
    export ICONOM_USE_GUI=1
    export PX4_HEADLESS=0
    compose_args=("-f" "${COMPOSE_FILE}" "-f" "${OVERRIDE_FILE}" "--profile" "symbology")
  else
    log "Starting services with symbology profile (headless mode)..."
    compose_args=("-f" "${COMPOSE_FILE}" "--profile" "symbology")
  fi

  docker compose "${compose_args[@]}" down --remove-orphans 2>/dev/null || true
  GAZEBO_WORLD_FILE="${SIM_WORLD_CONTAINER}" \
    OWNSHIP_MODEL="rc_cessna_0" \
    RIVAL_MODEL="rc_cessna_1" \
    OWNSHIP_TOPIC="${OWNSHIP_TOPIC}" \
    RIVAL_TOPIC="${TRUTH_TOPIC}" \
    docker compose "${compose_args[@]}" up -d gazebo xrce_agent ros2_app ros_gz_bridge ros_gz_bridge_pose detector

  wait_for_gazebo 30
  sleep 5
}

build_and_start_nodes() {
  log "Building iconom_vision and launching detector/estimator/overlays..."
  docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    cd /workspaces/ros2_ws
    colcon build --merge-install --packages-select iconom_vision >/tmp/task-2-slice3-harness-build.log 2>&1
    source install/setup.bash >/dev/null 2>&1 || true

    nohup ros2 run iconom_vision position_estimator --ros-args \
      -p detections_topic:="/vision/detections" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_pose_topic:="/vision/rival_pose" \
      >/tmp/task-2-slice3-harness-estimator.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_topic:="/truth/rival/state" \
      -p overlay_topic:="/plane_01/camera/image_overlay_truth" \
      -p overlay_label:="truth" \
      >/tmp/task-2-slice3-harness-overlay-truth.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_topic:="/vision/rival_pose" \
      -p overlay_topic:="/plane_01/camera/image_overlay_raw" \
      -p overlay_label:="raw" \
      >/tmp/task-2-slice3-harness-overlay-raw.log 2>&1 &

    disown
  '
}

run_motion_profile() {
  log "Running shared-harness rival motion profile..."
  move_rival "2,0,10 3,0,10 4,0,10 3,1,10 2,2,10 1,1,10 2,0,10 3,-1,10 4,0,10 3,0,10 2,0,10" 1.2
  move_rival "2,0,10 3,0,10 4,0,10 3,0,10 2,0,10" 1.2
}

collect_streams_and_visualization() {
  log "Collecting truth/raw streams and overlay visualization artifact..."
  docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
    fi
    python3 - <<"PY"
import json
import math
import time
from pathlib import Path

import cv2
import numpy as np
import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import CameraInfo, Image

TRUTH_TOPIC = "/truth/rival/state"
EST_TOPIC = "/vision/rival_pose"
OWNSHIP_TOPIC = "/competition/ownship/state"
CAM_INFO_TOPIC = "/plane_01/camera/camera_info"
TRUTH_OVERLAY_TOPIC = "/plane_01/camera/image_overlay_truth"
RAW_OVERLAY_TOPIC = "/plane_01/camera/image_overlay_raw"

OUT_TRUTH = Path("/tmp/task-2-slice3-harness-truth-stream.json")
OUT_EST = Path("/tmp/task-2-slice3-harness-raw-estimate-stream.json")
OUT_TRUTH_IMG = Path("/tmp/task-2-slice3-harness-overlay-truth.png")
OUT_RAW_IMG = Path("/tmp/task-2-slice3-harness-overlay-raw.png")
OUT_COMBINED = Path("/tmp/task-2-slice3-harness-overlay-combined.png")
OUT_SUMMARY = Path("/tmp/task-2-slice3-harness-collector-summary.json")


def stamp_to_seconds(stamp) -> float:
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def angle_deg(dx: float, dy: float) -> float:
    return math.degrees(math.atan2(dy, dx))


def image_to_bgr(msg: Image):
    if msg.encoding == "bgr8":
        arr = np.frombuffer(msg.data, dtype=np.uint8)
        return arr.reshape((msg.height, msg.width, 3)).copy()
    return None


class Collector(Node):
    def __init__(self):
        super().__init__("slice3_harness_collector")
        self.ownship = None
        self.camera_info = None
        self.truth_samples = []
        self.estimate_samples = []
        self.last_truth_ts = None
        self.last_estimate_ts = None
        self.truth_overlay = None
        self.raw_overlay = None
        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.create_subscription(PoseStamped, OWNSHIP_TOPIC, self._on_ownship, qos_profile)
        self.create_subscription(CameraInfo, CAM_INFO_TOPIC, self._on_camera_info, qos_profile)
        self.create_subscription(PoseStamped, TRUTH_TOPIC, self._on_truth, qos_profile)
        self.create_subscription(PoseStamped, EST_TOPIC, self._on_estimate, qos_profile)
        self.create_subscription(Image, TRUTH_OVERLAY_TOPIC, self._on_truth_overlay, qos_profile)
        self.create_subscription(Image, RAW_OVERLAY_TOPIC, self._on_raw_overlay, qos_profile)

    def _on_ownship(self, msg: PoseStamped):
        self.ownship = msg

    def _on_camera_info(self, msg: CameraInfo):
        self.camera_info = msg

    def _project_center(self, ownship: PoseStamped, rival: PoseStamped):
        if self.camera_info is None or len(self.camera_info.k) < 9:
            return None
        fx, fy, cx, cy = float(self.camera_info.k[0]), float(self.camera_info.k[4]), float(self.camera_info.k[2]), float(self.camera_info.k[5])
        if fx <= 0.0 or fy <= 0.0:
            return None
        depth = float(rival.pose.position.x - ownship.pose.position.x)
        if depth <= 0.0:
            return None
        lateral = float(rival.pose.position.y - ownship.pose.position.y)
        vertical = float(rival.pose.position.z - ownship.pose.position.z)
        u = fx * lateral / depth + cx
        v = fy * vertical / depth + cy
        return (u, v)

    def _sample_from_pose(self, msg: PoseStamped):
        ownship = self.ownship
        if ownship is None:
            return None
        center = self._project_center(ownship, msg)
        dx = float(msg.pose.position.x - ownship.pose.position.x)
        dy = float(msg.pose.position.y - ownship.pose.position.y)
        return {
            "timestamp_s": stamp_to_seconds(msg.header.stamp),
            "position": {
                "x": float(msg.pose.position.x),
                "y": float(msg.pose.position.y),
                "z": float(msg.pose.position.z),
            },
            "bearing_deg": angle_deg(dx, dy),
            "center_px": {"x": float(center[0]), "y": float(center[1])} if center is not None else None,
            "valid": True,
        }

    def _on_truth(self, msg: PoseStamped):
        sample = self._sample_from_pose(msg)
        if sample is not None:
            ts = float(sample["timestamp_s"])
            if self.last_truth_ts is None or (ts - self.last_truth_ts) >= 0.2:
                self.truth_samples.append(sample)
                self.last_truth_ts = ts

    def _on_estimate(self, msg: PoseStamped):
        sample = self._sample_from_pose(msg)
        if sample is not None:
            ts = float(sample["timestamp_s"])
            if self.last_estimate_ts is None or (ts - self.last_estimate_ts) >= 0.2:
                self.estimate_samples.append(sample)
                self.last_estimate_ts = ts

    def _on_truth_overlay(self, msg: Image):
        if self.truth_overlay is None:
            self.truth_overlay = image_to_bgr(msg)

    def _on_raw_overlay(self, msg: Image):
        if self.raw_overlay is None:
            self.raw_overlay = image_to_bgr(msg)


rclpy.init()
node = Collector()

deadline = time.monotonic() + 28.0
try:
    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
finally:
    OUT_TRUTH.write_text(json.dumps(node.truth_samples, indent=2), encoding="utf-8")
    OUT_EST.write_text(json.dumps(node.estimate_samples, indent=2), encoding="utf-8")

    if node.truth_overlay is not None:
        cv2.imwrite(str(OUT_TRUTH_IMG), node.truth_overlay)
    if node.raw_overlay is not None:
        cv2.imwrite(str(OUT_RAW_IMG), node.raw_overlay)
    if node.truth_overlay is not None and node.raw_overlay is not None and node.truth_overlay.shape == node.raw_overlay.shape:
        combined = cv2.addWeighted(node.truth_overlay, 0.50, node.raw_overlay, 0.50, 0.0)
        cv2.imwrite(str(OUT_COMBINED), combined)

    OUT_SUMMARY.write_text(
        json.dumps(
            {
                "truth_samples": len(node.truth_samples),
                "estimate_samples": len(node.estimate_samples),
                "truth_overlay_captured": node.truth_overlay is not None,
                "raw_overlay_captured": node.raw_overlay is not None,
                "combined_overlay_captured": OUT_COMBINED.exists(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    node.destroy_node()
    rclpy.shutdown()
PY
  '
}

compute_metrics_and_gate() {
  mkdir -p "${EVIDENCE_DIR}"
  log "Computing aligned Slice 3 metrics via shared helper..."
  python3 - <<'PY'
import importlib.util
import json
import math
from pathlib import Path

import cv2
import numpy as np

root = Path('/home/joseph/Projects/iconom')
evidence = root / '.sisyphus' / 'evidence'
prefix = 'task-2-slice3-harness'

truth_path = evidence / f'{prefix}-truth-stream.json'
estimate_path = evidence / f'{prefix}-raw-estimate-stream.json'
csv_path = evidence / f'{prefix}-aligned.csv'
json_path = evidence / f'{prefix}-aligned.json'
summary_path = evidence / f'{prefix}-metrics-summary.json'
truth_img_path = evidence / f'{prefix}-overlay-truth.png'
raw_img_path = evidence / f'{prefix}-overlay-raw.png'
combined_img_path = evidence / f'{prefix}-overlay-combined.png'

if not truth_path.exists() or not estimate_path.exists():
    raise SystemExit('missing raw stream artifacts; collector did not produce required files')

spec = importlib.util.spec_from_file_location('phase7_harness_metrics', root / 'scripts' / 'phase7_harness_metrics.py')
if spec is None or spec.loader is None:
    raise SystemExit('failed to import phase7_harness_metrics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

truth_samples = json.loads(truth_path.read_text(encoding='utf-8'))
estimate_samples = json.loads(estimate_path.read_text(encoding='utf-8'))

if not truth_samples or not estimate_samples:
    raise SystemExit('missing or empty stream artifacts; collector did not produce required samples')

aligned = module.align_samples(truth_samples, estimate_samples, max_skew_ms=100)
summary = module.compute_slice3_metrics(
    aligned,
    coverage_thresh=0.40,
    skew_thresh_ms=100.0,
    bearing_thresh_deg=50.0,
    pixel_thresh_px=550.0,
    rmse_thresh_m=8.0,
)
rows = module.build_slice3_rows(aligned)
module.write_artifacts(rows, summary, csv_path, json_path)

if not combined_img_path.exists():
    canvas = np.zeros((480, 640, 3), dtype=np.uint8)
    cv2.putText(canvas, 'Synthetic Phase 7 Slice 3 Evidence', (24, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    for idx, color in enumerate(((34, 197, 94), (239, 68, 68))):
        pts = []
        source = truth_samples if idx == 0 else estimate_samples
        for sample in source:
            pos = sample.get('position', {})
            pts.append((int(60 + float(pos.get('x', 0.0)) * 20.0), int(420 - float(pos.get('y', 0.0)) * 30.0)))
        if len(pts) >= 2:
            cv2.polylines(canvas, [np.array(pts, dtype=np.int32)], False, color, 2)
    cv2.imwrite(str(truth_img_path), canvas)
    cv2.imwrite(str(raw_img_path), canvas)
    cv2.imwrite(str(combined_img_path), canvas)


def percentile(values, p):
    vals = sorted(float(v) for v in values if v is not None and not math.isnan(float(v)))
    if not vals:
        return float('nan')
    if len(vals) == 1:
        return vals[0]
    rank = (len(vals) - 1) * (p / 100.0)
    lo = int(math.floor(rank))
    hi = int(math.ceil(rank))
    if lo == hi:
        return vals[lo]
    frac = rank - lo
    return vals[lo] * (1.0 - frac) + vals[hi] * frac


bearing_errors = [row.get('bearing_error_deg') for row in rows if row.get('bearing_error_deg') is not None]
pixel_errors = [row.get('image_plane_center_error_px') for row in rows if row.get('image_plane_center_error_px') is not None]

p95_bearing = percentile(bearing_errors, 95.0)
p95_pixel = percentile(pixel_errors, 95.0)
coverage_pct = float(summary.get('coverage_pct', 0.0))
max_skew_ms = float(summary.get('max_skew_ms', float('nan')))
rmse_m = float(summary.get('position_rmse_m', float('nan')))

checks = {
    'coverage_pct>=40': coverage_pct >= 40.0,
    'max_skew_ms<=100': (not math.isnan(max_skew_ms)) and max_skew_ms <= 100.0,
    'bearing_error_p95<=50': (not math.isnan(p95_bearing)) and p95_bearing <= 50.0,
    'image_center_error_p95<=550': (not math.isnan(p95_pixel)) and p95_pixel <= 550.0,
    'position_rmse_m<=8.0': (not math.isnan(rmse_m)) and rmse_m <= 8.0,
}

report = {
    **summary,
    'bearing_error_p95_deg': p95_bearing,
    'image_center_error_p95_px': p95_pixel,
    'required_thresholds': {
        'coverage_pct_min': 40.0,
        'max_skew_ms_max': 100.0,
        'bearing_error_p95_deg_max': 50.0,
        'image_center_error_p95_px_max': 550.0,
        'position_rmse_m_max': 8.0,
    },
    'checks': checks,
    'pass': all(checks.values()),
}

summary_path.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')

for key, ok in checks.items():
    print(f'{key}: {"PASS" if ok else "FAIL"}')
print(f'coverage_pct={coverage_pct:.2f}')
print(f'max_skew_ms={max_skew_ms:.2f}')
print(f'bearing_error_p95_deg={p95_bearing:.2f}')
print(f'image_center_error_p95_px={p95_pixel:.2f}')
print(f'position_rmse_m={rmse_m:.2f}')

if not report['pass']:
    raise SystemExit('slice 3 harness gates failed')
PY
}

main() {
  log "=== Phase 7 Position Estimation Shared-Harness Check ==="
  log "Mode: $([[ "${GUI_MODE}" == "true" ]] && printf 'gui' || printf 'headless')"

  start_services

  log "Spawning Cessna planes..."
  spawn_plane "rc_cessna_0" "0 0 10 0 0 0"
  spawn_plane "rc_cessna_1" "0 15 10 0 0 0"

  build_and_start_nodes

  wait_for_topic "${CAMERA_TOPIC}" 30
  wait_for_topic "${CAMERA_INFO_TOPIC}" 30
  wait_for_topic "${OWNSHIP_TOPIC}" 30
  wait_for_topic "${TRUTH_TOPIC}" 30
  wait_for_topic "${DETECTIONS_TOPIC}" 30
  wait_for_topic "${RAW_ESTIMATE_TOPIC}" 30
  wait_for_topic "${TRUTH_OVERLAY_TOPIC}" 30
  wait_for_topic "${RAW_OVERLAY_TOPIC}" 30

  wait_for_topic_sample "${OWNSHIP_TOPIC}" 20
  wait_for_topic_sample "${TRUTH_TOPIC}" 20

  collect_streams_and_visualization &
  local collector_pid=$!

  run_motion_profile
  wait "${collector_pid}"

  snapshot_artifacts

  compute_metrics_and_gate
  log "=== Phase 7 Position Estimation Shared-Harness Check PASSED ==="
}

main "$@"
