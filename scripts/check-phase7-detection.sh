#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/home/joseph/Projects/iconom"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
SIM_WORLD_CONTAINER="/opt/iconom/sim/worlds/symbology_test.sdf"

ROS2_APP="iconom-ros2_app-1"
CAMERA_TOPIC="/plane_01/camera/image_raw"
DETECTIONS_TOPIC="/vision/detections"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  log "Cleaning up phase 7 detection check..."
  capture_evidence
  docker compose -f "${COMPOSE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
}

capture_evidence() {
  local evidence_dir="${ROOT_DIR}/.sisyphus/evidence"
  mkdir -p "${evidence_dir}"

  # Capture detector log if it exists
  docker exec "${ROS2_APP}" bash -lc 'cat /tmp/aircraft_detector.log' > "${evidence_dir}/task-2-detector.log" 2>/dev/null || true

  docker exec "${ROS2_APP}" bash -lc 'python3 -c "import numpy; print(numpy.__version__)"' > "${evidence_dir}/task-2-numpy-version.txt" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash >/dev/null 2>&1; python3 -c "import cv_bridge; print(cv_bridge.__version__ if hasattr(cv_bridge, \"__version__\") else \"ok\")"' > "${evidence_dir}/task-2-cv-bridge-version.txt" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'python3 -c "import ultralytics; print(ultralytics.__version__)"' > "${evidence_dir}/task-2-ultralytics-version.txt" 2>/dev/null || true
  docker exec "${ROS2_APP}" bash -lc 'python3 -c "from ultralytics import YOLO; YOLO(\"/workspaces/yolov8n.pt\"); print(\"model load ok\")"' > "${evidence_dir}/task-2-yolo-load.txt" 2>/dev/null || true

  # Capture topic list
  docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; ros2 topic list' > "${evidence_dir}/task-2-topic-list.txt" 2>/dev/null || true

  # Capture /vision/detections topic info
  docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash >/dev/null 2>&1; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1; fi; ros2 topic info /vision/detections 2>&1' > "${evidence_dir}/task-2-detections-info.txt" 2>/dev/null || true

  log "Evidence captured to ${evidence_dir}/"
}

preflight_checks() {
  log "Running preflight checks inside ros2_app container..."

  local numpy_version numpy_major
  numpy_version=$(docker exec "${ROS2_APP}" bash -lc 'python3 -c "import numpy; print(numpy.__version__)"' 2>/dev/null) || {
    fail "PREFLIGHT FAILED: NumPy not importable inside ros2_app. Is the image rebuilt?"
  }
  numpy_major="${numpy_version%%.*}"
  log "Preflight: NumPy version ${numpy_version}"
  if [[ "${numpy_major}" != "1" ]]; then
    fail "PREFLIGHT FAILED: NumPy major version is not 1 (found: ${numpy_major})"
  fi

  if ! docker exec "${ROS2_APP}" bash -lc 'source /opt/ros/humble/setup.bash >/dev/null 2>&1; python3 -c "import cv_bridge; print(\"cv_bridge ok\")"' >/dev/null 2>&1; then
    fail "PREFLIGHT FAILED: cv_bridge not importable (check ROS environment)"
  fi
  log "Preflight: cv_bridge import OK"

  # Check ultralytics import
  if ! docker exec "${ROS2_APP}" bash -lc 'python3 -c "import ultralytics; print(ultralytics.__version__)"' >/dev/null 2>&1; then
    fail "PREFLIGHT FAILED: ultralytics not importable inside ros2_app. Is the image rebuilt?"
  fi
  log "Preflight: ultralytics import OK"

  # Check model file exists
  if ! docker exec "${ROS2_APP}" bash -lc 'test -s /workspaces/yolov8n.pt' >/dev/null 2>&1; then
    fail "PREFLIGHT FAILED: /workspaces/yolov8n.pt missing or empty. Is the image rebuilt?"
  fi
  log "Preflight: yolov8n.pt exists and non-zero"

  # Check model loads
  if ! docker exec "${ROS2_APP}" bash -lc "python3 -c \"from ultralytics import YOLO; YOLO('/workspaces/yolov8n.pt'); print('model load ok')\"" >/dev/null 2>&1; then
    fail "PREFLIGHT FAILED: YOLO cannot load /workspaces/yolov8n.pt"
  fi
  log "Preflight: YOLO model load OK"
}

