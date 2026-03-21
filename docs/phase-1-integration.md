# Phase 1 Integration

This document defines the first honest single-vehicle integration baseline.

## Canonical Contract

- Vehicle namespace: `plane_01`
- PX4 ROS namespace: `plane_01`
- PX4 model contract: `gz_rc_cessna`
- Gazebo world contract: `sim/worlds/empty.sdf`
- Integrated service set: `xrce_agent`, `ros2_app`, `px4`

## What Is Wired

- The maintained service set can be built and started together under one `plane_01` contract.
- `px4` and `ros2_app` depend on `xrce_agent` in the canonical compose stack.
- `scripts/integration-single-vehicle.sh` validates the agreed namespace, model, world, and workspace assumptions inside the running containers.
- `scripts/bringup-single-vehicle.sh` is the first actual runtime attempt for one PX4-backed aircraft in Gazebo.
- `scripts/bringup-single-vehicle-gui.sh` is the local integrated aircraft GUI entrypoint for the current PX4 runtime path.
- `scripts/phase1-launch.sh` is the canonical operator entrypoint for the maintained phase-1 runtime in headless or GUI mode.
- `scripts/check-px4-telemetry.sh` is the first narrow telemetry discovery check for `/plane_01/fmu/out/...` during the current runtime path.
- `ros2_ws/src/px4_msgs.repos` pins the minimum ROS-side PX4 message dependency for telemetry type visibility.
- `scripts/check-camera-bridge.sh` validates the first camera slice by discovering Gazebo camera topics in the live PX4 runtime container and verifying that the maintained `ros_gz_bridge` service bridges them into ROS 2.
- `ros2_ws/src/iconom_vision` contains the first repo-owned ROS 2 vision package for the camera slice.
- `scripts/check-camera-subscriber.sh` validates that a ROS-side subscriber can receive at least one bridged image frame on `/plane_01/camera/image_raw`.
- `ros2_ws/src/iconom_control` contains the first repo-owned ROS 2 control package for the command slice.
- `scripts/check-vehicle-command.sh` validates a ROS-side `VehicleCommand` publish plus `VehicleCommandAck` roundtrip on `/plane_01/fmu/in/...` and `/plane_01/fmu/out/...`.
- The current command slice validates both `disarm` and `arm` actions for `plane_01`.
- `scripts/check-mode-command.sh` validates the first ROS-side mode slice by waiting for preflight-ready `VehicleStatus`, arming, publishing a mode request, and confirming the resulting `VehicleStatus.nav_state`.
- The first validated phase-1 mode is `mode_loiter`, which maps to `NAVIGATION_STATE_AUTO_LOITER` and is observed on `/plane_01/fmu/out/vehicle_status_v1`.
- `scripts/check-offboard-readiness.sh` validates the first ROS-side offboard slice by streaming `OffboardControlMode` plus a hold-style `TrajectorySetpoint`, requesting `mode_offboard`, and confirming `VehicleStatus.nav_state=14`.
- `ros2_ws/src/iconom_control/iconom_control/offboard_hold_publisher.py` contains the first repo-owned offboard publisher for the control slice.
- `scripts/check-offboard-movement.sh` validates the first ROS-side movement slice in `OFFBOARD` mode by streaming `body_rate + thrust`, confirming bounded planar `VehicleLocalPosition` motion, and verifying that `VehicleStatus` remains in `nav_state=14`.
- `scripts/phase1-acceptance.sh` is the canonical maintained validation flow for phase 1 and chains the current telemetry, camera, command, mode, offboard-readiness, and offboard-movement checks.
- `ros2_ws/src/iconom_control/iconom_control/offboard_rate_thrust_publisher.py` contains the first repo-owned fixed-wing-compatible movement publisher for the control slice.
- `ros2_ws/src/iconom_control/iconom_control/vehicle_local_position_waiter.py` contains the first repo-owned local-position response validator for the movement slice.
- The current `gz_rc_cessna` phase-1 baseline explicitly overrides two PX4 airframe defaults to make headless SITL arming achievable:
  - `NAV_DLL_ACT=0`
  - `SYS_HAS_NUM_ASPD=0`
- The maintained runtime now includes a long-running `ros_gz_bridge` service for the camera bridge path.

## What Is Not Yet Wired

- The first actual bring-up currently uses PX4's native Gazebo launch inside the `px4` container rather than the standalone `gazebo` service.
- The standalone `gazebo` service remains useful for local GUI checks, but it is not the runtime backend for the current one-aircraft milestone.
- The integrated aircraft GUI path is local-host-only for now and still depends on X11 passthrough in the override stack.
- The current camera bridge path is a truthful milestone, but it is still a transitional integration shape rather than the final separated runtime architecture.
- `NAVIGATION_STATE_STAB` is not used as the first validated mode because PX4 requires manual-control availability for it in the current SITL state.
- The current offboard readiness milestone proves entry and a basic hold stream, but fixed-wing position-style offboard from rest remains constrained by PX4's landed handling.
- The first real offboard movement primitive in this SITL baseline is `body_rate + thrust`, not a position-step takeoff.
- The movement slice still does not prove waypointing, fixed-wing trajectory behavior, or mission logic.
- The full fixed-wing autonomy target is still incomplete.

## Canonical Entry Points

- Use `scripts/phase1-launch.sh --headless` for the maintained headless operator path.
- Use `scripts/phase1-launch.sh --gui` for the maintained integrated aircraft GUI path.
- Use `scripts/phase1-acceptance.sh --headless` for the maintained CI-style acceptance flow.
- Use `scripts/phase1-acceptance.sh --gui` for the maintained local GUI-backed acceptance flow.
