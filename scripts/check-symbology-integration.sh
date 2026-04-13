#!/usr/bin/env bash
# Symbology integration test - spawns planes directly in Gazebo without PX4
set -euo pipefail

ROOT_DIR="/home/joseph/Projects/iconom"
ENV_FILE="${ROOT_DIR}/.env.example"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"
OVERRIDE_FILE="${ROOT_DIR}/docker-compose.override.yml"
SIM_WORLD_LOCAL="${ROOT_DIR}/sim/worlds/symbology_test.sdf"
SIM_WORLD_CONTAINER="/opt/iconom/sim/worlds/symbology_test.sdf"

GUI_MODE=false
COLD_BUILD=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gui)
      GUI_MODE=true
      shift
      ;;
    --cold)
      COLD_BUILD=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--gui] [--cold]"
      echo "  --gui    Enable GUI mode with X11 display"
      echo "  --cold   Force clean rebuild of ROS workspace"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "=== Symbology Integration Test (No-PX4 Mode) ==="
echo "  GUI_MODE: ${GUI_MODE}"
echo "  COLD_BUILD: ${COLD_BUILD}"

cleanup() {
  echo "Cleaning up..."
  docker exec iconom-gazebo-1 bash -lc '
    gz model -m rc_cessna_0 -r 2>/dev/null || true
    gz model -m rc_cessna_1 -r 2>/dev/null || true
  ' 2>/dev/null || true
  
  if [[ -f "${COMPOSE_FILE}" ]]; then
    if [[ "${GUI_MODE}" == "true" ]]; then
      docker compose -f "${COMPOSE_FILE}" -f "${OVERRIDE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
    else
      docker compose -f "${COMPOSE_FILE}" --profile symbology down --remove-orphans 2>/dev/null || true
    fi
  fi
}
trap cleanup EXIT

wait_for_gazebo() {
  local timeout="${1:-60}"
  for i in $(seq 1 "${timeout}"); do
    if docker exec iconom-gazebo-1 bash -lc 'gz topic -l | head -1' &>/dev/null; then
      echo "Gazebo ready at attempt ${i}"
      return 0
    fi
    sleep 1
  done
  echo "ERROR: Gazebo did not become ready" >&2
  return 1
}

spawn_plane() {
  local model_name="$1"
  local pose="$2"
  
  # Rival starts 2m in front of ownship (X=2, camera looks in +X direction)
  if [[ "${model_name}" == "rc_cessna_1" ]]; then
    pose="2 0 10 0 0 0"
  fi

  echo "Spawning ${model_name} with Cessna model at pose ${pose}"
  
  # Create SDF with renamed model, pose, and static=1
  # Pass variables through environment to avoid quoting issues
  docker exec -e "MODEL_NAME=${model_name}" -e "MODEL_POSE=${pose}" iconom-gazebo-1 \
    bash -c 'sed -e "s|<model name='"'"'rc_cessna'"'"'>|<model name='"'"'${MODEL_NAME}'"'"'>|g" \
               -e "s|<pose>0 0 0.246 0 0 0</pose>|<pose>${MODEL_POSE}</pose>|g" \
               -e "s|<static>0</static>|<static>1</static>|g" \
               /opt/iconom/sim/models/rc_cessna/model.sdf \
               > /tmp/${MODEL_NAME}.sdf'
  
  # Spawn using gz service
  docker exec iconom-gazebo-1 gz service -s /world/default/create \
    -r "sdf_filename: \"/tmp/${model_name}.sdf\", allow_renaming: true" \
    --reqtype gz.msgs.EntityFactory --reptype gz.msgs.Boolean > /dev/null 2>&1
  sleep 1
  echo "${model_name} spawned"
}

move_rival() {
  local model_name="${1:-rc_cessna_1}"
  local waypoints="$2"
  local dwell="${3:-2}"
  
  echo "Moving ${model_name} through waypoints: ${waypoints}"
  IFS=' ' read -ra WPS <<< "${waypoints}"
  for wp in "${WPS[@]}"; do
    echo "  -> ${wp}"
    docker exec iconom-gazebo-1 bash -lc "
      IFS=',' read -r x y z r p yaw <<< '${wp}'
      gz service -s /world/default/set_pose --reqtype gz.msgs.Pose --reptype gz.msgs.Boolean -r \"name: \\\"${model_name}\\\" position: {x: \${x}, y: \${y}, z: \${z}}\"
    " 2>/dev/null || true
    sleep "${dwell}"
  done
}

