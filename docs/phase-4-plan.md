# Phase 4 Plan

This document defines the next bounded phase after the tagged `phase3-guidance-loop`.

Phase 4 does not expand into swarm coordination or operator UX. Its job is to prove that the maintained stack can host a second fixed-wing aircraft without topic, port, or identity collisions.

## Purpose

Phase 3 proved that one aircraft can complete a bounded guided flight loop:

- the separated runtime is stable,
- PX4 telemetry reaches ROS 2,
- the camera path reaches ROS 2,
- command, mode, and offboard control work,
- PX4-native guidance can take off, loiter, reposition, route, and land,
- GUI and headless flows both work.

What is still unproven is whether the stack scales from one aircraft to two without collapsing the naming and transport contract.

Phase 4 exists to validate multi-vehicle coexistence first. It does not yet try to coordinate the vehicles.

## Phase 4 Goal

Add `plane_02` to the maintained simulator stack and prove that `plane_01` and `plane_02` can coexist with clean isolation.

Success means:

1. both aircraft start in the same maintained runtime,
2. each aircraft has unique transport identity and ports,
3. each aircraft exposes isolated ROS telemetry and camera topics,
4. one aircraft can be commanded without affecting the other,
5. the proof is scriptable and repeatable in headless mode,
6. the same coexistence can still be observed in GUI mode.

## Phase 4 Scope

Phase 4 is limited to a dual-aircraft baseline and isolation proof.

Included:

- one second PX4 instance for `plane_02`
- one second camera contract for `plane_02`
- isolated ROS namespaces and topic roots
- isolated MAVLink port assignments
- isolated XRCE keys
- acceptance-first validation for dual-aircraft coexistence

Excluded:

- swarm coordination
- formation flight
- centralized mission planning across vehicles
- collision avoidance
- operator UI work beyond what is needed to observe both aircraft
- more than two aircraft

## Locked Phase 4 Contract

The following constraints stay fixed unless deliberately revised:

- vehicle namespaces are `plane_01` and `plane_02`
- PX4 model remains `gz_rc_cessna` for both aircraft
- Gazebo remains the maintained simulator owner
- one shared `Micro XRCE-DDS Agent` remains the maintained XRCE topology
- MAVLink port allocation remains sequential from the existing base
- ROS topics remain namespaced per aircraft under `/plane_XX/fmu/in/...` and `/plane_XX/fmu/out/...`
- camera topics remain namespaced per aircraft under `/plane_XX/camera/...`
- canonical entrypoints remain script-driven

## Identity And Addressing Contract

Phase 4 should implement and preserve this exact dual-aircraft contract:

- `plane_01`
  - PX4 system id: `1`
  - XRCE key: `1`
  - MAVLink offboard UDP port: `14540`
  - Gazebo model name: `rc_cessna_0`
- `plane_02`
  - PX4 system id: `2`
  - XRCE key: `2`
  - MAVLink offboard UDP port: `14541`
  - Gazebo model name: `rc_cessna_1`

Shared rules:

- GCS port remains the maintained shared QGC-facing port `14550`
- XRCE agent stays on UDP `8888`
- ROS namespace roots stay `plane_01` and `plane_02`
- camera topics must be separate for both aircraft
- frame ids must not collide across aircraft

## Recommended Technical Direction

Phase 4 should prefer duplication with explicit isolation over abstraction-first refactors.

That means:

- add the second vehicle with explicit env and script wiring first,
- prove the addressing contract end to end,
- only then consider deduplicating repeated runtime logic.

Reason:

- the repo currently has many truthful `plane_01` assumptions,
- premature generalization will hide collisions instead of exposing them,
- dual-aircraft success depends more on clean isolation than on elegant abstraction.

## Implementation Order

### Slice 1: Dual-Aircraft Contract Baseline

Pin the exact naming, ID, port, and topic rules for `plane_02`.

Success:

- one source-of-truth document exists,
- the repo has one explicit dual-aircraft contract,
- no implementation starts before the contract is pinned.

### Slice 2: Runtime Bring-Up

Add the second PX4 instance and second bridge/camera contract to the maintained runtime.

Success:

- both aircraft start in one world,
- both PX4 instances attach to Gazebo,
- both aircraft have unique runtime identity.

### Slice 3: Telemetry And Camera Isolation

Prove that both aircraft publish isolated telemetry and camera topics.

Success:

- ROS discovers `/plane_01/fmu/out/...` and `/plane_02/fmu/out/...`,
- ROS discovers `/plane_01/camera/...` and `/plane_02/camera/...`,
- no topic collisions are needed to make the proof pass.

### Slice 4: Command Isolation

Prove that commands can target one aircraft without mutating the other.

Success:

- `plane_01` can be armed independently,
- `plane_02` can be armed independently,
- a mode or nav action on one aircraft leaves the other aircraft unchanged.

### Slice 5: Mode Isolation

Prove that one aircraft can change mode without mutating the other.

Success:

- `plane_01` can enter `OFFBOARD` independently,
- `plane_02` stays outside `OFFBOARD` until explicitly targeted,
- `plane_02` can then enter `OFFBOARD` independently while `plane_01` stays unchanged.

### Slice 6: Acceptance And GUI Confirmation

Add the maintained validation path for the dual-aircraft baseline.

Success:

- one headless acceptance script proves dual-aircraft coexistence,
- the same coexistence can be observed in GUI mode,
- the work still avoids swarm coordination logic.

## Acceptance Criteria

Phase 4 is complete when all of the following are true:

- two aircraft run in one maintained stack,
- each aircraft has unique PX4 identity and transport addressing,
- each aircraft exposes isolated telemetry topics,
- each aircraft exposes isolated camera topics,
- commands can target one aircraft independently,
- one maintained acceptance script proves the dual-aircraft baseline,
- the same baseline is observable in the GUI runtime.

## Risks

- the current repo encodes many `plane_01` assumptions that must be surfaced deliberately,
- Gazebo model naming and camera-frame naming may collide even when ROS namespaces do not,
- MAVLink and XRCE isolation may look correct in env files while still colliding at runtime,
- multi-vehicle support may pressure the repo toward premature refactoring.

These are why phase 4 should stop at dual-aircraft coexistence and not expand into swarm behavior yet.

## Deliverables

Phase-4 completion should leave the repo with:

- one maintained dual-aircraft runtime path
- one maintained dual-aircraft acceptance script
- updated documentation for the two-aircraft contract
- isolated telemetry, camera, command, and mode proofs for both aircraft

The next likely increment after this closed phase-4 slice is the first bounded multi-vehicle coordination layer, not a larger uncontrolled expansion of vehicle count.

## Initial Next Step

The first concrete phase-4 task should be:

- update the repo runtime contract so `plane_02` has an explicit namespace, XRCE key, system id, MAVLink port, Gazebo model name, and camera topic root before any dual-aircraft launch work begins.