trap cleanup EXIT

wait_for_gazebo() {
  local timeout_seconds="${1:-30}"

  log "Waiting for Gazebo to become ready..."
  for i in $(seq 1 "${timeout_seconds}"); do
    if docker exec iconom-gazebo-1 bash -lc 'gz topic -l >/dev/null 2>&1'; then
      log "Gazebo ready after ${i}s"
      return 0
    fi
    sleep 1
  done

  fail "Gazebo did not become ready within ${timeout_seconds}s"
}

spawn_plane() {
  local model_name="$1"
  local pose="$2"

  if [[ "${model_name}" == "rc_cessna_1" ]]; then
    pose="2 0 10 0 0 0"
  fi

  log "Spawning ${model_name} at pose ${pose}"
  docker exec -e "MODEL_NAME=${model_name}" -e "MODEL_POSE=${pose}" iconom-gazebo-1 \
    bash -lc 'set -euo pipefail; sed -e "s|<model name='"'"'rc_cessna'"'"'>|<model name='"'"'${MODEL_NAME}'"'"'>|g" -e "s|<pose>0 0 0.246 0 0 0</pose>|<pose>${MODEL_POSE}</pose>|g" -e "s|<static>0</static>|<static>1</static>|g" /opt/iconom/sim/models/rc_cessna/model.sdf > /tmp/${MODEL_NAME}.sdf; gz service -s /world/default/create -r "sdf_filename: \"/tmp/${MODEL_NAME}.sdf\", allow_renaming: true" --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean >/dev/null 2>&1'

  sleep 1
  log "${model_name} spawned"
}

start_services() {
  log "Starting required services with symbology profile..."
  docker compose -f "${COMPOSE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
  GAZEBO_WORLD_FILE="${SIM_WORLD_CONTAINER}" \
    docker compose -f "${COMPOSE_FILE}" --profile symbology up -d gazebo xrce_agent ros2_app ros_gz_bridge
  wait_for_gazebo 30
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

start_detector() {
  log "Building and launching aircraft detector..."
  docker exec "${ROS2_APP}" bash -lc '
    set -e
    source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true
    cd /workspaces/ros2_ws
    colcon build --merge-install --packages-select iconom_vision 2>&1 | tail -5
    source install/setup.bash >/dev/null 2>&1 || true
    nohup ros2 run iconom_vision aircraft_detector >/tmp/aircraft_detector.log 2>&1 &
    disown
  '
  log "Aircraft detector launched"
}

wait_for_detection_activity() {
  local timeout_seconds="${1:-10}"

  log "Waiting up to ${timeout_seconds}s for activity on ${DETECTIONS_TOPIC}..."
  for i in $(seq 1 "${timeout_seconds}"); do
    local pub_count
    pub_count=$(docker exec "${ROS2_APP}" bash -lc 'set -e; source /opt/ros/humble/setup.bash >/dev/null 2>&1 || true; if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1 || true; fi; ros2 topic info '"${DETECTIONS_TOPIC}"' 2>/dev/null' 2>&1 | grep -c "Publisher count:" || echo "0")
    if [[ "${pub_count}" -ge 1 ]]; then
      log "PASS: observed ${DETECTIONS_TOPIC} message activity after ${i}s (publisher count: ${pub_count})"
      return 0
    fi
    sleep 1
  done

  fail "No ${DETECTIONS_TOPIC} message observed within ${timeout_seconds}s"
}

main() {
  log "=== Phase 7 Detection Acceptance Check ==="
  start_services
  preflight_checks

  log "Spawning Cessna planes..."
  spawn_plane "rc_cessna_0" "0 0 10 0 0 0"
  spawn_plane "rc_cessna_1" "0 15 10 0 0 0"

  wait_for_topic "${CAMERA_TOPIC}" 30

  start_detector
  wait_for_topic "${DETECTIONS_TOPIC}" 10
  wait_for_detection_activity 10

  log "=== Phase 7 Detection Acceptance Check PASSED ==="
}

main "$@"
