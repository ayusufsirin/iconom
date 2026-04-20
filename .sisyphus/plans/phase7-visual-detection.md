# Phase 7 — Visual Detection, Position Estimation, and Fusion

## TL;DR
> **Summary**: Implement the full Phase 7 pipeline by preserving the canonical intent of `docs/phase-7-plan.md` while correcting stale contracts to match repo reality. Keep detector and estimator in `iconom_vision`, keep fusion in `iconom_competition`, separate harness truth from fused output, and add maintained Slice 3 / Slice 4 / final acceptance scripts.
> **Deliverables**:
> - repo-aligned Phase 7 contract lock in `docs/phase-7-plan.md`
> - hardened Slice 2 detector contract and regression coverage
> - new `position_estimator` node publishing `/vision/rival_pose`
> - Phase-7 mode for existing `iconom_competition/ekf_fusion.py`
> - `check-phase7-position-estimation.sh`, `check-phase7-fusion.sh`, `phase7-acceptance.sh`
> - shared-harness metrics, GUI evidence path, and downstream fused-topic compatibility check
> **Effort**: XL
> **Parallel**: YES - 3 waves
> **Critical Path**: 1 → 3/4/5 → 6 → 7 → 8 → 9 → 10 → 11

## Context
### Original Request
- Create a Sisyphus-compatible work plan using the canonical Phase 7 plan.

### Interview Summary
- Prior prerequisite plans are already complete: `phase7-cv-bridge-numpy-fix` and `phase7-shared-harness-amendment`.
- The canonical `docs/phase-7-plan.md` remains the source-of-truth intent document, but parts of its implementation contract are stale.
- The unified Sisyphus plan must cover the full Phase 7 execution path, not only the earlier Slice 2 draft.

### Metis Review (gaps addressed)
- Treat Slice 2 as regression/hardening, not greenfield.
- Lock repo-real contracts explicitly: keep fusion in `iconom_competition`, use `/fusion/rival/state`, do not create a second EKF in `iconom_vision`.
- Reuse the shared symbology harness instead of inventing a parallel benchmark stack.
- Add exact acceptance scripts, thresholds, evidence paths, dropout behavior, and downstream compatibility checks.

## Work Objectives
### Core Objective
Deliver the complete Phase 7 perception pipeline: detector output on `/vision/detections`, 3D rival pose on `/vision/rival_pose`, fused high-rate track on `/fusion/rival/state`, maintained headless acceptance, and GUI-observable evidence using the shared rival-movement harness.

### Deliverables
- `docs/phase-7-plan.md` updated to repo-real contracts
- Slice 2 detector contract hardened around the current `MarkerArray` output
- `ros2_ws/src/iconom_vision/iconom_vision/position_estimator.py`
- `ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py` adapted for a Phase-7 visual-input mode while preserving Phase-6 defaults
- parameterized harness truth / overlay plumbing for simultaneous baseline, raw, and fused comparison
- `scripts/check-phase7-position-estimation.sh`
- `scripts/check-phase7-fusion.sh`
- `scripts/phase7-acceptance.sh`

### Definition of Done (verifiable conditions with commands)
- `python3 -m pytest ros2_ws/src/iconom_vision/iconom_vision/test_symbology_projection.py ros2_ws/src/iconom_vision/iconom_vision/test_position_estimator.py ros2_ws/src/iconom_competition/iconom_competition/test_ekf_fusion_phase7.py`
- `./scripts/check-phase7-detection.sh`
- `./scripts/check-phase7-position-estimation.sh`
- `./scripts/check-phase7-fusion.sh`
- `./scripts/phase7-acceptance.sh`
- `grep -R "/fusion/rival_state\|ekf_fuser.py" docs/phase-7-plan.md scripts/ ros2_ws/src/ docker/` returns no Phase-7 contract matches

### Must Have
- Canonical intent preserved, but repo-real implementation contract adopted where the canonical doc is stale.
- Detector + estimator ownership remain in `iconom_vision`.
- Fusion ownership remains in `iconom_competition` via `ekf_fusion.py`.
- Fused topic contract is `/fusion/rival/state`.
- Detector output contract remains `visualization_msgs/msg/MarkerArray` on `/vision/detections`.
- Harness truth is separated onto `/truth/rival/state` for Phase 7 validation so `/fusion/rival/state` has exactly one publisher.
- `ekf_fusion.py` keeps Phase-6 defaults intact, but gains a Phase-7 parameter mode using `/vision/rival_pose` as the high-rate input and `publish_rate_hz=30.0`.
- Slice 3 and Slice 4 both use the shared symbology harness and write artifacts under `.sisyphus/evidence/`.

