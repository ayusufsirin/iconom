# Phase 7 Slice 2 — Visual Detection Node Implementation Plan

## Status
- **State**: Planned (not started)
- **Scope**: Phase 7 Slice 2 only (visual detection node)
- **Out of scope**: position estimation (Slice 3), EKF fusion (Slice 4), Phase 6 guidance changes

## Table of Contents
- [Task 1: Add ultralytics YOLO to Dockerfile](#task-1-add-ultralytics-yolo-to-dockerfile)
- [Task 2: Create aircraft_detector.py node](#task-2-create-aircraft_detectorpy-node)
- [Task 3: Add detector to symbology profile](#task-3-add-detector-to-symbology-profile)
- [Task 4: Create detection acceptance check script](#task-4-create-detection-acceptance-check-script)
- [Task 5: Run detection regression](#task-5-run-detection-regression)

## Implementation Tasks

- [ ] 1. **Task 1: Add ultralytics YOLO to Dockerfile**

  **What**
  - Update `docker/ros2_app/Dockerfile` to install YOLO runtime dependencies for CPU inference.
  - Add `pip3 install ultralytics` in the existing Python dependency install flow.
  - Download `yolov8n.pt` at build time to a deterministic path (e.g., `/workspaces/yolov8n.pt`) using:
    - `https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n.pt`

  **Must Do**
  - Keep existing constraints (`numpy<2`, `opencv-python-headless<4.10`) intact.
  - Use `pip3 install ultralytics` (not `pip install ultralytics`).
  - Ensure the model file is available in-container without manual runtime download prompts.

  **Must Not Do**
  - Do not introduce GPU-only dependencies or require CUDA.
  - Do not change unrelated Docker topology or compose architecture.
  - Do not move this work into phase guidance/runtime files.

  **Acceptance Criteria**
  - [ ] `docker/ros2_app/Dockerfile` includes `ultralytics` install.
  - [ ] `docker/ros2_app/Dockerfile` includes deterministic `yolov8n.pt` fetch path.
  - [ ] Rebuilt `ros2_app` image can import `ultralytics` successfully.

  **QA Scenarios**
  ```
  Scenario: Dependency + model presence
    Tool: Bash
    Steps: Rebuild ros2_app image, start container, run Python import check and list model file path.
    Expected: ultralytics import succeeds and /workspaces/yolov8n.pt exists.

  Scenario: Headless CPU compatibility
    Tool: Bash
    Steps: Run a minimal YOLO load/inference bootstrap in ros2_app without GPU flags.
    Expected: model loads on CPU and process exits cleanly.
  ```

  **Commit message**
  - `feat(phase7): add ultralytics YOLOv8 to ros2_app`

- [ ] 2. **Task 2: Create aircraft_detector.py node**

  **What**
  - Add `ros2_ws/src/iconom_vision/iconom_vision/aircraft_detector.py`.
  - Subscribe to `/plane_01/camera/image_raw` and convert images with `cv_bridge`.
  - Run YOLOv8n inference per frame using `yolov8n.pt`.
  - For initial proxy detection against `gz_rc_cessna`, filter target classes using `person` (and optionally `airplane` if present in model labels).
  - Publish detections on `/vision/detections` using a practical interim message shape (preferred: `visualization_msgs/msg/MarkerArray` or existing project-supported box array).
  - Log when detections are found and continue cleanly when no detections appear.
  - Register node in `setup.py` entry points:
    - `aircraft_detector = iconom_vision.aircraft_detector:main`

  **Must Do**
  - Keep implementation in `iconom_vision` package only.
  - Ensure node runs in headless mode and does not require display/GPU.
  - Handle empty detection frames without exceptions (log + continue).

  **Must Not Do**
  - Do not add position estimation logic (Slice 3).
  - Do not add EKF fusion logic (Slice 4).
  - Do not modify `camera_symbology_overlay.py`.
  - Do not touch phase-6 guidance nodes.

  **Acceptance Criteria**
  - [ ] New node file exists and compiles in ROS workspace.
  - [ ] Node subscribes to `/plane_01/camera/image_raw`.
  - [ ] Node publishes to `/vision/detections`.
  - [ ] `setup.py` contains the new `aircraft_detector` entry point.
  - [ ] Runtime logs show graceful behavior for both detection and no-detection frames.

  **QA Scenarios**
  ```
  Scenario: Node startup and topic wiring
    Tool: Bash
    Steps: Build workspace, run aircraft_detector, check `ros2 topic info` for input/output topics.
    Expected: one subscriber on /plane_01/camera/image_raw and one publisher on /vision/detections.

  Scenario: No-detection robustness
    Tool: Bash
    Steps: Run detector with frames that do not contain target class.
    Expected: node remains alive, logs no-detection status, publishes valid empty/neutral outputs as designed.
  ```

  **Commit message**
  - `feat(phase7): add YOLOv8 aircraft detector node`

- [ ] 3. **Task 3: Add detector to symbology profile**

  **What**
  - Update `docker-compose.yml` so the detector launches automatically in the symbology profile (or equivalent bounded wiring in existing service startup path).
  - Ensure detector node startup order is compatible with existing camera topic availability.
  - If auto-start cannot be wired cleanly in current profile flow, add explicit startup/verification hook in symbology check script that enforces detector publication.

  **Must Do**
  - Keep profile behavior aligned with canonical compose stack conventions.
  - Ensure detector is active when symbology profile is active.
  - Preserve existing service names and contract assumptions where possible.

  **Must Not Do**
  - Do not introduce architecture drift between local and CI compose behavior.
  - Do not change unrelated profile semantics.
  - Do not alter high-risk infrastructure outside detector wiring needs.

  **Acceptance Criteria**
  - [ ] Symbology profile starts detector path automatically.
  - [ ] `/vision/detections` has at least one active publisher during profile runtime.
  - [ ] Existing symbology stack still boots without regressions.

  **QA Scenarios**
  ```
  Scenario: Symbology profile auto-start
    Tool: Bash
    Steps: Start compose symbology profile, inspect running services and detector logs.
    Expected: detector starts without manual intervention and stays healthy.

  Scenario: Topic publication contract
    Tool: Bash
    Steps: Query /vision/detections topic info while profile is running.
    Expected: topic exists with >=1 publisher from detector node.
  ```

  **Commit message**
  - `feat(phase7): wire aircraft detector into symbology profile`

- [ ] 4. **Task 4: Create detection acceptance check script**

  **What**
  - Add `scripts/check-phase7-detection.sh`.
  - Script flow: start required services, spawn Cessna planes, run detector for 10s, verify `/vision/detections` publications occurred.
  - Fail hard if no detections are observed within the 10-second window.

  **Must Do**
  - Keep script headless-friendly and deterministic.
  - Validate both topic availability and message activity (not just topic existence).
  - Emit clear pass/fail logs for CI/operator diagnosis.

  **Must Not Do**
  - Do not require GUI interaction.
  - Do not include Slice 3+ behaviors (3D estimation, EKF fusion).
  - Do not weaken failure behavior to “warn and continue”.

  **Acceptance Criteria**
  - [ ] Script exists and is executable.
  - [ ] Script exits non-zero if `/vision/detections` has no message activity after 10s.
  - [ ] Script exits zero when at least one detection message is observed.

  **QA Scenarios**
  ```
  Scenario: Positive detection path
    Tool: Bash
    Steps: Run check script in normal symbology runtime.
    Expected: script observes /vision/detections activity and exits 0.

  Scenario: Negative timeout path
    Tool: Bash
    Steps: Disable detector or force non-publishing behavior, then run check script.
    Expected: script times out at 10s and exits non-zero with explicit reason.
  ```

  **Commit message**
  - `test(phase7): add detection acceptance check`

- [ ] 5. **Task 5: Run detection regression**

  **What**
  - Execute `./scripts/check-phase7-detection.sh` in headless mode.
  - Capture evidence that detector runs, publishes, and does not crash.

  **Must Do**
  - Confirm acceptance script pass status from actual run output.
  - Verify detector has no Python exceptions/crashes during the run.
  - Keep verification focused on Slice 2 success criteria only.

  **Must Not Do**
  - Do not claim success without running the script.
  - Do not include manual-only verification in place of automated check.
  - Do not expand this task into position estimation/fusion work.

  **Acceptance Criteria**
  - [ ] `/vision/detections` topic exists with at least 1 publisher.
  - [ ] At least one bounding box/detection message is published during a 10-second run.
  - [ ] No detector node crashes or Python exceptions during the check.

  **QA Scenarios**
  ```
  Scenario: Headless regression execution
    Tool: Bash
    Steps: Run ./scripts/check-phase7-detection.sh and capture exit code + logs.
    Expected: exit code 0; detection topic publisher and at least one detection observed.

  Scenario: Runtime stability audit
    Tool: Bash
    Steps: Inspect detector logs during and after the run.
    Expected: no uncaught exceptions, no crash loop, stable detector process.
  ```

  **Commit message**
  - `test(phase7): run detection regression`
