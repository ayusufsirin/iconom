# Phase 2 Plan

This document defines the next bounded phase after the tagged `phase1-baseline`.

Phase 2 did not expand into swarm behavior or mission autonomy. Its job was to replace the transitional phase-1 runtime shape with a cleaner, separable simulator architecture while keeping the phase-1 single-vehicle contract intact.

## Purpose

Phase 1 proved that the single-vehicle stack works:

- PX4 starts,
- Gazebo runs,
- camera topics reach ROS 2,
- telemetry reaches ROS 2,
- ROS commands reach PX4,
- offboard entry and first movement are validated.

At the start of phase 2, the runtime still had one major architectural compromise:

- PX4 launches Gazebo from inside the `px4` container.

Phase 2 existed to remove that compromise.

## Phase 2 Goal

Promote the standalone `gazebo` service from a local utility into the real simulator backend for the maintained single-vehicle stack.

Completed result:

1. `gazebo` becomes the actual simulator process for the maintained one-vehicle runtime,
2. `px4` connects to that external Gazebo runtime rather than spawning its own,
3. the `plane_01` namespace, camera topics, telemetry topics, and control topics remain stable,
4. the existing phase-1 validation slices still pass with only intentional updates,
5. the GUI and headless operator flows continue to work through the canonical entrypoints.

## Phase 2 Scope

Phase 2 is limited to single-vehicle runtime separation.

Included:

- external Gazebo runtime ownership in the `gazebo` service
- PX4-to-Gazebo connection changes needed for that split
- camera bridge continuity
- telemetry continuity
- command/mode/offboard continuity
- launch and acceptance updates required by the new runtime shape
- operator-visible documentation updates

Excluded:

- multi-vehicle execution
- new aircraft models
- waypoint or mission autonomy
- swarm control
- QGroundControl workflows as a primary milestone
- perception algorithms beyond the current camera consumer

## Locked Phase 2 Contract

The following constraints stay fixed unless deliberately revised:

- Vehicle namespace remains `plane_01`
- PX4 model remains `gz_rc_cessna`
- ROS namespace remains `plane_01`
- XRCE topology remains one shared `MicroXRCEAgent`
- Camera ROS topics remain `/plane_01/camera/image_raw` and `/plane_01/camera/camera_info`
- PX4 ROS topics remain under `/plane_01/fmu/in/...` and `/plane_01/fmu/out/...`
- Canonical user entrypoints remain script-driven rather than raw `docker compose` commands

## Main Technical Change

Phase 1 uses a transitional runtime:

- `px4` starts Gazebo internally,
- `ros_gz_bridge` joins that live PX4 runtime network namespace to see Gazebo topics.

Phase 2 target:

- `gazebo` owns the simulator runtime,
- `px4` joins an already-running Gazebo world in standalone mode,
- `ros_gz_bridge` can connect through the maintained Compose network without container-namespace tricks.

That change was the core of phase 2 and is now the maintained runtime shape.

## Implemented Slices

### Slice 1: External Gazebo Ownership
- `gazebo` is the maintained runtime owner for the single-vehicle stack.
- one maintained launch path starts `gazebo` first.
- PX4 no longer spawns Gazebo internally in the maintained path.

### Slice 2: PX4 External-Gazebo Attachment
- PX4 joins the external Gazebo runtime cleanly.
- the `gz_rc_cessna` model attaches deterministically.
- the maintained single-vehicle bring-up reaches `pxh>`.

### Slice 3: Camera and Bridge Reconciliation
- Gazebo camera topics are discovered under the separated runtime.
- a maintained long-running `ros_gz_bridge` service now owns the camera bridge path.
- ROS 2 still receives `/plane_01/camera/image_raw`.
- the camera subscriber still receives frames.

### Slice 4: Control Regression Pass
- telemetry check passes,
- command check passes,
- mode check passes,
- offboard readiness passes,
- offboard movement passes.

### Slice 5: Entry Point Cleanup
- `scripts/phase1-launch.sh` works against the separated runtime.
- `scripts/phase1-acceptance.sh` passes against the separated runtime.
- GUI and headless modes remain explicit and honest.

## Acceptance Criteria

Phase 2 is complete and the following are now true:

- one canonical headless operator path uses external Gazebo service ownership,
- one canonical GUI operator path uses external Gazebo service ownership,
- the current single-vehicle validation set still passes,
- the camera consumer still receives frames,
- PX4 no longer needs to launch Gazebo from inside the `px4` container in the maintained path,
- the transitional phase-1 runtime is demoted and no longer described as the maintained path.

## Risks

- PX4 standalone Gazebo attachment may differ from the currently proven internal launch path in subtle ways.
- Camera-topic names may shift when the runtime ownership changes.
- Offboard timing may regress if world startup order changes.
- GUI/headless behavior may diverge if the `gazebo` service is not kept profile-safe.

These are precisely why phase 2 should stay limited to runtime separation and not add new autonomy goals at the same time.

## Deliverables

Phase-2 completion should leave the repo with:

- updated runtime scripts
- updated acceptance scripts
- updated Compose wiring
- updated documentation for the maintained single-vehicle flow
- removal or demotion of the old PX4-internal Gazebo path

## Next Step

The next bounded step after phase 2 should be one of:

- multi-vehicle planning and naming/port/runtime design, or
- higher-level autonomy work on top of the now-stable single-vehicle separated runtime.
