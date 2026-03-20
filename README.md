# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Phase 1 Scaffold](./docs/phase-1-scaffold.md)
- [Phase 1 Integration](./docs/phase-1-integration.md)
- [Agent Rules](./AGENTS.md)
- [Task Template](./docs/task-template.md)
- [Canonical Compose Stack](./docker-compose.yml)
- [Smoke Script](./scripts/smoke.sh)
- [Single-Vehicle Integration Script](./scripts/integration-single-vehicle.sh)
- [Single-Vehicle Bring-Up Script](./scripts/bringup-single-vehicle.sh)
- [Single-Vehicle GUI Bring-Up Script](./scripts/bringup-single-vehicle-gui.sh)
- [PX4 Telemetry Check Script](./scripts/check-px4-telemetry.sh)
- [Camera Bridge Check Script](./scripts/check-camera-bridge.sh)
- [Camera Subscriber Check Script](./scripts/check-camera-subscriber.sh)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Current Slice

All four service slices now exist: `xrce_agent`, `ros2_app`, `px4`, and `gazebo`. The current integrated milestone is no longer basic service availability. The repo now has a truthful one-vehicle runtime, PX4 telemetry discovery, and a first Gazebo camera bridge into ROS 2.

This repo requires Docker Compose v2 via `docker compose`.

The first integrated baseline is now `plane_01` via [integration-single-vehicle.sh](./scripts/integration-single-vehicle.sh). It validates the shared one-vehicle launch contract without claiming full PX4-in-Gazebo vehicle runtime yet.

The first actual one-vehicle runtime attempt is [bringup-single-vehicle.sh](./scripts/bringup-single-vehicle.sh). It launches PX4's native `gz_rc_cessna` Gazebo path inside the `px4` container while `xrce_agent` and `ros2_app` run as companion services.

The local integrated aircraft GUI path is [bringup-single-vehicle-gui.sh](./scripts/bringup-single-vehicle-gui.sh). It uses the local override stack to route X11 into the `px4` runtime and forces `PX4_HEADLESS=0`.

The next narrow milestone is [check-px4-telemetry.sh](./scripts/check-px4-telemetry.sh), which attempts to observe one PX4 telemetry topic under `/plane_01/fmu/out/...` during the current runtime path.

For this telemetry step, the ROS workspace now carries a pinned [px4_msgs.repos](./ros2_ws/src/px4_msgs.repos) manifest so `ros2_app` can build the minimum PX4 message package needed for telemetry type and topic discovery.

The current camera milestone is [check-camera-bridge.sh](./scripts/check-camera-bridge.sh). It validates one forward camera on the `gz_rc_cessna` runtime and proves that:

- Gazebo publishes the live camera image and camera-info topics,
- a `ros_gz_bridge` one-off container can join the live PX4 runtime network namespace,
- ROS 2 sees `/plane_01/camera/image_raw` and `/plane_01/camera/camera_info`.

The next ROS-side proof is [check-camera-subscriber.sh](./scripts/check-camera-subscriber.sh). It builds the minimal `iconom_vision` package in `ros2_ws`, launches a subscriber in `ros2_app`, and verifies that one bridged image frame is actually received.

## Local Gazebo GUI

The canonical stack remains headless in [docker-compose.yml](./docker-compose.yml). Local host GUI behavior is added only through [docker-compose.override.yml](./docker-compose.override.yml).

To run Gazebo with a local GUI from the repo root:

```bash
xhost +local:docker
docker compose up gazebo
```

To force the canonical headless path even on the local host:

```bash
docker compose -f docker-compose.yml up gazebo
```

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Immediate Next Outcome

With phase-0 decisions and guardrails in place, the next work should be:

1. stabilize the first camera/ROS bridge path as a maintained phase-1 baseline,
2. decide whether the aircraft GUI path should also be routed through the PX4 runtime milestone,
3. reconcile the PX4-native bring-up path with the standalone `gazebo` service for a fully separated runtime.
