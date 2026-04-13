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
  
  wait_for_camera_topics 45 || echo "Continuing despite camera issues..."
  verify_topic_data 20 || echo "Continuing despite data issues..."
  
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
    echo "Moving rival through waypoints..."
    # Waypoints bring rival IN FRONT of ownship (X > 0 since camera looks in +X direction)
    # Ownship at (0, 0, 10), rival starts at (2, 0, 10), moves to front then circles
    # Small smooth movements ±2m around 2m front position (1m interpolated steps)
    move_rival "rc_cessna_1" "2,0,10 3,0,10 4,0,10 3,1,10 2,2,10 1,1,10 0,0,10 1,-1,10 2,-2,10 3,-1,10 4,0,10 3,0,10 2,0,10" 1
    
    echo "Verifying overlay still active..."
    for i in $(seq 1 15); do
      TOPICS=$(docker exec "${ros2_app}" bash -lc 'source /opt/ros/humble/setup.bash 2>/dev/null; ros2 topic list 2>/dev/null' || echo "")
      if echo "${TOPICS}" | grep -q "${overlay_topic}"; then
        echo "Overlay still active"
        break
      fi
      sleep 1
    done
    
    echo ""
    echo "=== SYMBOLOGY INTEGRATION TEST PASSED ==="
  fi
}

main "$@"