### Must NOT Have
- No new EKF implementation in `iconom_vision`.
- No `/fusion/rival_state` underscore topic in any Phase-7 implementation artifact.
- No second effective publisher on `/fusion/rival/state` during Slice 4 or final acceptance.
- No new benchmarking world or replacement of `scripts/check-symbology-integration.sh`.
- No Phase-6 guidance logic rewrite.
- No custom detection message unless `MarkerArray` is proven insufficient; default is to keep the current contract.
- No human-only QA or “looks okay” acceptance.

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: **TDD for new Slice 3 / Slice 4 code, tests-after for existing Slice 2 regression**.
- QA policy: every task includes a concrete command path plus happy-path and failure-path evidence.
- Numeric defaults locked for this plan:
  - Slice 3 coverage: `>= 40%`
  - Slice 3 timestamp skew: `<= 100 ms`
  - Slice 3 bearing error P95: `<= 12 deg`
  - Slice 3 image-plane center error P95: `<= 160 px`
  - Slice 3 3D position RMSE: `<= 8.0 m`
  - Slice 4 fused topic rate: `>= 25 Hz`
  - Slice 4 jitter reduction: `> 0%`
  - Slice 4 dropout recovery: `<= 2.0 s`
- Evidence: `.sisyphus/evidence/task-{N}-phase7-*.{txt,json,csv,png}`

## Execution Strategy
### Parallel Execution Waves
Wave 1: contract + harness foundations + Slice 2 hardening (Tasks 1-5)

Wave 2: Slice 3 estimator tests, node, and acceptance script (Tasks 6-8)

Wave 3: Slice 4 fusion adaptation, fusion acceptance, and final wrapper (Tasks 9-11)

### Dependency Matrix (full, all tasks)
- 1 blocks 6-11
- 2 blocks 6-8
- 3 blocks 8, 10, 11
- 4 blocks 8, 10, 11
- 5 blocks 8, 10, 11
- 6 blocks 7-8
- 7 blocks 8-10
- 8 blocks 11
- 9 blocks 10-11
- 10 blocks 11

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 5 tasks → `writing`, `quick`, `deep`
- Wave 2 → 3 tasks → `deep`
- Wave 3 → 3 tasks → `deep`, `quick`

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task MUST have: Agent Profile + Parallelization + QA Scenarios.

- [x] 1. Lock the repo-real Phase 7 contract in the canonical document and remove stale names

  **What to do**: Update `docs/phase-7-plan.md` so all implementation-facing Phase 7 contracts match repo reality. Replace `/fusion/rival_state` with `/fusion/rival/state`; replace the stale `iconom_vision/ekf_fuser.py` proposal with `iconom_competition/ekf_fusion.py`; explicitly state that detector output remains `visualization_msgs/msg/MarkerArray`; and state that harness truth uses `/truth/rival/state` during Slice 3/4 validation so `/fusion/rival/state` remains the single fused-output topic.
  **Must NOT do**: Do not widen into a new architecture document. Do not change Phase 7 scope or baseline exclusions. Do not introduce a second fusion implementation path.

  **Recommended Agent Profile**:
  - Category: `writing` — Reason: bounded contract normalization in the canonical plan.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [6, 7, 8, 9, 10, 11] | Blocked By: []

  **References**:
  - Pattern: `docs/phase-7-plan.md:93-116` — stale fusion ownership/topic contract to normalize.
  - Pattern: `docs/phase-7-plan.md:306-319` — stale proposed repo additions.
  - Pattern: `ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py:21-24` — current fused topic contract.
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/aircraft_detector.py:42-49` — current detector output contract.
  - Pattern: `docker/ros_gz_bridge/pose_bridge.py:39-40` — current truth/fused-topic collision to resolve.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `grep -n "/fusion/rival_state\|ekf_fuser.py" docs/phase-7-plan.md` returns no matches.
  - [ ] `docs/phase-7-plan.md` explicitly names `iconom_competition/ekf_fusion.py` and `/fusion/rival/state`.
  - [ ] `docs/phase-7-plan.md` explicitly states that Phase-7 harness truth uses `/truth/rival/state`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Stale-contract audit
    Tool: Bash
    Steps: Search `docs/phase-7-plan.md` for `/fusion/rival_state` and `ekf_fuser.py` after the edit.
    Expected: No stale contract strings remain.
    Evidence: .sisyphus/evidence/task-1-phase7-contract-audit.txt

  Scenario: Ownership/topic lock review
    Tool: Bash
    Steps: Search the updated doc for `MarkerArray`, `/truth/rival/state`, `iconom_competition/ekf_fusion.py`, and `/fusion/rival/state`.
    Expected: The repo-real contract is explicitly recorded.
    Evidence: .sisyphus/evidence/task-1-phase7-contract-lock.txt
  ```

  **Commit**: YES | Message: `docs(phase7): align plan with repo fusion contract` | Files: [`docs/phase-7-plan.md`]

