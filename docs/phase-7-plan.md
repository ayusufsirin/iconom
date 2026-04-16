# Phase 7 Plan

This document defines the next bounded phase after the validated phase-6 pursuit/cueing baseline.

Phase 7 does not implement visual lock scoring, autonomous weapon engagement, or hardware-facing behavior. Its job is to add visual detection and high-rate state fusion to the existing rival tracking pipeline, enabling the ownship to track the rival using camera feedback in addition to the 1 Hz referee data.

## Purpose

Phase 6 proved that geometric cueing can bring the rival into the forward camera view:

- deterministic target selection works,
- bounded intercept planning produces guidance targets,
- pursuit state machine commands the aircraft,
- the rival is brought into the forward camera cone through geometric steering.

What is still missing is **visual confirmation** that the rival is actually in frame, and **higher-rate rival tracking** beyond the 1 Hz referee limit.

Phase 7 exists to add computer vision detection and sensor fusion. It does not yet attempt multi-frame tracking, lock scoring, or visual feedback loops to guidance.

## Phase 7 Goal

Add visual detection and EKF-based state fusion to the maintained rivalry tracking pipeline.

Success means:

1. the forward camera can detect the rival aircraft in the image stream,
2. detected bounding boxes can be converted to 3D position estimates using camera intrinsics,
3. an EKF fuses referee data (1 Hz, accurate) with camera estimates (30 Hz, noisy) into a high-rate fused track,
4. the fused track is published at 30+ Hz for downstream guidance consumption,
5. the detection and fusion pipeline runs headlessly and is acceptance-validated,
6. the same behavior is observable in GUI mode.

## Phase 7 Scope

Phase 7 is limited to visual detection and sensor fusion.

Included:

- one YOLO-based detector node subscribing to `/plane_01/camera/image_raw`
- one position estimation node converting bounding boxes to 3D pose
- one EKF fusion node combining referee state with camera estimates
- fused track publication on a new topic for downstream consumption
- headless acceptance validation for detection and fusion
- GUI confirmation of detection visualization

Excluded:

- multi-frame tracking (single-frame detection only)
- lock rectangle scoring
- visual feedback to pursuit guidance (fused track only, not visual闭环)
- object classification beyond aircraft detection
- real hardware integration
- more than two aircraft visual tracking
- autonomous weapon or intercept logic

## Locked Phase 7 Contract

The following constraints stay fixed unless deliberately revised:

- ownship remains `plane_01`
- rival remains `plane_02` (as the target aircraft to detect)
- camera remains the forward camera under `/plane_01/camera/...`
- camera intrinsics source remains `/plane_01/camera/camera_info`
- referee-based rival state remains the ground-truth source at 1 Hz
- fused track topic must be usable by existing guidance nodes without modification
- detection must run in headless mode for CI validation
- phase 7 does not modify the phase-6 acceptance baseline

## Technical Approach

### Detection Layer

Use a lightweight YOLO model (YOLOv8-nano or YOLOv11-nano) for real-time detection:

- Subscribe to `/plane_01/camera/image_raw`
- Run inference using Ultralytics YOLO (Python, GPU-capable)
- Publish detections as `visualization_msgs/msg/MarkerArray` on `/vision/detections`
- Topic: `/vision/detections` remains the detector output as `visualization_msgs/msg/MarkerArray`

**Reference**: `mgonzs13/yolov8_ros` provides ROS 2-native YOLO integration.

### Position Estimation Layer

Convert 2D bounding box to 3D position using camera model:

- Use `/plane_01/camera/camera_info` for camera intrinsics (K matrix)
- Apply monocular depth estimation or assume known rival size for scaling
- Publish estimated rival pose in world frame
- Topic: `/vision/rival_pose` (PoseStamped)

For the simulation baseline, the known aircraft size (`gz_rc_cessna` dimensions) provides depth scaling without needing a separate depth estimator.

### Fusion Layer

Implement an Extended Kalman Filter (EKF) that fuses:

