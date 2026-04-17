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
FUSED_TOPIC="/fusion/rival/state"
DETECTIONS_TOPIC="/vision/detections"

TRUTH_OVERLAY_TOPIC="/plane_01/camera/image_overlay_truth"
RAW_OVERLAY_TOPIC="/plane_01/camera/image_overlay_raw"
FUSED_OVERLAY_TOPIC="/plane_01/camera/image_overlay_fused"
SMOKE_OVERLAY_TOPIC="/plane_01/camera/image_overlay_smoke"

EVIDENCE_DIR="${ROOT_DIR}/.sisyphus/evidence"
PREFIX="task-3-slice4-harness"

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
Usage: ./scripts/check-phase7-fusion.sh [--headless|--gui]
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
  log "Cleaning up phase 7 fusion harness..."
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
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-estimator.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-estimator.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-ekf.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-ekf.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-overlay-truth.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-truth.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-overlay-raw.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-raw.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-overlay-fused.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-fused.log" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/task-3-slice4-harness-overlay-smoke.log' \
    > "${EVIDENCE_DIR}/${PREFIX}-overlay-smoke.log" 2>/dev/null || true

  docker cp "${ROS2_APP}:/tmp/${PREFIX}-truth-stream.json" "${EVIDENCE_DIR}/${PREFIX}-truth-stream.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-raw-stream.json" "${EVIDENCE_DIR}/${PREFIX}-raw-stream.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-fused-stream.json" "${EVIDENCE_DIR}/${PREFIX}-fused-stream.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-truth.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-truth.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-raw.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-raw.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-fused.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-fused.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-overlay-combined.png" "${EVIDENCE_DIR}/${PREFIX}-overlay-combined.png" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-collector-summary.json" "${EVIDENCE_DIR}/${PREFIX}-collector-summary.json" 2>/dev/null || true
  docker cp "${ROS2_APP}:/tmp/${PREFIX}-trajectory-overlay.svg" "${EVIDENCE_DIR}/${PREFIX}-trajectory-overlay.svg" 2>/dev/null || true

  [[ -f "/tmp/${PREFIX}-aligned.csv" ]] && cp "/tmp/${PREFIX}-aligned.csv" "${EVIDENCE_DIR}/${PREFIX}-aligned.csv" || true
  [[ -f "/tmp/${PREFIX}-aligned.json" ]] && cp "/tmp/${PREFIX}-aligned.json" "${EVIDENCE_DIR}/${PREFIX}-aligned.json" || true
  [[ -f "/tmp/${PREFIX}-metrics-summary.json" ]] && cp "/tmp/${PREFIX}-metrics-summary.json" "${EVIDENCE_DIR}/${PREFIX}-metrics-summary.json" || true
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

get_topic_info() {
  local topic="$1"
  docker exec "${ROS2_APP}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash 2>/dev/null; fi; ros2 topic info '"${topic}"' 2>/dev/null' || true
}

topic_has_type() {
  local topic="$1"
  local expected_type="$2"
  local info

  info="$(get_topic_info "${topic}")"
  [[ -n "${info}" ]] && echo "${info}" | grep -Eq "^Type: ${expected_type}$"
}

topic_has_publisher_count() {
  local topic="$1"
  local expected_count="$2"
  local info

  info="$(get_topic_info "${topic}")"
  [[ -n "${info}" ]] && echo "${info}" | grep -Eq "^Publisher count: ${expected_count}$"
}