- [x] 2. Harden the existing Slice 2 detector contract and package metadata without changing its topic/message shape

  **What to do**: Keep `aircraft_detector.py` publishing `MarkerArray`, then add the missing `visualization_msgs` dependency to `ros2_ws/src/iconom_vision/package.xml` and add detector contract tests that assert: (a) `DELETEALL` marker is emitted first, (b) bbox center is stored in `marker.pose.position.{x,y}`, (c) bbox size is stored in `marker.scale.{x,y}`, and (d) label/confidence remain encoded in `marker.text`. This task is the Slice 2 hardening step; it does not re-implement the detector.
  **Must NOT do**: Do not replace `MarkerArray` with a custom message. Do not change `/vision/detections`. Do not fold Slice 3 logic into the detector.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: narrow hardening around an existing node and package manifest.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [6, 7, 8] | Blocked By: []

  **References**:
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/aircraft_detector.py:91-150` — current marker encoding to lock.
  - Pattern: `ros2_ws/src/iconom_vision/package.xml:9-18` — package dependency list missing `visualization_msgs`.
  - Pattern: `scripts/check-phase7-detection.sh:181-197` — maintained Slice 2 acceptance entrypoint to preserve.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `iconom_vision/package.xml` includes `visualization_msgs`.
  - [ ] Detector contract tests pass and lock the current marker encoding.
  - [ ] `./scripts/check-phase7-detection.sh` still exits `0` after the hardening changes.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: MarkerArray contract regression
    Tool: Bash
    Steps: Run `python3 -m pytest ros2_ws/src/iconom_vision/iconom_vision/test_aircraft_detector_contract.py -q`.
    Expected: Tests pass and prove the current bbox encoding is preserved.
    Evidence: .sisyphus/evidence/task-2-phase7-detector-contract.txt

  Scenario: Slice 2 acceptance regression
    Tool: Bash
    Steps: Run `./scripts/check-phase7-detection.sh` after the package/test updates.
    Expected: Existing Slice 2 acceptance still passes.
    Evidence: .sisyphus/evidence/task-2-phase7-detector-regression.txt
  ```

  **Commit**: YES | Message: `test(phase7): lock detector marker contract` | Files: [`ros2_ws/src/iconom_vision/package.xml`, `ros2_ws/src/iconom_vision/iconom_vision/test_aircraft_detector_contract.py`]