| Source | Rate | Quality |
|--------|------|---------|
| Referee (`/competition/rival/state/referee`) | 1 Hz | Ground truth, but delayed |
| Camera estimate (`/vision/rival_pose`) | ~30 Hz | Noisy, high-rate |

- Use the existing `iconom_competition/ekf_fusion.py` EKF node with Phase-7 parameter mode
- State vector: position (x, y, z), velocity (vx, vy, vz)
- Publish fused state at 30 Hz on `/fusion/rival/state`, with exactly one publisher, the EKF node
- The fused track replaces the raw referee feed for downstream guidance

### Integration with Phase 6

The fused track from Phase 7 feeds into the existing phase-6 guidance chain:

```
Phase 6 input (before):  /competition/rival/state (1 Hz)
Phase 7 output (after):  /fusion/rival/state (30 Hz)
```

Guidance nodes subscribe to `/fusion/rival/state` instead of the raw referee topic. No changes to phase-6 guidance logic required.

## Implementation Order

## Shared Rival-Movement Validation Harness (Slices 3–4)

> **HARNESS IS MANDATORY FOR SLICES 3 AND 4. IT IS NOT PART OF SLICE 2 ACCEPTANCE.**

The existing rival-movement symbology scenario is the mandatory comparison environment for all later Phase 7 perception and fusion validation. It is not optional, not a "nice-to-have", and not a separate benchmarking world.

**Purpose**: Provides a known-good, ground-truth-validated environment where rival motion is scripted, 3D pose is known, and reverse-projected symbology overlay produces a verifiable baseline. Slices 3 and 4 must compare their output against this baseline.

**Truth stream**: Slice 3 and Slice 4 harness truth comes from `/truth/rival/state`, so `/fusion/rival/state` stays a single-publisher EKF output during validation.

**Reused components**:
- `sim/worlds/symbology_test.sdf` — world shell
- `scripts/check-symbology-integration.sh` — rival movement orchestration, camera/symbology startup
- `camera_symbology_overlay` node — reverse-projected truth baseline (publishes `/plane_01/camera/image_overlay`)
- `rc_cessna_1` as scripted rival with known interpolated pose at all times

**Slice 2 boundary**: Slice 2 acceptance remains detector-only. The shared harness does not expand Slice 2 scope.

**Time alignment**: Nearest-timestamp matching with maximum allowed skew of 100 ms.

**Artifact requirements**: Every harness run must produce raw logs, aligned metric summary, and visualization artifacts under `.sisyphus/evidence/`.

**GUI-observable**: The harness must be observable in GUI mode so reviewers can confirm the rival is visually present in the scene during validation runs.

### Slice 1: Phase 7 Baseline Plan

Pin the exact detection and fusion boundaries, package names, and acceptance goal.

Success:

- one source-of-truth document exists,
- phase 7 has explicit scope and exclusions,
- no implementation starts before the plan is pinned.

### Slice 2: Visual Detection Node

Add one YOLO-based detector that subscribes to the forward camera and publishes bounding boxes.

Success:

- detector runs and publishes bounding boxes on `/vision/detections`,
- detector handles the `gz_rc_cessna` model appearance in simulation,
- one maintained check proves detection output appears in headless mode.

### Slice 3: Position Estimation Node

Add one node that converts bounding boxes to 3D position estimates using camera intrinsics.

Success:

- node subscribes to `/vision/detections` and `/plane_01/camera/camera_info`,
- node publishes estimated rival pose on `/vision/rival_pose`,
- estimation runs at camera frame rate (~30 Hz).

#### Shared Harness Validation (Slices 3–4)

> This section is MANDATORY for Slice 3 completion.

Slice 3 must be validated inside the shared rival-movement symbology harness defined in "Shared Rival-Movement Validation Harness (Slices 3–4)". Slice 3 cannot pass by running the position estimator in isolation or in an unvalidated scenario.

