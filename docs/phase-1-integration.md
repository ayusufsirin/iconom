# Phase 1 Integration

This document defines the first honest single-vehicle integration baseline.

## Canonical Contract

- Vehicle namespace: `plane_01`
- PX4 ROS namespace: `plane_01`
- PX4 model contract: `gz_rc_cessna`
- Gazebo world contract: `sim/worlds/empty.sdf`
- Integrated service set: `xrce_agent`, `ros2_app`, `px4`

## What Is Wired

- The four containers can be built and started together under one `plane_01` contract.
- `px4` and `ros2_app` depend on `xrce_agent` in the canonical compose stack.
- `scripts/integration-single-vehicle.sh` validates the agreed namespace, model, world, and workspace assumptions inside the running containers.
- `scripts/bringup-single-vehicle.sh` is the first actual runtime attempt for one PX4-backed aircraft in Gazebo.
- `scripts/check-px4-telemetry.sh` is the first narrow telemetry discovery check for `/plane_01/fmu/out/...` during the current runtime path.
- `ros2_ws/src/px4_msgs.repos` pins the minimum ROS-side PX4 message dependency for telemetry type visibility.
- `scripts/check-camera-bridge.sh` validates the first camera slice by discovering Gazebo camera topics in the live PX4 runtime container and bridging them into ROS 2.
- The current camera bridge process runs in a one-off `ros_gz_bridge` container that shares the live PX4 runtime network namespace.

## What Is Not Yet Wired

- The first actual bring-up currently uses PX4's native Gazebo launch inside the `px4` container rather than the standalone `gazebo` service.
- The standalone `gazebo` service remains useful for local GUI checks, but it is not the runtime backend for the current one-aircraft milestone.
- The current camera bridge path is a truthful milestone, but it is still a transitional integration shape rather than the final separated runtime architecture.
- The full fixed-wing autonomy target is still incomplete.