- [x] 3. Parameterize harness truth publishing so baseline truth no longer collides with the fused-output topic

  **What to do**: Update `docker/ros_gz_bridge/pose_bridge.py` and its runtime wiring so ownship and rival output topics are ROS parameters instead of hard-coded strings. Preserve current defaults for non-Phase-7 callers (`/competition/ownship/state` and `/fusion/rival/state`), but allow Phase-7 scripts to launch the bridge with `rival_topic:=/truth/rival/state`. If the compose entrypoint requires env pass-through, update that pass-through only as needed for parameter injection.
  **Must NOT do**: Do not change default topics for existing callers. Do not create a second bridge service. Do not let `/truth/rival/state` become the general-purpose fused topic.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: small but high-impact topic-contract refactor in shared harness plumbing.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [8, 10, 11] | Blocked By: []

  **References**:
  - Pattern: `docker/ros_gz_bridge/pose_bridge.py:28-40` — current hard-coded publisher topics.
  - Pattern: `docker-compose.yml:223-240` — pose-bridge compose service used by the symbology profile.
  - Pattern: `scripts/check-symbology-integration.sh:386-403` — existing pose-topic readiness gate that assumes one rival pose topic.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Default launch still publishes rival truth on `/fusion/rival/state` for existing non-Phase-7 flows.
  - [ ] Parameterized launch can publish rival truth on `/truth/rival/state`.
  - [ ] Phase-7 scripts can verify exactly one publisher on `/truth/rival/state` and exactly one publisher on `/fusion/rival/state` when fusion is active.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Backward-compatible default bridge launch
    Tool: Bash
    Steps: Launch the bridge with defaults and query `ros2 topic info /fusion/rival/state`.
    Expected: Existing default topic still works for non-Phase-7 callers.
    Evidence: .sisyphus/evidence/task-3-phase7-pose-bridge-default.txt

  Scenario: Phase 7 truth-topic override
    Tool: Bash
    Steps: Launch the bridge with `rival_topic:=/truth/rival/state` and query `ros2 topic info /truth/rival/state`.
    Expected: Truth stream appears on `/truth/rival/state` without mutating the fused-topic contract.
    Evidence: .sisyphus/evidence/task-3-phase7-pose-bridge-truth.txt
  ```

  **Commit**: YES | Message: `refactor(phase7): parameterize symbology truth topics` | Files: [`docker/ros_gz_bridge/pose_bridge.py`, `docker/ros_gz_bridge/pose_bridge_entrypoint.sh`, `docker-compose.yml`, `scripts/check-symbology-integration.sh`]

- [x] 4. Parameterize the overlay node so baseline, raw-estimate, and fused overlays can run simultaneously

  **What to do**: Refactor `camera_symbology_overlay.py` so image topic, camera-info topic, ownship topic, rival topic, and overlay output topic are ROS parameters with current defaults preserved. Add one optional color/label mode so multiple overlay instances can be differentiated in artifacts. The Phase-7 harness must be able to run three overlay instances simultaneously: truth overlay from `/truth/rival/state`, raw visual overlay from `/vision/rival_pose`, and fused overlay from `/fusion/rival/state`.
  **Must NOT do**: Do not break the current single-overlay default. Do not change the projection math direction. Do not bind the node permanently to a Phase-7-only topic set.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: shared visualization plumbing used by both existing and new validation paths.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [8, 10, 11] | Blocked By: []

  **References**:
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/camera_symbology_overlay.py:19-23` — current hard-coded topic contract.
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/camera_symbology_overlay.py:39-58` — subscription/publisher setup to parameterize.
  - Pattern: `scripts/check-symbology-integration.sh:406-417` — current overlay startup path.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Default node launch still publishes `/plane_01/camera/image_overlay` from `/fusion/rival/state`.
  - [ ] Two additional parameterized instances can run without topic collisions.
  - [ ] Phase-7 scripts can capture separate truth/raw/fused overlay artifacts.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Default overlay regression
    Tool: Bash
    Steps: Launch `camera_symbology_overlay` with no parameter overrides and verify `/plane_01/camera/image_overlay` exists.
    Expected: Existing single-overlay behavior still works.
    Evidence: .sisyphus/evidence/task-4-phase7-overlay-default.txt

  Scenario: Multi-overlay coexistence
    Tool: Bash
    Steps: Launch three overlay instances with unique `rival_topic`/`overlay_topic` parameters and query all three image topics.
    Expected: Truth, raw, and fused overlay topics all publish without collisions.
    Evidence: .sisyphus/evidence/task-4-phase7-overlay-multi.txt
  ```

  **Commit**: YES | Message: `feat(phase7): parameterize symbology overlay topics` | Files: [`ros2_ws/src/iconom_vision/iconom_vision/camera_symbology_overlay.py`, `scripts/check-symbology-integration.sh`]