**Comparison streams** (both required simultaneously):
1. Reverse-projected truth baseline — from `camera_symbology_overlay` publishing `/plane_01/camera/image_overlay` (3D pose known from `rc_cessna_1` interpolated position)
2. YOLO-derived position estimation — from the Slice 3 node publishing `/vision/rival_pose` (bounding box → 3D via camera intrinsics)

**Time alignment**: Nearest-timestamp matching; maximum allowed skew: 100 ms.

**Required metrics** (all must be computed during the harness run):
- **Detection coverage %**: fraction of frames where YOLO produced a valid detection
- **Timestamp skew**: measured difference between baseline and estimation timestamps (must stay ≤ 100 ms)
- **Image-plane center error (px)**: Euclidean distance in pixels between projected baseline center and estimated center
- **Bearing error (deg)**: angular difference in degrees between baseline and estimated bearing to rival
- **3D position RMSE (m)**: root-mean-square error in meters of the estimated rival position vs. ground truth from the harness

**Artifact requirements** (mandatory — cannot pass without):
- Raw log of both streams with timestamps
- Aligned CSV or JSON file containing all five metrics per aligned sample
- At least one visualization artifact (e.g., overlaid image showing baseline and estimation traces together)
- All artifacts written to `.sisyphus/evidence/` with naming pattern `task-2-slice3-harness-*`

**Not acceptable**:
- Manual "looked okay" confirmation
- Only topic existence proof
- Comparison without the ground-truth baseline stream

### Slice 4: EKF Fusion Node

Add one EKF that fuses referee state with camera estimates.

Success:

- node subscribes to both `/competition/rival/state` (1 Hz) and `/vision/rival_pose` (30 Hz),
- node publishes fused state on `/fusion/rival/state` at 30 Hz as the only publisher on that topic,
- fused track is smoother than raw camera input and higher-rate than referee alone.

#### Shared Harness Validation (Slices 3–4)

> This section is MANDATORY for Slice 4 completion.

Slice 4 must be validated inside the shared rival-movement symbology harness defined in "Shared Rival-Movement Validation Harness (Slices 3–4)". Slice 4 cannot pass by running the EKF in isolation or against only one comparison stream.

**Three comparison streams** (all three required simultaneously):
1. **Reverse-projected baseline** — from `camera_symbology_overlay` publishing `/plane_01/camera/image_overlay` (ground truth from `rc_cessna_1` interpolated position)
2. **Raw YOLO-derived visual estimate** — from the Slice 3 node publishing `/vision/rival_pose` (bounding box → 3D via camera intrinsics, unfiltered)
3. **Fused rival state** — from the Slice 4 EKF publishing `/fusion/rival/state` (EKF output combining referee + visual, and the only publisher on the topic)

**Time alignment**: Nearest-timestamp matching; maximum allowed skew: 100 ms.

**Required metrics** (all must be computed during the harness run):
- **Timestamp skew**: measured difference between any two streams' timestamps (must stay ≤ 100 ms)
- **3D position RMSE — raw vs fused**: RMSE in meters of the raw visual estimate vs. fused track relative to ground truth baseline
- **Bearing error — raw vs fused (deg)**: angular difference in degrees for raw estimate and fused output separately, relative to baseline bearing
- **Jitter reduction %**: `(stddev(raw_position) - stddev(fused_position)) / stddev(raw_position) * 100` — fused jitter must be lower than raw (positive reduction)
- **Dropout recovery time (s)**: time elapsed from last valid visual detection until fused track resumes producing estimates after a simulated dropout (when raw estimate goes missing for ≥ 5 frames)

**Improvement gate** (failing this gate fails Slice 4):
- Jitter reduction % must be > 0 (fused must be smoother than raw)
- Dropout recovery must complete within 2 seconds

**Artifact requirements** (mandatory — cannot pass without):
- Raw log of all three streams with timestamps
- Aligned CSV or JSON containing all metrics per aligned sample
- Visualization showing raw vs fused trajectory overlaid on baseline
- All artifacts written to `.sisyphus/evidence/` with naming pattern `task-3-slice4-harness-*`