start_services() {
  local profile_args=()
  
  if [[ "${GUI_MODE}" == "true" ]]; then
    echo "Starting services in GUI mode..."
    xhost +local:docker 2>/dev/null || true
    profile_args=("-f" "${COMPOSE_FILE}" "-f" "${OVERRIDE_FILE}" "--profile" "symbology")
    export ICONOM_USE_GUI=1
    export PX4_HEADLESS=0
  else
    echo "Starting services in headless mode..."
    profile_args=("-f" "${COMPOSE_FILE}" "--profile" "symbology")
  fi
  
  echo "Starting gazebo..."
  GAZEBO_WORLD_FILE="${SIM_WORLD_CONTAINER}" docker compose "${profile_args[@]}" up -d gazebo
  wait_for_gazebo 30
  
  echo "Starting ros2_app..."
  docker compose "${profile_args[@]}" up -d ros2_app
  
  echo "Starting ros_gz_bridge..."
  docker compose "${profile_args[@]}" up -d ros_gz_bridge ros_gz_bridge_plane_02 ros_gz_bridge_pose
  
  echo "Starting web services (rosbridge + camera_web)..."
  docker compose "${profile_args[@]}" up -d rosbridge camera_web
  
  sleep 5
  echo "Services started"
  echo ""
  echo "=== Web Access ==="
  echo "View camera overlay in browser:"
  echo "  http://localhost:8766/docs/phase6-camera-viewer.html"
  echo ""
  echo "In the viewer:"
  echo "  Topic: /plane_01/camera/image_overlay"
  echo "  Click: Connect"
}

wait_for_camera_topics() {
  local ros2_app="iconom-ros2_app-1"
  local timeout="${1:-60}"
  
  echo "Waiting for camera topics..."
  for i in $(seq 1 "${timeout}"); do
    TOPICS=$(docker exec "${ros2_app}" bash -lc 'source /opt/ros/humble/setup.bash 2>/dev/null; ros2 topic list 2>/dev/null' || echo "")
    
    if echo "${TOPICS}" | grep -q "/plane_01/camera/image_raw" && \
       echo "${TOPICS}" | grep -q "/plane_02/camera/image_raw"; then
      echo "Camera topics found at attempt ${i}"
      return 0
    fi
    sleep 1
  done
  echo "WARNING: Camera topics not found"
  return 1
}

verify_topic_data() {
  local ros2_app="iconom-ros2_app-1"
  local topic="/plane_01/camera/image_raw"
  local timeout="${1:-30}"
  
  echo "Verifying ${topic} has data..."
  for i in $(seq 1 "${timeout}"); do
    HZ=$(docker exec "${ros2_app}" bash -lc \
      'source /opt/ros/humble/setup.bash 2>/dev/null; timeout 3 ros2 topic hz '"${topic}"' 2>&1' | \
      grep "average rate:" | awk '{print $3}' || echo "0")
    
    if [[ -n "${HZ}" && "${HZ}" != "0" && "${HZ}" != "nan" ]]; then
      echo "${topic} publishing at ${HZ} Hz"
      return 0
    fi
    sleep 1
  done
  echo "WARNING: No data on ${topic}"
  return 1
}