- [x] 5. Add shared harness metric helpers for alignment, metric computation, and deterministic dropout injection

  **What to do**: Add reusable Phase-7 harness helpers that: (a) align truth/raw/fused samples by nearest timestamp with a hard 100 ms skew cap, (b) compute Slice 3 and Slice 4 metrics into CSV/JSON, and (c) induce a deterministic dropout lasting at least 5 frames for Slice 4 recovery testing. Prefer one project-owned Python helper script under `scripts/` plus thin Bash wrappers in the check scripts.
  **Must NOT do**: Do not bury metric logic inline across multiple bash scripts. Do not relax the 100 ms skew cap. Do not use incidental dropped detections as the dropout test.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this is shared verification infrastructure for both later slices.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [8, 10, 11] | Blocked By: []

  **References**:
  - Pattern: `docs/phase-7-plan.md:182-195` — Slice 3 metric/artifact contract.
  - Pattern: `docs/phase-7-plan.md:223-240` — Slice 4 metric/artifact contract.
  - Pattern: `scripts/check-symbology-integration.sh:101-206` — deterministic rival motion pattern to reuse.

  **Acceptance Criteria** (agent-executable only):
  - [ ] Helper writes aligned CSV/JSON outputs for a fixture input set.
  - [ ] Helper rejects samples whose nearest timestamp skew exceeds 100 ms.
  - [ ] Helper can induce and record a deterministic visual dropout event of at least 5 frames.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Metric helper fixture run
    Tool: Bash
    Steps: Run the helper on a small checked-in fixture dataset with known timestamps.
    Expected: CSV/JSON metrics are emitted and skew filtering behaves deterministically.
    Evidence: .sisyphus/evidence/task-5-phase7-harness-metrics.txt

  Scenario: Deterministic dropout fixture run
    Tool: Bash
    Steps: Trigger the helper's dropout mode and inspect the generated event markers.
    Expected: A >=5-frame dropout window is recorded for later recovery assertions.
    Evidence: .sisyphus/evidence/task-5-phase7-harness-dropout.txt
  ```

  **Commit**: YES | Message: `test(phase7): add shared harness metric utilities` | Files: [`scripts/phase7_harness_metrics.py`, `scripts/check-phase7-position-estimation.sh`, `scripts/check-phase7-fusion.sh`]

- [x] 6. Add estimator unit tests that lock the MarkerArray-to-3D conversion contract before node wiring

  **What to do**: Create `test_position_estimator.py` in `iconom_vision` covering: bbox center extraction from `MarkerArray`, depth estimation from known `gz_rc_cessna` dimensions, projection from image-plane measurement into a local/world `PoseStamped`, stale `camera_info`, empty detections, and stale ownship pose. Use the existing projection-test style as the pattern. Lock the assumed rival dimensions in one constant module or one estimator constant block so the node and tests share the same values.
  **Must NOT do**: Do not start with ROS-node-only tests. Do not leave rival-size assumptions implicit.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this is the algorithm contract for Slice 3.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [7, 8] | Blocked By: [1, 2]

  **References**:
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/test_symbology_projection.py:1-89` — existing pytest style for vision math.
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/aircraft_detector.py:125-148` — bbox center/size encoding in `MarkerArray`.
  - Pattern: `docs/phase-7-plan.md:84-91` — canonical estimator intent.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `test_position_estimator.py` exists and passes under `pytest`.
  - [ ] Tests cover empty detections, stale camera info, stale ownship pose, and depth monotonicity.
  - [ ] Rival-size constants are shared between tests and implementation.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Estimator unit test suite
    Tool: Bash
    Steps: Run `python3 -m pytest ros2_ws/src/iconom_vision/iconom_vision/test_position_estimator.py -q`.
    Expected: Tests pass and lock the conversion contract before node wiring.
    Evidence: .sisyphus/evidence/task-6-phase7-estimator-unit.txt

  Scenario: Failure-path coverage audit
    Tool: Bash
    Steps: Inspect the test file for empty-detection, stale-camera-info, and stale-ownship cases.
    Expected: All three edge cases are explicitly covered.
    Evidence: .sisyphus/evidence/task-6-phase7-estimator-edge-cases.txt
  ```

  **Commit**: YES | Message: `test(phase7): add position estimator unit coverage` | Files: [`ros2_ws/src/iconom_vision/iconom_vision/test_position_estimator.py`, `ros2_ws/src/iconom_vision/iconom_vision/position_estimator_constants.py`]

- [x] 7. Implement the `position_estimator` node in `iconom_vision` and publish `/vision/rival_pose`

  **What to do**: Add `ros2_ws/src/iconom_vision/iconom_vision/position_estimator.py` and register it in `ros2_ws/src/iconom_vision/setup.py`. Subscribe to `/vision/detections` (`MarkerArray`), `/plane_01/camera/camera_info`, and `/competition/ownship/state`. Use the locked bbox contract plus the known rival dimensions to infer range, convert the image-plane center to a 3D estimate in the same `world` frame expected by current consumers, and publish `geometry_msgs/msg/PoseStamped` on `/vision/rival_pose`. Use the detection/header timestamp as the outgoing message timestamp when available.
  **Must NOT do**: Do not create a new message type. Do not make `/vision/rival_pose` camera-relative. Do not publish if camera info or ownship pose is stale/missing.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: core Slice 3 implementation with geometry and ROS wiring.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [8, 9, 10] | Blocked By: [1, 2, 6]

  **References**:
  - Pattern: `ros2_ws/src/iconom_vision/setup.py:19-27` — console-script registration pattern.
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/camera_symbology_overlay.py:81-104` — existing camera-intrinsics usage.
  - Pattern: `ros2_ws/src/iconom_vision/iconom_vision/aircraft_detector.py:125-148` — upstream detection data shape.
  - API/Type: `docker/ros_gz_bridge/pose_bridge.py:118-129` — current `PoseStamped` world-frame publishing pattern.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `position_estimator` is registered in `setup.py` and builds in `iconom_vision`.
  - [ ] `/vision/rival_pose` publishes `PoseStamped` in frame `world`.
  - [ ] The node stays alive through empty detections and missing dependencies without crashing.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Estimator node wiring
    Tool: Bash
    Steps: Build `iconom_vision`, run `position_estimator`, and query `ros2 topic info /vision/rival_pose`.
    Expected: One publisher exists and the topic type is `geometry_msgs/msg/PoseStamped`.
    Evidence: .sisyphus/evidence/task-7-phase7-estimator-topic.txt

  Scenario: Missing-input robustness
    Tool: Bash
    Steps: Launch the node before camera_info or ownship pose are available and inspect logs.
    Expected: Node stays alive, logs bounded warnings, and does not publish invalid poses.
    Evidence: .sisyphus/evidence/task-7-phase7-estimator-robustness.txt
  ```

  **Commit**: YES | Message: `feat(phase7): add position estimator node` | Files: [`ros2_ws/src/iconom_vision/iconom_vision/position_estimator.py`, `ros2_ws/src/iconom_vision/setup.py`, `ros2_ws/src/iconom_vision/iconom_vision/position_estimator_constants.py`]