**Not acceptable**:
- Raw-vs-fused comparison without the baseline stream
- "Smoother looks okay" eyeball confirmation
- Only topic existence proof
- Dropout recovery time exceeding 2 seconds

### Slice 5: Integration and Acceptance

Wire the fused track into the guidance chain and validate end-to-end.

Success:

- downstream guidance nodes consume `/fusion/rival/state` without modification,
- headless acceptance script validates detection + fusion pipeline,
- GUI mode shows detection overlay and fused track visualization.

## Acceptance Criteria

Phase 7 is complete when all of the following are true:

- one YOLO detector publishes bounding boxes on `/vision/detections`,
- one position estimator publishes 3D pose on `/vision/rival_pose`,
- one EKF fusion node publishes high-rate track on `/fusion/rival/state`, and it is the only publisher on that topic,
- fused track rate is 30+ Hz (matching camera frame rate),
- fused track is demonstrably smoother than raw camera input,
- headless acceptance script validates the detection-fusion pipeline,
- detection overlay and fused track are observable in GUI mode (see Shared Harness Validation Requirement),
- phase-6 guidance nodes work with fused input without code changes.

### Shared Harness Validation Requirement

Phase 7 cannot be called complete without a successful run of the shared rival-movement symbology harness in both of the following modes:

**Headless mode acceptance**:
- The shared symbology rival-movement scenario runs headless via `scripts/check-symbology-integration.sh` or equivalent
- Raw logs, aligned metrics (coverage %, timestamp skew, image-plane center error, bearing error, 3D RMSE), and topic-rate evidence are produced as artifacts
- Artifacts written to `.sisyphus/evidence/` with naming pattern `task-final-phase7-harness-*`
- All three streams (baseline, raw visual, fused) are present and time-aligned

**GUI-observable acceptance**:
- The shared symbology rival-movement scenario runs in GUI mode (`--gui`)
- Reverse-projected baseline overlay and visual/fused outputs are observable simultaneously
- Screenshot or recording artifact confirms rival is present in scene and overlays are rendering
- Artifact written to `.sisyphus/evidence/` as `task-final-phase7-harness-gui.{png,mp4}`

**Evidence bundle**:
A complete Phase 7 acceptance bundle must contain:
- Headless run: raw logs + CSV/JSON metrics + topic-rate evidence (min. 3 files)
- GUI run: at least 1 screenshot or video artifact
- Naming convention: `task-final-phase7-harness-*`

## Out of Scope for Phase 7

The following topics belong to later phases and should not be pulled into early phase 7 slices:

- multi-frame tracking or temporal filtering beyond EKF
- lock rectangle scoring or visual lock confirmation publishing
- visual feedback loops to pursuit state machine
- object classification beyond aircraft detection
- depth estimation networks
- hardware camera integration
- real-world deployment
- weapon or intercept logic

## Proposed Repo Additions

Phase 7 should add files in this shape:

- `docs/phase-7-plan.md` — this document
- `scripts/check-phase7-detection.sh` — detector validation
- `scripts/check-phase7-position-estimation.sh` — position estimator validation
- `scripts/check-phase7-fusion.sh` — EKF fusion validation
- `scripts/phase7-acceptance.sh` — full pipeline validation
- `ros2_ws/src/iconom_vision/` — vision processing package (expand existing)
  - `aircraft_detector.py` — YOLO-based aircraft detection
  - `position_estimator.py` — bbox to 3D pose conversion
- `ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py` — EKF state fusion
- `ros2_ws/src/iconom_vision/msg/Detections.msg` — bounding box message (if needed)

## First Step After This Plan

The first implementation step after this document should be the visual detection slice.

That slice should:

- subscribe to `/plane_01/camera/image_raw`,
- run YOLO inference on each frame,
- publish bounding boxes to `/vision/detections`,
- add one maintained check script,
- avoid position estimation or fusion yet.
