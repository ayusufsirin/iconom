# Phase 6 Plan

This document defines the next bounded phase after the validated phase-5 server-aware substrate.

Phase 6 does not implement visual lock scoring, round emulation, or hardware-facing behavior. Its job is to turn the maintained server/history/prediction outputs into bounded aircraft guidance that can cue a rival into the forward camera view.

## Purpose

Phase 5 proved that the maintained stack can:

- talk to a deterministic referee server,
- publish ownship telemetry from the simulator,
- ingest rival state from referee responses,
- accumulate rival history,
- publish a bounded short-horizon prediction,
- validate the whole path through a maintained headless acceptance script.

What is still unproven is whether that server-aware rival state can drive the aircraft in a deterministic and reviewable way.

Phase 6 exists to prove pursuit guidance first. It does not yet try to detect, track, or score a target lock from the camera stream.

## Phase 6 Goal

Add one maintained pursuit layer that selects a rival, plans a bounded intercept/cueing action, and drives one aircraft so the target can be brought into the forward camera field of view.

Success means:

1. one rival can be selected deterministically from the maintained phase-5 outputs,
2. a bounded intercept target can be computed from buffered and predicted rival state,
3. one pursuit state machine can command the aircraft through search/pursue/reacquire-style transitions,
4. the aircraft response remains scriptable and repeatable in headless mode,
5. the same cueing behavior can still be observed in GUI mode,
6. the proof stays separate from visual lock evaluation.

## Phase 6 Scope

Phase 6 is limited to pursuit guidance and camera cueing for one ownship aircraft.

Included:

- deterministic target selection from maintained rival state
- bounded intercept planning from history and prediction
- one repo-owned pursuit state machine
- one camera-cueing validation path
- acceptance-first validation for the whole phase-6 guidance path

Excluded:

- detection from raw camera images
- visual tracker implementation
- autonomous lock scoring
- round management or scoring
- multi-ownship coordination
- hardware/HIL
- kamikaze behavior

## Locked Phase 6 Contract

The following constraints stay fixed unless deliberately revised:

- the maintained ownship remains `plane_01`
- the maintained rival data source remains the phase-5 referee/client/history/predictor path
- the maintained camera remains the forward camera already exposed under `/plane_01/camera/...`
- guidance must stay script-driven and acceptance-first
- phase 6 may command the aircraft, but it must not embed lock-scoring logic
- headless validation remains required even when GUI confirmation is added

## Guidance Contract

Phase 6 should preserve this exact split of responsibilities:

- target selection chooses which rival identity to pursue
- intercept planning converts rival history and prediction into a bounded guidance target
- pursuit state owns mode transitions and command sequencing
- camera cueing validation proves the rival can be brought into the nose-camera view

Shared rules:

- selection, planning, and pursuit must stay inspectable as separate steps
- the first maintained target-selection policy must be deterministic and simple
- the first intercept planner must be bounded and reviewable, not optimization-heavy
- the first cueing proof should use one scripted encounter, not a free-form dogfight

## Recommended Technical Direction

Phase 6 should prefer deterministic heuristics and explicit state transitions over ambitious autonomy logic.

That means:

- start with one simple rival-selection rule,
- start with one short-horizon intercept target derived from the maintained predictor,
- use one explicit pursuit state machine with small states and clear transitions,
- prove that the target enters the camera view before attempting any visual tracking.

Reason:

- phase 5 already proved the data substrate,
- the next risk is not data availability but uncontrolled guidance complexity,
- bounded heuristics are easier to validate and easier to replace later than one opaque pursuit controller.

## Implementation Order

### Slice 1: Phase 6 Baseline Plan

Pin the exact guidance boundaries, package/script names, and acceptance goal for pursuit cueing.

Success:

- one source-of-truth document exists,
- phase 6 has explicit scope and exclusions,
- no pursuit implementation starts before the plan is pinned.

### Slice 2: Target Selection Policy

Add one deterministic selector on top of the maintained phase-5 rival outputs.

Success:

- one rival identity is chosen deterministically from controlled inputs,
- one maintained check proves the expected rival is selected,
- no aircraft guidance is emitted yet.

### Slice 3: Intercept Planner

Add one bounded planner that converts the selected rival state into a guidance target.

Success:

- one intercept target is produced from maintained history/prediction inputs,
- the output is explicit enough to inspect in logs or topics,
- one maintained check proves the planner reacts correctly to controlled rival motion.

### Slice 4: Pursuit State Machine

Add one repo-owned pursuit state machine for the maintained ownship.

Success:

- the state machine exposes explicit pursuit states,
- state transitions are deterministic under controlled inputs,
- the state machine can emit bounded command intents without visual logic.

### Slice 5: First Aircraft Cueing

Drive the maintained ownship with the pursuit layer so the rival is cued toward the forward camera view.

Success:

- one scripted encounter runs end to end,
- the ownship responds to pursuit output,
- the target is brought into the forward camera view in a measurable way.

### Slice 6: Acceptance And GUI Confirmation

Add the maintained validation path for the bounded pursuit/cueing baseline.

Success:

- one headless acceptance script proves the maintained phase-6 path,
- one GUI confirmation path shows the cueing behavior,
- the work still stops short of visual lock evaluation.

## Acceptance Criteria

Phase 6 is complete when all of the following are true:

- one deterministic target-selection rule is implemented and validated,
- one bounded intercept planner is implemented and validated,
- one pursuit state machine is implemented and validated,
- one maintained cueing check proves the rival can be brought into the forward camera view,
- one maintained phase-6 acceptance entrypoint passes in headless mode,
- the same cueing behavior can be confirmed in GUI mode,
- no visual lock evaluation is required to make the phase pass.

## Out Of Scope For Phase 6

The following topics belong to later phases and should not be pulled into early phase 6 slices:

- object detection from camera frames
- visual multi-frame tracking
- lock rectangle scoring
- lock packet publishing
- round-clock logic, penalties, or scoring
- coordinated multi-ownship pursuit
- hardware deployment

## Proposed Repo Additions

Phase 6 should likely add files in this shape:

- `docs/phase-6-plan.md`
- `scripts/check-phase6-target-selection.sh`
- `scripts/check-phase6-intercept-planner.sh`
- `scripts/check-phase6-pursuit-state-machine.sh`
- `scripts/check-phase6-camera-cueing.sh`
- `scripts/phase6-acceptance.sh`
- `ros2_ws/src/iconom_guidance/`

Custom message packages should be avoided unless the existing ROS and PX4 message contracts become a real blocker.

## First Step After This Plan

The first implementation step after this document should be the deterministic target-selection slice.

That slice should:

- choose one rival from maintained controlled inputs,
- expose the result in one inspectable way,
- add one maintained check script,
- avoid commanding the aircraft yet.
