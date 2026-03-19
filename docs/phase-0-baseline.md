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
- Autopilot: PX4 SITL
- ROS distribution: ROS 2 Humble
- Simulator: Gazebo Harmonic
- Ground-control side channel: MAVLink retained for QGroundControl, debugging, and fallback tooling

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

## Control Contract for Phase 1

The phrase "ROS can command the plane" is too vague for implementation, so phase 1 uses a restricted control contract.

Phase-1 command validation means:

- ROS 2 can connect to PX4 through the selected bridge path,
- ROS 2 can receive the telemetry required to prove the link is alive,
- ROS 2 can issue one minimal, preselected command path that is simple to test repeatedly.

Phase 1 does not include:

- full mission logic,
- formation control,
- advanced offboard behaviors,
- arbitrary actuator-level experimentation,
- swarm coordination.

The exact command primitive still needs to be chosen deliberately before implementation starts.

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

1. Exact PX4 version pin
2. Exact Gazebo Harmonic installation and image strategy
3. Exact base fixed-wing model to extend
4. Exact phase-1 command primitive
5. Exact topic, namespace, frame, and port naming convention
6. Exact `uXRCE-DDS` topology for future multi-vehicle expansion
7. Exact remote CI runner model and smoke-test execution shape

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