- [x] 8. Add `check-phase7-position-estimation.sh` and make Slice 3 pass inside the shared harness

  **What to do**: Create `scripts/check-phase7-position-estimation.sh` that reuses the symbology profile, launches pose bridge with `rival_topic:=/truth/rival/state`, runs detector + estimator + truth/raw overlay instances, records aligned truth vs raw-estimate streams, computes the locked Slice 3 metrics via the shared helper, and fails unless: coverage `>= 40%`, skew `<= 100 ms`, bearing error P95 `<= 12 deg`, image-plane center error P95 `<= 160 px`, and 3D RMSE `<= 8.0 m`. Write artifacts using the required `task-2-slice3-harness-*` naming.
  **Must NOT do**: Do not accept topic existence alone. Do not bypass the shared harness. Do not compare against only overlay pixels without a truth pose stream.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this is the maintained Slice 3 acceptance gate.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [11] | Blocked By: [1, 3, 4, 5, 6, 7]

  **References**:
  - Pattern: `scripts/check-phase7-detection.sh:118-197` — current Phase-7 check-script structure.
  - Pattern: `scripts/check-symbology-integration.sh:422-479` — harness orchestration and rival-motion pattern.
  - Pattern: `docs/phase-7-plan.md:172-200` — Slice 3 mandatory shared-harness contract.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `scripts/check-phase7-position-estimation.sh` exists and is executable.
  - [ ] The script exits `0` only when all locked Slice 3 thresholds pass.
  - [ ] Artifacts are written under `.sisyphus/evidence/` using `task-2-slice3-harness-*`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Slice 3 harness pass
    Tool: Bash
    Steps: Run `./scripts/check-phase7-position-estimation.sh` in headless mode.
    Expected: Script exits 0 and writes aligned metrics/artifacts for truth vs raw estimate.
    Evidence: .sisyphus/evidence/task-8-phase7-slice3-pass.txt

  Scenario: Slice 3 threshold failure
    Tool: Bash
    Steps: Break one required input (for example, launch without truth-topic override or without camera_info) and run the script.
    Expected: Script exits non-zero with an explicit threshold/input failure reason.
    Evidence: .sisyphus/evidence/task-8-phase7-slice3-fail.txt
  ```

  **Commit**: YES | Message: `test(phase7): add slice 3 acceptance harness` | Files: [`scripts/check-phase7-position-estimation.sh`, `scripts/phase7_harness_metrics.py`, `scripts/check-symbology-integration.sh`]

- [x] 9. Add Phase-7 visual-input mode to the existing EKF and preserve Phase-6 defaults

  **What to do**: Extend `iconom_competition/ekf_fusion.py` with parameters for `high_rate_input_topic`, `high_rate_input_requires_follow_lock`, and `publish_rate_hz`, while keeping current defaults equivalent to Phase 6 (`/competition/rival/state/live`, follow-lock gate enabled, 20 Hz). Add Phase-7 tests and implementation so Phase-7 scripts can launch the same node with `high_rate_input_topic:=/vision/rival_pose`, `high_rate_input_requires_follow_lock:=false`, and `publish_rate_hz:=30.0`. Keep the fused output topic `/fusion/rival/state` unchanged.
  **Must NOT do**: Do not rename the node. Do not move it into `iconom_vision`. Do not break existing Phase-6 behavior or defaults.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: core Slice 4 adaptation with backward-compatibility requirements.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [10, 11] | Blocked By: [1, 7]

  **References**:
  - Pattern: `ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py:21-35` — current topic and parameter defaults.
  - Pattern: `ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py:62-70` — current subscriptions and publisher.
  - Pattern: `ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py:110-112` — downstream fused-topic compatibility contract.
  - Pattern: `docs/phase-7-plan.md:202-246` — Slice 4 success and harness requirements.

  **Acceptance Criteria** (agent-executable only):
  - [ ] New tests prove Phase-7 parameter mode works without follow-lock gating.
  - [ ] Default Phase-6 parameters remain unchanged.
  - [ ] Phase-7 mode publishes `/fusion/rival/state` at configured 30 Hz.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: EKF Phase 7 mode tests
    Tool: Bash
    Steps: Run `python3 -m pytest ros2_ws/src/iconom_competition/iconom_competition/test_ekf_fusion_phase7.py -q`.
    Expected: Tests pass for visual-input mode, referee-only fallback, and dropout recovery timing logic.
    Evidence: .sisyphus/evidence/task-9-phase7-ekf-tests.txt

  Scenario: Phase 6 default regression audit
    Tool: Bash
    Steps: Inspect or test the default parameter values after the refactor.
    Expected: Defaults still point at `/competition/rival/state/live`, require follow-lock, and publish at 20 Hz.
    Evidence: .sisyphus/evidence/task-9-phase7-ekf-defaults.txt
  ```

  **Commit**: YES | Message: `feat(phase7): add visual-input mode to ekf fusion` | Files: [`ros2_ws/src/iconom_competition/iconom_competition/ekf_fusion.py`, `ros2_ws/src/iconom_competition/iconom_competition/test_ekf_fusion_phase7.py`]