get_topic_info() {
  local topic="$1"
  local ros2_app="iconom-ros2_app-1"
  docker exec "${ros2_app}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; ros2 topic info '"${topic}"' 2>/dev/null' || true
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
  local ros2_app="iconom-ros2_app-1"
  local sample

  sample=$(docker exec "${ros2_app}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; timeout 5 ros2 topic echo --once '"${topic}"' 2>/dev/null' || true)

  [[ -n "${sample}" ]] && echo "${sample}" | grep -Eq 'header:|pose:'
}

topic_has_nonzero_rate() {
  local topic="$1"
  local ros2_app="iconom-ros2_app-1"
  local hz_output
  local rate

  hz_output=$(docker exec "${ros2_app}" bash -lc \
    'source /opt/ros/humble/setup.bash 2>/dev/null; timeout 6 ros2 topic hz '"${topic}"' 2>/dev/null' || true)
  rate=$(echo "${hz_output}" | awk '/average rate:/ {print $3; exit}')

  if [[ -z "${rate}" || "${rate}" == "0" || "${rate}" == "0.0" || "${rate}" == "nan" ]]; then
    return 1
  fi

  awk -v r="${rate}" 'BEGIN {exit !(r+0>0)}'
}

capture_overlay_frame() {
  local expect_crosshair="$1"
  local timeout_seconds="${2:-12}"
  local ros2_app="iconom-ros2_app-1"
  local overlay_topic="/plane_01/camera/image_overlay"

  echo "Validating overlay frame (expect=${expect_crosshair}, timeout=${timeout_seconds}s)..."
  if ! docker exec "${ros2_app}" bash -lc '
    set +u
    source /opt/ros/humble/setup.bash >/dev/null 2>&1
    if [[ -f /workspaces/ros2_ws/install/setup.bash ]]; then
      source /workspaces/ros2_ws/install/setup.bash >/dev/null 2>&1
    fi
    set -u
    timeout '"${timeout_seconds}"' python3 /workspaces/scripts/validate-overlay-frame.py \
      --topic '"${overlay_topic}"' \
      --expect '"${expect_crosshair}"' \
      --timeout '"${timeout_seconds}"'
  '; then
    echo "ERROR: overlay frame validation failed for expect=${expect_crosshair}" >&2
    return 1
  fi

  echo "Overlay frame validation passed for expect=${expect_crosshair}"
}

wait_for_pose_check() {
  local description="$1"
  local timeout="$2"
  shift 2

  local start_time=${SECONDS}

  echo "Pose readiness check: ${description}"
  while (( SECONDS - start_time < timeout )); do
    if "$@"; then
      echo "  PASS: ${description}"
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
  local ownship_topic="/competition/ownship/state"
  local rival_topic="/fusion/rival/state"

  echo "Waiting for pose topic readiness gate..."

  wait_for_pose_check "${ownship_topic} type is ${expected_type}" "${timeout}" topic_has_type "${ownship_topic}" "${expected_type}" || return 1
  wait_for_pose_check "${ownship_topic} publisher count is exactly 1" "${timeout}" topic_has_publisher_count "${ownship_topic}" "1" || return 1
  wait_for_pose_check "${rival_topic} type is ${expected_type}" "${timeout}" topic_has_type "${rival_topic}" "${expected_type}" || return 1
  wait_for_pose_check "${rival_topic} publisher count is exactly 1" "${timeout}" topic_has_publisher_count "${rival_topic}" "1" || return 1
  wait_for_pose_check "${ownship_topic} publishes a PoseStamped sample" "${timeout}" topic_has_pose_sample "${ownship_topic}" || return 1
  wait_for_pose_check "${rival_topic} publishes a PoseStamped sample" "${timeout}" topic_has_pose_sample "${rival_topic}" || return 1
  wait_for_pose_check "${ownship_topic} publish rate is non-zero" "${timeout}" topic_has_nonzero_rate "${ownship_topic}" || return 1
  wait_for_pose_check "${rival_topic} publish rate is non-zero" "${timeout}" topic_has_nonzero_rate "${rival_topic}" || return 1

  echo "Pose topic readiness gate passed"
}

start_symbology_overlay() {
  local ros2_app="iconom-ros2_app-1"
  
  echo "Building iconom_vision package..."
  docker exec "${ros2_app}" bash -lc '
    source /opt/ros/humble/setup.bash
    cd /workspaces/ros2_ws
    colcon build --packages-select iconom_vision 2>&1 || true
    source install/setup.bash
    ros2 run iconom_vision camera_symbology_overlay &
  ' > /tmp/symbology.log 2>&1 &
  
  sleep 5
}

main() {
  start_services
  
  echo "Spawning planes..."
  spawn_plane "rc_cessna_0" "0 0 10 0 0 0"
  spawn_plane "rc_cessna_1" "0 15 10 0 0 0"

  wait_for_pose_topics 30
  
  wait_for_camera_topics 45
  verify_topic_data 20
  
  start_symbology_overlay
  
  local ros2_app="iconom-ros2_app-1"
  local overlay_topic="/plane_01/camera/image_overlay"
  
  echo "Waiting for overlay topic..."
  for i in $(seq 1 30); do
    TOPICS=$(docker exec "${ros2_app}" bash -lc 'source /opt/ros/humble/setup.bash 2>/dev/null; ros2 topic list 2>/dev/null' || echo "")
    if echo "${TOPICS}" | grep -q "${overlay_topic}"; then
      echo "Overlay topic found"
      break
    fi
    sleep 1
  done
  
  if [[ "${GUI_MODE}" == "true" ]]; then
    echo "Running deterministic overlay validation before GUI loop..."
    move_rival "rc_cessna_1" "2,0,10 3,0,10 2,0,10" 1
    wait_for_pose_topics 20
    capture_overlay_frame "green" 15

    move_rival "rc_cessna_1" "0,15,10 -2,15,10" 1
    wait_for_pose_topics 20
    capture_overlay_frame "grey" 15

    echo ""
    echo "=== GUI Mode Ready ==="
    echo "Gazebo window should be visible with Cessna planes."
    echo "rqt_image_view should show the camera overlay."
    echo "Rival will fly in front of ownship."
    echo ""
    echo "Press Ctrl+C to stop and clean up"
    
    # Start rqt_image_view in background
    docker exec "${ros2_app}" bash -lc '
      source /opt/ros/humble/setup.bash
      nohup rqt_image_view /plane_01/camera/image_overlay > /dev/null 2>&1 &
    '
    
    # Move rival in a loop so it keeps flying in front
    echo "Moving rival through waypoints (looping)..."
    while true; do
      # Small smooth movements ±2m around 2m front position (1m interpolated steps)
      move_rival "rc_cessna_1" "2,0,10 3,0,10 4,0,10 3,1,10 2,2,10 1,1,10 0,0,10 1,-1,10 2,-2,10 3,-1,10 4,0,10 3,0,10 2,0,10" 1
      sleep 2
    done
  else
    echo ""
    echo "=== Headless Mode ==="
    echo "Checkpoint 1: rival in front, expect green crosshair"
    move_rival "rc_cessna_1" "2,0,10 3,0,10 4,0,10 3,0,10 2,0,10" 1
    wait_for_pose_topics 20
    capture_overlay_frame "green" 15

    echo "Checkpoint 2: rival out of camera cone, expect grey center crosshair"
    move_rival "rc_cessna_1" "0,15,10 -2,15,10" 1
    wait_for_pose_topics 20
    capture_overlay_frame "grey" 15

    echo ""
    echo "=== SYMBOLOGY INTEGRATION TEST PASSED ==="
  fi
}

main "$@"
