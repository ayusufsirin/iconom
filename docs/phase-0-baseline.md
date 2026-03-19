# Phase 0 Baseline

## Purpose

This document freezes the initial project boundaries for the first implementation phase. Its job is to remove ambiguity before any worker agent starts changing files.

Phase 0 does not aim to solve the whole project. It only defines the first build target, the integration boundaries, and the safety constraints for future automation.

## Project Goal

Build a Docker-based simulation environment for a PX4 fixed-wing vehicle in Gazebo with:

- a forward camera available in ROS 2,
- PX4 telemetry visible in ROS 2,
- a minimal ROS-to-PX4 command path,
- a later expansion path toward multi-vehicle swarm simulation.

## Phase 1 Target

Phase 1 is intentionally narrow. Success means:

1. one PX4 SITL fixed-wing instance starts reliably,
2. one Gazebo world starts reliably,
3. one forward-facing camera publishes into ROS 2,
4. one ROS 2 node can observe PX4 telemetry,
5. one minimal command path from ROS 2 to PX4 is validated,
6. the above can run through a repeatable smoke test.

Anything beyond that is deferred.

## Locked Decisions

The following decisions are accepted for now and should be treated as the default project contract.

### Runtime Stack

- Host execution style: Docker Compose on Linux
- Container base OS: Ubuntu 22.04
- Autopilot: PX4-Autopilot `v1.16.0` in SITL mode
- ROS distribution: ROS 2 Humble
- Simulator: Gazebo Harmonic
- Ground-control side channel: MAVLink retained for QGroundControl, debugging, and fallback tooling

These pins are based on current official PX4, ROS, and Gazebo documentation as of `2026-03-19`.

Gazebo Harmonic with ROS 2 Humble is being chosen intentionally. It is a supported PX4 path, but it is not Gazebo's default ROS pairing, so it carries some integration risk around package and bridge setup.

### Integration Boundaries

- Primary PX4-to-ROS integration path: `uXRCE-DDS`
- Primary Gazebo-to-ROS sensor path: `ros_gz_bridge`
- Camera data must not be routed through PX4
- ROS nodes must use simulation time

### Development Strategy

- Single vehicle before multi-vehicle
- Existing PX4 fixed-wing model before custom airframe work
- Documentation and guardrails before implementation
- Agent work must be scoped to narrow, reviewable tasks

### Phase 1 Base Model

- Phase-1 base airframe: PX4 `gz_rc_cessna`

This is the standard fixed-wing model documented in PX4 `v1.16` and is also used in PX4's multi-vehicle Gazebo + ROS 2 example, which makes it the safest starting point for future swarm work.

`gz_advanced_plane` is intentionally deferred until after the baseline stack is working because it adds lift-model complexity that is not needed for phase 1.

## Control Contract for Phase 1

The phrase "ROS can command the plane" is too vague for implementation, so phase 1 uses a restricted control contract.

Phase-1 command primitive: a ROS 2 `VehicleCommand` roundtrip through the PX4 `uXRCE-DDS` path, with acknowledgement verification.

Phase-1 command validation means:

- ROS 2 can connect to PX4 through the selected bridge path,
- ROS 2 can receive the telemetry required to prove the link is alive,
- ROS 2 can deliver a mode or arm class `VehicleCommand`,
- ROS 2 can verify the corresponding acknowledgement.

Phase 1 does not include:

- full mission logic,
- formation control,
- fixed-wing trajectory control,
- offboard flight behavior,
- arbitrary actuator-level experimentation,
- swarm coordination.

This is deliberate. In PX4 `v1.16`, the documented ROS 2 control examples are centered on `VehicleCommand` and multicopter-style offboard flows, while the more explicit fixed-wing ROS 2 control interface comes later. Phase 1 should not depend on fixed-wing offboard semantics.

## Naming and Port Conventions

Phase-1 single-vehicle namespace: `plane_01`

Future multi-vehicle pattern: `plane_01`, `plane_02`, `plane_03`, ...

PX4 ROS topics must be namespaced through `PX4_UXRCE_DDS_NS`, producing topic paths such as `/plane_01/fmu/in/...` and `/plane_01/fmu/out/...`.

Gazebo sensor topics and camera frames must use the same vehicle namespace prefix.

MAVLink offboard API ports follow PX4's sequential multi-vehicle convention starting at `14540`, while GCS traffic remains on `14550`.

The shared Micro XRCE-DDS Agent listens on UDP `8888` for all simulated vehicles in this project.

These choices align with PX4 multi-vehicle conventions while using a project-specific namespace instead of the default `px4_N` pattern.

## Swarm Rules to Preserve From Day One

Even though phase 1 is single-vehicle, the layout must not block later multi-vehicle work.

Every future vehicle instance must have:

- a unique PX4 instance identity,
- a unique ROS namespace,
- a unique MAVLink port allocation,
- a unique camera topic namespace,
- a deterministic frame naming scheme,
- a deterministic mapping strategy for DDS and launch configuration.

This means phase-1 naming should already be namespace-friendly.

## CI Philosophy

The first CI target is a smoke test, not a full autonomy test.

The smoke test should prove only:

1. containers start,
2. PX4 SITL starts,
3. Gazebo starts,
4. bridge services start,
5. ROS 2 can see the expected camera topic,
6. ROS 2 can see the expected PX4 telemetry path.

If command validation is included in CI, it should be limited to one deterministic check.

## Agent Safety Boundaries

Future coding agents should not be allowed to redefine the architecture ad hoc. Before agent automation is enabled, the repo should contain:

- `AGENTS.md` with repository rules,
- a task template with acceptance criteria,
- a clear list of editable paths per task,
- a merge policy,
- a smoke-test command that acts as the primary gate.

Until the stack is stable, infrastructure files should be treated as high-risk:

- Dockerfiles
- Compose files
- CI workflows
- bridge configuration
- networking and port assignments
- simulator launch configuration

These should require deliberate review even if an agent prepares the patch.

## Open Decisions That Must Be Resolved Next

The following items are intentionally left open, but must be resolved before phase-1 implementation:

1. Exact Gazebo Harmonic installation and image strategy
2. Exact `uXRCE-DDS` topology for future multi-vehicle expansion
3. Exact remote CI runner model and smoke-test execution shape

## Proposed Repository Shape

This is the intended initial layout once implementation starts:

```text
iconom/
  docs/
  docker/
  sim/
  ros2_ws/
  scripts/
  .github/workflows/
```

Phase 0 does not require all of these directories to exist yet. They are listed to make future task scopes explicit.

## Source of This Baseline

This baseline was derived from the earlier architecture discussion captured in:

- [ChatGPT-Gazebo_PX4_FPV_Setup.md](../ChatGPT-Gazebo_PX4_FPV_Setup.md)

If that discussion and this document conflict, this document should be treated as the current working source of truth until updated.
