# Phase 3 Plan

This document defines the next bounded phase after the tagged `phase2-runtime-separation`.

Phase 3 does not expand into multi-vehicle execution or full mission autonomy. Its job is to add the first honest single-vehicle fixed-wing guidance primitive on top of the now-stable separated runtime.

## Purpose

Phase 2 proved that the maintained single-vehicle runtime is stable:

- Gazebo owns the simulator runtime,
- PX4 attaches externally,
- camera topics reach ROS 2 through the maintained `ros_gz_bridge` service,
- telemetry reaches ROS 2,
- command and mode control work,
- offboard entry and bounded movement are validated,
- GUI and headless operator flows both work.

What is still missing is a higher-level fixed-wing guidance progression that is more meaningful than raw `body_rate + thrust`.

Phase 3 exists to add that first guidance layer without yet turning the project into a mission-planning or swarm problem.

## Phase 3 Goal

Add one maintained single-vehicle fixed-wing guidance primitive for `plane_01` and prove it with telemetry and an acceptance script.

Success means:

1. the project owns one higher-level guidance behavior above raw movement,
2. the behavior is observable in PX4 telemetry, not just command acknowledgements,
3. the behavior is scriptable and repeatable in headless mode,
4. the same behavior remains testable in GUI mode,
5. the work stays within one-aircraft scope.

## Phase 3 Scope

Phase 3 is limited to single-vehicle guidance primitives.

Included:

- one repo-owned autonomy/guidance node or control extension
- one bounded fixed-wing behavior
- telemetry-based success criteria
- documentation updates
- one acceptance check for the new behavior

Excluded:

- multi-vehicle execution
- swarm coordination
- full mission upload/execution flows
- QGroundControl-driven autonomy workflows
- dynamic obstacle avoidance
- perception-driven autonomy
- operator UI work beyond what is needed to observe the behavior

## Locked Phase 3 Contract

The following constraints stay fixed unless deliberately revised:

- Vehicle namespace remains `plane_01`
- PX4 model remains `gz_rc_cessna`
- ROS namespace remains `plane_01`
- Gazebo remains the maintained simulator owner
- `ros_gz_bridge` remains the maintained camera bridge service
- PX4 ROS topics remain under `/plane_01/fmu/in/...` and `/plane_01/fmu/out/...`
- Canonical entrypoints remain script-driven

## First Guidance Primitive

The first proven phase-3 primitive is PX4-native `NAV_TAKEOFF`.

Why this became the correct first step:

- it uses PX4 navigation semantics instead of raw movement control,
- it is bounded and telemetry-verifiable,
- it gets the aircraft into a meaningful guided flight state,
- it is a safer first proof than jumping directly into freer waypoint behavior from rest.

This does not replace later loiter or waypoint guidance. It establishes the first honest higher-level primitive above the phase-2 offboard movement layer.

## Recommended Technical Direction

The first implementation should prefer the highest-level PX4 contract that is still reliable in this fixed-wing SITL stack.

Phase 3 now selects this contract for the first guidance primitive:

- primary contract: PX4-native navigation-state command plus telemetry validation
- rejected for slice 1: raw `OFFBOARD` movement primitives as the main guidance abstraction

Reason:

- phase 2 already proved that raw `OFFBOARD` transport and bounded movement work,
- fixed-wing guidance should now move up one abstraction level,
- PX4-native navigation commands are more naturally aligned with fixed-wing guidance than ad hoc `body_rate + thrust` control,
- this keeps the first autonomy slice closer to aircraft guidance and farther from manual low-level actuation.

The first phase-3 slice should therefore build on mode/navigation semantics first, and only fall back to deeper `OFFBOARD` control if PX4-native guidance proves insufficient for the bounded target behavior.

## Contract Decision

The first fixed-wing guidance primitive will use this contract:

1. enter a suitable navigation state through the existing `VehicleCommand` path,
2. publish or configure one bounded target behavior at the guidance layer,
3. validate success through PX4 telemetry rather than through command ack alone.

The first target behavior is now:

- one bounded `NAV_TAKEOFF` behavior for `plane_01`

The success signal should be telemetry-based, for example:

- `VehicleCommandAck` accepted for the PX4-native navigation command,
- `VehicleStatus.nav_state=AUTO_TAKEOFF`,
- meaningful `VehicleLocalPosition` climb and movement after the command.

## Implementation Order

### Slice 1: Guidance Contract Selection

Choose the exact control contract for the first higher-level behavior.

Completed result:

- one documented control contract is selected,
- deeper `OFFBOARD` control is explicitly rejected as the primary phase-3 abstraction,
- the first primitive is pinned to bounded fixed-wing guidance.

### Slice 2: First Guidance Node

Implement the first repo-owned single-vehicle guidance node.

Success:

- one node publishes the required commands or setpoints,
- one bounded target behavior is encoded,
- the node is runnable from the maintained stack.