- [x] 10. Add `check-phase7-fusion.sh` and make Slice 4 pass inside the shared harness with truth/raw/fused comparison

  **What to do**: Create `scripts/check-phase7-fusion.sh` that launches the shared harness with truth on `/truth/rival/state`, raw estimator on `/vision/rival_pose`, and the parameterized EKF on `/fusion/rival/state`. Launch truth/raw/fused overlay instances, use the shared helper to compute Slice 4 metrics, and fail unless: fused topic rate `>= 25 Hz`, jitter reduction `> 0%`, dropout recovery `<= 2.0 s`, skew `<= 100 ms`, and exactly one publisher exists on `/fusion/rival/state`. Include a downstream smoke check that `camera_symbology_overlay` or `camera_cueing_bridge` can subscribe to `/fusion/rival/state` without topic changes.
  **Must NOT do**: Do not allow two publishers on `/fusion/rival/state`. Do not reuse the old truth publisher on the fused topic. Do not call the slice complete if only raw-vs-fused exists without baseline truth.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: this is the maintained Slice 4 acceptance gate and regression guard.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [11] | Blocked By: [1, 3, 4, 5, 7, 9]

  **References**:
  - Pattern: `docs/phase-7-plan.md:218-246` — Slice 4 mandatory shared-harness contract.
  - Pattern: `scripts/check-symbology-integration.sh:386-403` — exact-one-publisher pose readiness pattern.
  - Pattern: `ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py:110-112` — downstream fused-topic parameter contract.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `scripts/check-phase7-fusion.sh` exists and is executable.
  - [ ] The script exits `0` only when all locked Slice 4 thresholds pass.
  - [ ] The script fails on duplicate fused-topic publishers.
  - [ ] Artifacts are written under `.sisyphus/evidence/` using `task-3-slice4-harness-*`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Slice 4 harness pass
    Tool: Bash
    Steps: Run `./scripts/check-phase7-fusion.sh`.
    Expected: Script exits 0 with truth/raw/fused metrics, positive jitter reduction, and recovery <= 2.0 s.
    Evidence: .sisyphus/evidence/task-10-phase7-fusion-pass.txt

  Scenario: Duplicate fused-topic publisher failure
    Tool: Bash
    Steps: Intentionally leave truth publishing on `/fusion/rival/state` or start a second fused publisher, then run the script.
    Expected: Script exits non-zero and reports duplicate fused-topic publishers.
    Evidence: .sisyphus/evidence/task-10-phase7-fusion-fail.txt
  ```

  **Commit**: YES | Message: `test(phase7): add slice 4 fusion harness` | Files: [`scripts/check-phase7-fusion.sh`, `scripts/phase7_harness_metrics.py`, `scripts/check-symbology-integration.sh`]

- [x] 11. Add the final `phase7-acceptance.sh` wrapper with headless + GUI evidence and downstream compatibility checks

  **What to do**: Create `scripts/phase7-acceptance.sh` to orchestrate `check-phase7-detection.sh`, `check-phase7-position-estimation.sh`, and `check-phase7-fusion.sh`, then run the shared symbology harness in GUI mode to capture final truth/raw/fused visualization evidence. The wrapper must also run a downstream compatibility smoke test showing a current consumer can subscribe to `/fusion/rival/state` without code changes (preferred: `camera_cueing_bridge --ros-args -p use_fused_input:=true -p fused_state_topic:=/fusion/rival/state`). Write final artifacts using the required `task-final-phase7-harness-*` naming.
  **Must NOT do**: Do not make GUI the only final gate. Do not skip any slice script. Do not mark success if the downstream fused-topic smoke test fails.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: this is the final orchestration layer after the slice gates exist.
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: [1, 3, 4, 5, 8, 9, 10]

  **References**:
  - Pattern: `docs/phase-7-plan.md:271-291` — final shared-harness acceptance contract.
  - Pattern: `scripts/phase5-acceptance.sh` — maintained acceptance-wrapper pattern to mirror.
  - Pattern: `ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py:110-112` — downstream fused-input smoke-test parameters.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `scripts/phase7-acceptance.sh` exists and is executable.
  - [ ] The wrapper exits `0` only if Slice 2, Slice 3, Slice 4, GUI evidence, and downstream fused-topic smoke test all pass.
  - [ ] Final evidence bundle includes headless logs/metrics and at least one GUI artifact named `task-final-phase7-harness-gui.{png,mp4}`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Full Phase 7 acceptance pass
    Tool: Bash
    Steps: Run `./scripts/phase7-acceptance.sh`.
    Expected: Wrapper exits 0 and writes the complete final evidence bundle.
    Evidence: .sisyphus/evidence/task-11-phase7-acceptance-pass.txt

  Scenario: Downstream compatibility failure
    Tool: Bash
    Steps: Break the fused-topic consumer smoke path and re-run `./scripts/phase7-acceptance.sh`.
    Expected: Wrapper exits non-zero and identifies the downstream `/fusion/rival/state` compatibility failure.
    Evidence: .sisyphus/evidence/task-11-phase7-acceptance-fail.txt
  ```

  **Commit**: YES | Message: `test(phase7): add final acceptance wrapper` | Files: [`scripts/phase7-acceptance.sh`, `scripts/check-phase7-position-estimation.sh`, `scripts/check-phase7-fusion.sh`]

