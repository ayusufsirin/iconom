# Phase 1 Integration

This document defines the first honest single-vehicle integration baseline.

## Canonical Contract

- Vehicle namespace: `plane_01`
- PX4 ROS namespace: `plane_01`
- PX4 model contract: `gz_rc_cessna`
- Gazebo world contract: `sim/worlds/empty.sdf`
- Integrated service set: `xrce_agent`, `gazebo`, `ros2_app`, `px4`

## What Is Wired

- The four containers can be built and started together under one `plane_01` contract.
- `px4` and `ros2_app` depend on `xrce_agent` and `gazebo` in the canonical compose stack.
- `scripts/integration-single-vehicle.sh` validates the agreed namespace, model, world, and workspace assumptions inside the running containers.
- `scripts/bringup-single-vehicle.sh` is the first actual runtime attempt for one PX4-backed aircraft in Gazebo.
- `scripts/check-px4-telemetry.sh` is the first narrow telemetry discovery check for `/plane_01/fmu/out/...` during the current runtime path.
- `ros2_ws/src/px4_msgs.repos` pins the minimum ROS-side PX4 message dependency for telemetry type visibility.

## What Is Not Yet Wired

- The first actual bring-up currently uses PX4's native Gazebo launch inside the `px4` container rather than the standalone `gazebo` service.
- No camera sensor path is implemented yet.
- `ros_gz` is installed but runtime camera/topic bridging is not yet validated.
- The full fixed-wing autonomy target is still incomplete.