Current result:

- `iconom_control.navigation_command_client` exists,
- it supports `nav_takeoff` as the first maintained PX4-native guidance command,
- it seeds its target from live `VehicleGlobalPosition` telemetry.

### Slice 3: Telemetry Proof

Validate the behavior through PX4 telemetry.

Success:

- success is defined in terms of `VehicleStatus`, `VehicleLocalPosition`, or another pinned PX4 topic,
- the behavior can be distinguished from raw movement.

Current result:

- [check-nav-takeoff.sh](../scripts/check-nav-takeoff.sh) proves headless `NAV_TAKEOFF`,
- PX4 accepts the command,
- `VehicleStatus` enters `AUTO_TAKEOFF`,
- `VehicleLocalPosition` shows real takeoff motion.

### Slice 4: Acceptance and GUI Confirmation

Add the maintained validation path for the primitive.

Success:

- one headless acceptance script passes,
- the same behavior can be observed in the GUI path.

Current result:

- [phase3-acceptance.sh](../scripts/phase3-acceptance.sh) exists as the maintained phase-3 validation entrypoint,
- [check-nav-takeoff.sh](../scripts/check-nav-takeoff.sh) passes headless,
- [check-nav-takeoff.sh](../scripts/check-nav-takeoff.sh) also passes in GUI mode.

## Acceptance Criteria

Phase 3 is complete when all of the following are true:

- one bounded single-vehicle guidance primitive is implemented,
- the primitive is owned by this repo,
- the primitive is validated through PX4 telemetry,
- the primitive has a maintained acceptance script,
- the primitive can be observed in the GUI runtime,
- the work does not introduce multi-vehicle assumptions.

The current maintained phase-3 slice satisfies these criteria for a bounded airborne guidance chain: `NAV_TAKEOFF`, in-flight `AUTO_LOITER`, and a truthful `AUTO_LAND` closure.

## Risks

- fixed-wing PX4 guidance semantics may not align cleanly with the current offboard-control pattern,
- some behaviors that look simple for multicopters may be poor first targets for fixed-wing SITL,
- telemetry may prove command transport but not true path-following quality unless the success metric is chosen carefully.

- `NAV_TAKEOFF` is a meaningful first guidance step, but it is still only the start of fixed-wing autonomy and not yet waypoint convergence or route following.

These are why phase 3 should stay narrow and prove one guidance primitive well before expanding scope.

## Deliverables

Phase-3 completion should leave the repo with:

- one phase-3 guidance node or control extension
- one validation script for the new primitive
- updated documentation
- one clear success metric for the behavior

The next likely increment after this closed phase-3 slice is mission-style target sequencing or more explicit route-following, not a return to raw offboard movement as the main abstraction.

## Current Increment

The current closing increment is auto landing after airborne guidance.

This closes the first bounded `NAV_TAKEOFF` primitive without expanding into full mission machinery:

- the aircraft first enters a meaningful PX4-native takeoff state,
- then transitions into PX4-native loiter guidance while airborne,
- route and reposition proofs remain available as intermediate guidance slices,
- then `NAV_LAND` closes the flight loop with telemetry-based descent and touchdown proof.

Current result:

- [check-nav-loiter.sh](../scripts/check-nav-loiter.sh) exists,
- it proves `NAV_TAKEOFF` followed by an in-flight `mode_loiter` request,
- it requires `VehicleStatus.nav_state=AUTO_LOITER`,
- it verifies continued `VehicleLocalPosition` motion while loiter remains active,
- [check-nav-reposition.sh](../scripts/check-nav-reposition.sh) exists,
- it proves `NAV_TAKEOFF` followed by in-flight `mode_loiter` and `DO_REPOSITION`,
- it requires `VehicleStatus.nav_state=AUTO_LOITER`,
- it verifies that `VehicleGlobalPosition` approaches the commanded reposition target,
- [check-nav-route.sh](../scripts/check-nav-route.sh) exists,
- it proves `NAV_TAKEOFF` followed by in-flight `mode_loiter` and two sequential `DO_REPOSITION` targets,
- it requires `VehicleStatus.nav_state=AUTO_LOITER`,
- it verifies that `VehicleGlobalPosition` approaches both commanded route points,
- [check-nav-land.sh](../scripts/check-nav-land.sh) exists,
- it proves `NAV_TAKEOFF` followed by in-flight `mode_loiter` and `NAV_LAND`,
- it requires `VehicleStatus.nav_state=AUTO_LAND`,
- it verifies landing descent in `VehicleLocalPosition`,
- it waits for `VehicleLandDetected.landed=true`,
- [phase3-acceptance.sh](../scripts/phase3-acceptance.sh) now uses the landing slice as the maintained phase-3 validation entrypoint.

## Initial Next Step

The first concrete phase-3 task should be:

- implement the first bounded fixed-wing guidance primitive on top of the selected navigation/guidance contract.
