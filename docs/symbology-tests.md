# Symbology Smoke Test Suite

## Overview

Comprehensive test suite for the camera symbology overlay feature, progressing from unit tests to full integration.

## Test Phases

| Phase | Type | Duration | Purpose |
|-------|------|----------|---------|
| 1 | Unit Tests | ~5s | Verify projection math correctness |
| 2 | Topic Smoke | ~1min | Verify node subscribes/publishes correctly |
| 3 | Integration | ~3-5min | Full test with real camera + 3D movement |
| 4 | Full Sim | ~15min | Complete integration with flying aircraft |

---

## Phase 1: Unit Tests

**Purpose**: Verify the projection math (pinhole camera model) is correct without ROS dependencies.

### Files
- `ros2_ws/src/iconom_vision/iconom_vision/test_symbology_projection.py`

### What It Tests
- Center projection (rival directly in front)
- Offset projection (rival to the side)
- Behind detection (rival behind ownship)
- Too-close detection (rival within 0.1m)
- Out-of-frame projection
- Different camera parameters (640x480, 1280x720)
- Edge cases (zero offsets, negative dz)

### Run

```bash
cd /home/joseph/Projects/iconom
python3 -m pytest ros2_ws/src/iconom_vision/iconom_vision/test_symbology_projection.py -v
```

### Expected Output
```
========================== 15 passed in 0.07 seconds ===========================
```

---

## Phase 2: Topic Smoke Test

**Purpose**: Verify the symbology node starts, subscribes to required topics, and publishes the overlay topic.

### Files
- `scripts/check-symbology-topics.sh`

### Prerequisites
- Docker installed
- `.env.example` exists
- `docker-compose.yml` valid

### Run

```bash
cd /home/joseph/Projects/iconom
./scripts/check-symbology-topics.sh
```

### What It Does
1. Starts ros2_app + ros_gz_bridge + gazebo containers
2. Waits for camera topic to appear
3. Launches camera_symbology_overlay node
4. Verifies /plane_01/camera/image_overlay topic appears
5. Verifies overlay is being published

### Expected Output
```
=== Phase 2: Symbology Topics Smoke Test ===
step 1: start ros2_app + ros_gz_bridge + gazebo
...
step 4: verify overlay topic
overlay found at 1
step 5: verify overlay publishes
=== PHASE 2 PASSED ===
```

### Troubleshooting
- If "camera not found": Check gazebo is running and ros_gz_bridge is connected
- If "overlay not found": Check iconom_vision package is installed in container

---

## Phase 3: Integration Test

**Purpose**: Full integration test with real camera feed from Gazebo and script-controlled 3D movement.

### Files
- `scripts/check-symbology-integration.sh`
- `scripts/move_gazebo_object.py`

### Run (Headless)

```bash
cd /home/joseph/Projects/iconom
./scripts/check-symbology-integration.sh
```

### Run (GUI - See the visualization)

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker 2>/dev/null || true
./scripts/check-symbology-integration.sh --gui
```

### What It Does (Headless)
1. Starts gazebo + ros2_app + ros_gz_bridge
2. Waits for camera topic
3. Launches symbology node
4. Verifies overlay topic
5. Moves plane_02 through 3D waypoints using gz CLI
6. Verifies overlay persists through movement

### What It Does (GUI)
Same as headless +:
- Opens Gazebo GUI window showing planes
- Allows you to watch the 3D scene
- Camera overlay can be viewed externally

### Waypoints Used
```
A: (0, 50, 10)   - 50m ahead, 10m altitude
B: (30, 30, 15)  - diagonal approach
C: (50, 0, 10)   - directly ahead, 50m
D: (30, -30, 5)  - passing to the right
E: (0, -50, 10)  - 50m behind to the left
```

### View Camera Overlay (GUI mode)

While test is running, in another terminal:

```bash
./scripts/view-phase6-ownship-camera.sh
# Press 'e' to edit, set: CAMERA_TOPIC=/plane_01/camera/image_raw

# Or view overlay (after test starts symbology node)
# Edit and set: CAMERA_TOPIC=/plane_01/camera/image_overlay
```

You should see:
- **Raw camera**: plane_01's forward camera view
- **Overlay**: Same view with green circle + "RIVAL" text marking where plane_02 appears

### Expected Output
```
=== Phase 3: Symbology Integration Test (gui mode) ===
step 1: start gazebo + ros2_app + ros_gz_bridge (GUI)
...
step 6: move plane_02 via gz (3D waypoints)
Waypoint 1/5: (0, 50, 10)
Moved plane_02 to (0, 50, 10)
...
Completed 5 waypoints
step 7: verify overlay still present
overlay still present at 1
=== PHASE 3 PASSED ===
```

---

## Phase 4: Full Simulation Test

**Purpose**: Complete integration test with actual flying aircraft using autopilot.

### Existing Scripts (already exist)
- `scripts/check-phase6-camera-symbology.sh`
- `scripts/check-phase6-live-rival-geometry.sh --with-overlay`

### Run

```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-camera-symbology.sh
```

### What It Does
- Starts full PX4 simulation with two aircraft
- Runs autopilot for both planes
- Enables symbology overlay on plane_01's camera
- Verifies marker appears correctly during actual chase behavior

---

## Quick Reference

| Test | Command | Time |
|------|---------|------|
| Unit tests | `python3 -m pytest .../test_symbology_projection.py -v` | 5s |
| Topic smoke | `./scripts/check-symbology-topics.sh` | 1min |
| Integration (headless) | `./scripts/check-symbology-integration.sh` | 3min |
| Integration (GUI) | `./scripts/check-symbology-integration.sh --gui` | 5min |
| Full sim | `./scripts/check-phase6-camera-symbology.sh` | 15min |

---

## Cleanup

After any test:

```bash
cd /home/joseph/Projects/iconom
docker compose -f docker-compose.yml down --remove-orphans
```

---

## Development Workflow

1. **Start with Phase 1** - Fast feedback on math changes
   ```bash
   python3 -m pytest .../test_symbology_projection.py -v
   ```

2. **Verify node wiring** - Phase 2
   ```bash
   ./scripts/check-symbology-topics.sh
   ```

3. **Test with real camera** - Phase 3
   ```bash
   ./scripts/check-symbology-integration.sh --gui
   ```

4. **Full acceptance** - Phase 4
   ```bash
   ./scripts/check-phase6-live-rival-geometry.sh --incremental --with-overlay
   ```

---

## CI Integration

These tests can be triggered at different stages:

| Phase | CI Trigger | Purpose |
|-------|------------|---------|
| 1 | Every PR | Fast feedback on math changes |
| 2 | Every PR | Verify node still subscribes/publishes |
| 3 | Merge to feature branch | Validate integration works |
| 4 | Release tags | Full acceptance test |