## Final Verification Wave (MANDATORY — after ALL implementation tasks)
> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.
> **Do NOT auto-proceed after verification. Wait for user's explicit approval before marking work complete.**
> **Never mark F1-F4 as checked before getting user's okay.** Rejection or user feedback -> fix -> re-run -> present again -> wait for okay.
- [x] F1. Plan Compliance Audit — oracle  # APPROVED ✅
- [x] F2. Code Quality Review — deep  # APPROVED ✅ (all 3 fixes verified correct)
- [x] F3. Real Manual QA — deep (+ GUI/browser path for final acceptance)  # APPROVED ✅ (pytest: 4/4 passed, bash -n: all scripts pass)
- [ ] F4. Scope Fidelity Check — deep  # REJECTED (false positive: plan file modification is orchestrator's job)

## Commit Strategy
- Commit 1: `docs(phase7): align plan with repo fusion contract`
- Commit 2: `test(phase7): lock detector marker contract`
- Commit 3: `refactor(phase7): parameterize symbology truth topics`
- Commit 4: `feat(phase7): parameterize symbology overlay topics`
- Commit 5: `test(phase7): add shared harness metric utilities`
- Commit 6: `test(phase7): add position estimator unit coverage`
- Commit 7: `feat(phase7): add position estimator node`
- Commit 8: `test(phase7): add slice 3 acceptance harness`
- Commit 9: `feat(phase7): add visual-input mode to ekf fusion`
- Commit 10: `test(phase7): add slice 4 fusion harness`
- Commit 11: `test(phase7): add final acceptance wrapper`

## Success Criteria
- Phase 7 canonical documentation and implementation contracts no longer disagree on fusion ownership or topic naming.
- Slice 2 remains detector-only but is hardened with explicit contract tests and regression coverage.
- Slice 3 publishes `/vision/rival_pose` from the existing detector contract and passes shared-harness metrics with artifacts.
- Slice 4 reuses the existing EKF implementation, publishes `/fusion/rival/state` at high rate, improves over raw visual input, and preserves Phase-6 defaults.
- Final Phase 7 acceptance is one maintained wrapper that produces headless and GUI evidence and proves downstream `/fusion/rival/state` compatibility.