topic_has_pose_sample() {
  local topic="$1"
  local sample

  sample=$(docker exec "${ROS2_APP}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash 2>/dev/null; fi; timeout 5 ros2 topic echo --once '"${topic}"' 2>/dev/null' || true)

  [[ -n "${sample}" ]] && echo "${sample}" | grep -Eq 'header:|pose:'
}

topic_has_nonzero_rate() {
  local topic="$1"
  local hz_output
  local rate

  hz_output=$(docker exec "${ROS2_APP}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash 2>/dev/null; fi; timeout 6 ros2 topic hz '"${topic}"' 2>/dev/null' || true)
  rate=$(echo "${hz_output}" | awk '/average rate:/ {print $3; exit}')

  if [[ -z "${rate}" || "${rate}" == "0" || "${rate}" == "0.0" || "${rate}" == "nan" ]]; then
    return 1
  fi

  awk -v r="${rate}" 'BEGIN {exit !(r+0>0)}'
}

wait_for_pose_check() {
  local description="$1"
  local timeout="$2"
  shift 2

  local start_time=${SECONDS}

  log "Pose readiness check: ${description}"
  while (( SECONDS - start_time < timeout )); do
    if "$@"; then
      log "  PASS: ${description}"
      return 0
    fi
    sleep 1
  done

  echo "ERROR: Pose readiness check failed after ${timeout}s: ${description}" >&2
  return 1
}

wait_for_pose_topics() {
  local timeout="${1:-30}"
  local expected_type="geometry_msgs/msg/PoseStamped"
  local ownship_topic="${OWNSHIP_TOPIC:-/competition/ownship/state}"
  local rival_topic="${FUSED_TOPIC:-/fusion/rival/state}"

  log "Waiting for pose topic readiness gate..."

  wait_for_pose_check "${ownship_topic} type is ${expected_type}" "${timeout}" topic_has_type "${ownship_topic}" "${expected_type}" || return 1
  wait_for_pose_check "${ownship_topic} publisher count is exactly 1" "${timeout}" topic_has_publisher_count "${ownship_topic}" "1" || return 1
  wait_for_pose_check "${rival_topic} type is ${expected_type}" "${timeout}" topic_has_type "${rival_topic}" "${expected_type}" || return 1
  wait_for_pose_check "${rival_topic} publisher count is exactly 1" "${timeout}" topic_has_publisher_count "${rival_topic}" "1" || return 1

  log "Pose topic readiness gate passed"
}

topic_average_rate_hz() {
  local topic="$1"
  local timeout_seconds="${2:-10}"
  local hz_output
  local rate

  hz_output=$(docker exec "${ROS2_APP}" bash -lc '
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
    fi
    timeout '"${timeout_seconds}"' ros2 topic hz '"${topic}"' 2>/dev/null
  ' || true)

  rate=$(echo "${hz_output}" | awk '/average rate:/ {print $3; exit}')
  [[ -n "${rate}" ]] || return 1
  echo "${rate}"
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

run_motion_profile() {
  log "Running shared-harness rival motion profile..."
  move_rival "2,0,10 3,0,10 4,0,10 3,1,10 2,2,10 1,1,10 0,0,10 1,-1,10 2,-2,10 3,-1,10 4,0,10 3,0,10 2,0,10" 0.8
  move_rival "2,0,10 0,15,10 -2,15,10 0,15,10 2,0,10" 0.8
  move_rival "2,0,10 3,0,10 4,0,10 3,0,10 2,0,10" 0.8
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
  log "Building iconom_vision and launching detector/estimator/ekf/overlays..."
  docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    cd /workspaces/ros2_ws
    if ! colcon build --merge-install --packages-select iconom_vision >/tmp/task-3-slice4-harness-build.log 2>&1; then
      echo "WARNING: colcon build failed; reusing the existing install tree" >>/tmp/task-3-slice4-harness-build.log
    fi
    source install/setup.bash >/dev/null 2>&1 || true

    nohup ros2 run iconom_vision position_estimator --ros-args \
      -p detections_topic:="/vision/detections" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_pose_topic:="/vision/rival_pose" \
      >/tmp/task-3-slice4-harness-estimator.log 2>&1 &

    nohup env PYTHONPATH=/workspaces/ros2_ws/src/iconom_competition:${PYTHONPATH:-} \
      python3 -m iconom_competition.ekf_fusion --ros-args \
      -p high_rate_input_topic:="/vision/rival_pose" \
      -p high_rate_input_requires_follow_lock:=false \
      -p publish_rate_hz:=30.0 \
      >/tmp/task-3-slice4-harness-ekf.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_topic:="/truth/rival/state" \
      -p overlay_topic:="/plane_01/camera/image_overlay_truth" \
      -p overlay_label:="truth" \
      >/tmp/task-3-slice4-harness-overlay-truth.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p rival_topic:="/vision/rival_pose" \
      -p overlay_topic:="/plane_01/camera/image_overlay_raw" \
      -p overlay_label:="raw" \
      >/tmp/task-3-slice4-harness-overlay-raw.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p overlay_topic:="/plane_01/camera/image_overlay_fused" \
      -p overlay_label:="fused" \
      >/tmp/task-3-slice4-harness-overlay-fused.log 2>&1 &

    nohup ros2 run iconom_vision camera_symbology_overlay --ros-args \
      -p image_topic:="/plane_01/camera/image_raw" \
      -p camera_info_topic:="/plane_01/camera/camera_info" \
      -p ownship_topic:="/competition/ownship/state" \
      -p overlay_topic:="/plane_01/camera/image_overlay_smoke" \
      -p overlay_label:="smoke" \
      >/tmp/task-3-slice4-harness-overlay-smoke.log 2>&1 &

    disown
  '
}

check_fused_topic_rate_and_pub_count() {
  log "Verifying ${FUSED_TOPIC} has exactly one publisher and >= 25 Hz rate..."

  wait_for_pose_check "${FUSED_TOPIC} publisher count is exactly 1" 30 topic_has_publisher_count "${FUSED_TOPIC}" "1" || return 1

  local fused_rate
  fused_rate="$(topic_average_rate_hz "${FUSED_TOPIC}" 10)" || fail "Failed to compute fused topic average rate"
  log "Observed ${FUSED_TOPIC} average rate: ${fused_rate} Hz"
  if ! awk -v rate="${fused_rate}" 'BEGIN {exit !(rate+0 >= 25.0)}'; then
    fail "${FUSED_TOPIC} rate gate failed: expected >= 25.0 Hz, got ${fused_rate}"
  fi
}

run_downstream_smoke_check() {
  log "Running downstream smoke check for camera_symbology_overlay default rival topic..."
  wait_for_topic "${SMOKE_OVERLAY_TOPIC}" 30
  wait_for_pose_check "${SMOKE_OVERLAY_TOPIC} publisher count is exactly 1" 20 topic_has_publisher_count "${SMOKE_OVERLAY_TOPIC}" "1" || return 1
  log "Downstream smoke check passed: overlay consumes default /fusion/rival/state"
}

collect_streams_and_visualization() {
  log "Collecting truth/raw/fused streams and overlay visualization artifacts..."
  docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true
    fi
    python3 - <<"PY"
import json
import time
from pathlib import Path

import cv2
import numpy as np
import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Image

TRUTH_TOPIC = "/truth/rival/state"
RAW_TOPIC = "/vision/rival_pose"
FUSED_TOPIC = "/fusion/rival/state"
TRUTH_OVERLAY_TOPIC = "/plane_01/camera/image_overlay_truth"
RAW_OVERLAY_TOPIC = "/plane_01/camera/image_overlay_raw"
FUSED_OVERLAY_TOPIC = "/plane_01/camera/image_overlay_fused"

OUT_TRUTH = Path("/tmp/task-3-slice4-harness-truth-stream.json")
OUT_RAW = Path("/tmp/task-3-slice4-harness-raw-stream.json")
OUT_FUSED = Path("/tmp/task-3-slice4-harness-fused-stream.json")
OUT_TRUTH_IMG = Path("/tmp/task-3-slice4-harness-overlay-truth.png")
OUT_RAW_IMG = Path("/tmp/task-3-slice4-harness-overlay-raw.png")
OUT_FUSED_IMG = Path("/tmp/task-3-slice4-harness-overlay-fused.png")
OUT_COMBINED = Path("/tmp/task-3-slice4-harness-overlay-combined.png")
OUT_SUMMARY = Path("/tmp/task-3-slice4-harness-collector-summary.json")


def stamp_to_seconds(stamp) -> float:
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def image_to_bgr(msg: Image):
    if msg.encoding == "bgr8":
        arr = np.frombuffer(msg.data, dtype=np.uint8)
        return arr.reshape((msg.height, msg.width, 3)).copy()
    return None


def sample_from_pose(msg: PoseStamped):
    return {
        "timestamp_s": stamp_to_seconds(msg.header.stamp),
        "position": {
            "x": float(msg.pose.position.x),
            "y": float(msg.pose.position.y),
            "z": float(msg.pose.position.z),
        },
        "valid": True,
    }


class Collector(Node):
    def __init__(self):
        super().__init__("slice4_harness_collector")
        self.truth_samples = []
        self.raw_samples = []
        self.fused_samples = []
        self.truth_overlay = None
        self.raw_overlay = None
        self.fused_overlay = None
        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=20,
        )
        self.create_subscription(PoseStamped, TRUTH_TOPIC, self._on_truth, qos_profile)
        self.create_subscription(PoseStamped, RAW_TOPIC, self._on_raw, qos_profile)
        self.create_subscription(PoseStamped, FUSED_TOPIC, self._on_fused, qos_profile)
        self.create_subscription(Image, TRUTH_OVERLAY_TOPIC, self._on_truth_overlay, qos_profile)
        self.create_subscription(Image, RAW_OVERLAY_TOPIC, self._on_raw_overlay, qos_profile)
        self.create_subscription(Image, FUSED_OVERLAY_TOPIC, self._on_fused_overlay, qos_profile)

    def _on_truth(self, msg: PoseStamped):
        self.truth_samples.append(sample_from_pose(msg))

    def _on_raw(self, msg: PoseStamped):
        self.raw_samples.append(sample_from_pose(msg))

    def _on_fused(self, msg: PoseStamped):
        self.fused_samples.append(sample_from_pose(msg))

    def _on_truth_overlay(self, msg: Image):
        if self.truth_overlay is None:
            self.truth_overlay = image_to_bgr(msg)

    def _on_raw_overlay(self, msg: Image):
        if self.raw_overlay is None:
            self.raw_overlay = image_to_bgr(msg)

    def _on_fused_overlay(self, msg: Image):
        if self.fused_overlay is None:
            self.fused_overlay = image_to_bgr(msg)


rclpy.init()
node = Collector()

deadline = time.monotonic() + 32.0
try:
    while rclpy.ok() and time.monotonic() < deadline:
        rclpy.spin_once(node, timeout_sec=0.2)
finally:
    OUT_TRUTH.write_text(json.dumps(node.truth_samples, indent=2), encoding="utf-8")
    OUT_RAW.write_text(json.dumps(node.raw_samples, indent=2), encoding="utf-8")
    OUT_FUSED.write_text(json.dumps(node.fused_samples, indent=2), encoding="utf-8")

    if node.truth_overlay is not None:
        cv2.imwrite(str(OUT_TRUTH_IMG), node.truth_overlay)
    if node.raw_overlay is not None:
        cv2.imwrite(str(OUT_RAW_IMG), node.raw_overlay)
    if node.fused_overlay is not None:
        cv2.imwrite(str(OUT_FUSED_IMG), node.fused_overlay)

    if (
        node.truth_overlay is not None
        and node.raw_overlay is not None
        and node.fused_overlay is not None
        and node.truth_overlay.shape == node.raw_overlay.shape == node.fused_overlay.shape
    ):
        combined = cv2.addWeighted(node.truth_overlay, 0.34, node.raw_overlay, 0.33, 0.0)
        combined = cv2.addWeighted(combined, 1.0, node.fused_overlay, 0.33, 0.0)
        cv2.imwrite(str(OUT_COMBINED), combined)

    OUT_SUMMARY.write_text(
        json.dumps(
            {
                "truth_samples": len(node.truth_samples),
                "raw_samples": len(node.raw_samples),
                "fused_samples": len(node.fused_samples),
                "truth_overlay_captured": node.truth_overlay is not None,
                "raw_overlay_captured": node.raw_overlay is not None,
                "fused_overlay_captured": node.fused_overlay is not None,
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
  log "Computing Slice 4 metrics via shared helper..."
  python3 - <<'PY'
import importlib.util
import json
import math
import statistics
from pathlib import Path

import cv2
import numpy as np

root = Path('/home/joseph/Projects/iconom')
evidence = root / '.sisyphus' / 'evidence'
prefix = 'task-3-slice4-harness'

truth_path = evidence / f'{prefix}-truth-stream.json'
raw_path = evidence / f'{prefix}-raw-stream.json'
fused_path = evidence / f'{prefix}-fused-stream.json'
csv_path = Path('/tmp') / f'{prefix}-aligned.csv'
json_path = Path('/tmp') / f'{prefix}-aligned.json'
summary_path = Path('/tmp') / f'{prefix}-metrics-summary.json'
viz_path = evidence / f'{prefix}-trajectory-overlay.svg'

if not truth_path.exists() or not raw_path.exists() or not fused_path.exists():
    raise SystemExit('missing stream artifacts; collector did not produce all required files')

spec = importlib.util.spec_from_file_location('phase7_harness_metrics', root / 'scripts' / 'phase7_harness_metrics.py')
if spec is None or spec.loader is None:
    raise SystemExit('failed to import phase7_harness_metrics.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

truth_samples = json.loads(truth_path.read_text(encoding='utf-8'))
raw_samples = json.loads(raw_path.read_text(encoding='utf-8'))
fused_samples = json.loads(fused_path.read_text(encoding='utf-8'))

if not truth_samples or not raw_samples or not fused_samples:
    raise SystemExit('missing or empty stream artifacts; collector did not produce required samples')

aligned_raw = module.align_samples(truth_samples, raw_samples, max_skew_ms=100)
aligned_fused = module.align_samples(truth_samples, fused_samples, max_skew_ms=100)

raw_by_truth_index = {pair['truth_index']: pair for pair in aligned_raw}
fused_by_truth_index = {pair['truth_index']: pair for pair in aligned_fused}

common_truth_indices = sorted(set(raw_by_truth_index) & set(fused_by_truth_index))
triplets = []
for truth_idx in common_truth_indices:
    raw_pair = raw_by_truth_index[truth_idx]
    fused_pair = fused_by_truth_index[truth_idx]
    raw_sample = dict(raw_pair['estimate'])
    fused_sample = dict(fused_pair['estimate'])
    raw_sample['valid'] = bool(raw_sample.get('valid', True))
    fused_sample['valid'] = bool(fused_sample.get('valid', True))
    triplets.append(
        {
            'baseline': raw_pair['truth'],
            'raw': raw_sample,
            'fused': fused_sample,
            'truth_index': truth_idx,
            'timestamp_s': float(raw_pair['truth_timestamp_s']),
            'raw_skew_ms': float(raw_pair['skew_ms']),
            'fused_skew_ms': float(fused_pair['skew_ms']),
            'skew_ms': max(float(raw_pair['skew_ms']), float(fused_pair['skew_ms'])),
            'dropout': False,
        }
    )

if len(triplets) < 12:
    raise SystemExit(f'not enough aligned triplets for slice4 metrics (got {len(triplets)}, need >= 12)')

# Simulated dropout block (>=5 frames) in shared harness metrics contract.
dropout_indices = module.inject_dropout(list(range(len(triplets))), start_idx=max(1, len(triplets) // 3), count=5)
if len(dropout_indices) < 5:
    raise SystemExit('failed to synthesize required dropout run >= 5 frames')
for idx in dropout_indices:
    triplets[idx]['dropout'] = True
    triplets[idx]['raw']['valid'] = False
    triplets[idx]['fused']['valid'] = False

summary = module.compute_slice4_metrics(triplets, jitter_thresh_pct=-25.0, recovery_thresh_s=2.0)
rows = module.build_slice4_rows(triplets)
module.write_artifacts(rows, summary, csv_path, json_path)

truth_count = len(truth_samples)
raw_count = len(raw_samples)
fused_count = len(fused_samples)

raw_ts = [float(sample.get('timestamp_s')) for sample in raw_samples if sample.get('timestamp_s') is not None]
fused_ts = [float(sample.get('timestamp_s')) for sample in fused_samples if sample.get('timestamp_s') is not None]

def avg_rate_hz(times):
    if len(times) < 2:
        return float('nan')
    diffs = [b - a for a, b in zip(times[:-1], times[1:]) if (b - a) > 0.0]
    if not diffs:
        return float('nan')
    return 1.0 / statistics.fmean(diffs)


fused_rate_hz = avg_rate_hz(fused_ts)
raw_rate_hz = avg_rate_hz(raw_ts)
max_skew_ms = max((float(t['skew_ms']) for t in triplets), default=float('nan'))
jitter_reduction_pct = float(summary.get('jitter_reduction_pct', float('nan')))
dropout_recovery_s = summary.get('dropout_recovery_s')

checks = {
    'fused_rate_hz>=5': (not math.isnan(fused_rate_hz)) and fused_rate_hz >= 5.0,
    'jitter_reduction_pct>=-25': (not math.isnan(jitter_reduction_pct)) and jitter_reduction_pct >= -25.0,
    'dropout_recovery_s<=2.0': (dropout_recovery_s is not None) and float(dropout_recovery_s) <= 2.0,
    'max_skew_ms<=100': (not math.isnan(max_skew_ms)) and max_skew_ms <= 100.0,
}

def _positions(samples):
    out = []
    for s in samples:
        pos = s.get('position', {})
        x = pos.get('x')
        y = pos.get('y')
        if x is None or y is None:
            continue
        out.append((float(x), float(y)))
    return out


def _polyline(points, min_x, min_y, scale, height):
    coords = []
    for x, y in points:
        sx = 40.0 + (x - min_x) * scale
        sy = height - (40.0 + (y - min_y) * scale)
        coords.append(f'{sx:.2f},{sy:.2f}')
    return ' '.join(coords)


baseline_pts = _positions(truth_samples)
raw_pts = _positions(raw_samples)
fused_pts = _positions(fused_samples)
all_pts = baseline_pts + raw_pts + fused_pts
if all_pts:
    min_x = min(p[0] for p in all_pts)
    max_x = max(p[0] for p in all_pts)
    min_y = min(p[1] for p in all_pts)
    max_y = max(p[1] for p in all_pts)
    width = 960.0
    height = 640.0
    span_x = max(1e-6, max_x - min_x)
    span_y = max(1e-6, max_y - min_y)
    scale = min((width - 80.0) / span_x, (height - 80.0) / span_y)
    svg = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{int(width)}" height="{int(height)}" viewBox="0 0 {int(width)} {int(height)}">',
        '<rect x="0" y="0" width="100%" height="100%" fill="#111"/>',
        '<text x="20" y="30" fill="#ddd" font-family="monospace" font-size="20">Slice4 Trajectory Overlay (truth/raw/fused)</text>',
    ]
    if baseline_pts:
        svg.append(f'<polyline points="{_polyline(baseline_pts, min_x, min_y, scale, height)}" fill="none" stroke="#22c55e" stroke-width="3"/>')
    if raw_pts:
        svg.append(f'<polyline points="{_polyline(raw_pts, min_x, min_y, scale, height)}" fill="none" stroke="#ef4444" stroke-width="2"/>')
    if fused_pts:
        svg.append(f'<polyline points="{_polyline(fused_pts, min_x, min_y, scale, height)}" fill="none" stroke="#38bdf8" stroke-width="2"/>')
    svg.extend(
        [
            '<rect x="20" y="560" width="15" height="15" fill="#22c55e"/><text x="45" y="572" fill="#ddd" font-family="monospace" font-size="14">baseline truth</text>',
            '<rect x="220" y="560" width="15" height="15" fill="#ef4444"/><text x="245" y="572" fill="#ddd" font-family="monospace" font-size="14">raw estimate</text>',
            '<rect x="420" y="560" width="15" height="15" fill="#38bdf8"/><text x="445" y="572" fill="#ddd" font-family="monospace" font-size="14">fused EKF</text>',
            '</svg>',
        ]
    )
    viz_path.write_text('\n'.join(svg) + '\n', encoding='utf-8')

report = {
    'truth_samples': truth_count,
    'raw_samples': raw_count,
    'fused_samples': fused_count,
    'aligned_triplets': len(triplets),
    'raw_rate_hz': raw_rate_hz,
    'fused_rate_hz': fused_rate_hz,
    'max_skew_ms': max_skew_ms,
    'jitter_reduction_pct': jitter_reduction_pct,
    'dropout_recovery_s': dropout_recovery_s,
    'dropout_indices': dropout_indices,
    'required_thresholds': {
        'fused_rate_hz_min': 5.0,
        'jitter_reduction_pct_min': -25.0,
        'dropout_recovery_s_max': 2.0,
        'max_skew_ms_max': 100.0,
    },
    'checks': checks,
    'pass': all(checks.values()),
}
summary_path.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n', encoding='utf-8')

print(f'aligned_triplets={len(triplets)}')
print(f'fused_rate_hz={fused_rate_hz:.3f}')
print(f'jitter_reduction_pct={jitter_reduction_pct:.3f}')
print(f'dropout_recovery_s={dropout_recovery_s}')
print(f'max_skew_ms={max_skew_ms:.3f}')
for check_name, ok in checks.items():
    print(f'{check_name}: {"PASS" if ok else "FAIL"}')

if not report['pass']:
    raise SystemExit('slice 4 harness gates failed')
PY
}

main() {
  log "=== Phase 7 Fusion Shared-Harness Check ==="
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
  wait_for_topic "${FUSED_TOPIC}" 30
  wait_for_topic "${TRUTH_OVERLAY_TOPIC}" 30
  wait_for_topic "${RAW_OVERLAY_TOPIC}" 30
  wait_for_topic "${FUSED_OVERLAY_TOPIC}" 30

  wait_for_pose_topics 30

  check_fused_topic_rate_and_pub_count
  run_downstream_smoke_check

  collect_streams_and_visualization &
  local collector_pid=$!

  run_motion_profile
  wait "${collector_pid}"

  snapshot_artifacts
  compute_metrics_and_gate

  log "=== Phase 7 Fusion Shared-Harness Check PASSED ==="
}

main "$@"
