# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Phase 1 Scaffold](./docs/phase-1-scaffold.md)
- [Phase 1 Integration](./docs/phase-1-integration.md)
- [Phase 2 Plan](./docs/phase-2-plan.md)
- [Agent Rules](./AGENTS.md)
- [Task Template](./docs/task-template.md)
- [Canonical Compose Stack](./docker-compose.yml)
- [Smoke Script](./scripts/smoke.sh)
- [Single-Vehicle Integration Script](./scripts/integration-single-vehicle.sh)
- [Single-Vehicle Bring-Up Script](./scripts/bringup-single-vehicle.sh)
- [Single-Vehicle GUI Bring-Up Script](./scripts/bringup-single-vehicle-gui.sh)
- [Phase 1 Launch Script](./scripts/phase1-launch.sh)
- [Phase 1 Acceptance Script](./scripts/phase1-acceptance.sh)
- [PX4 Telemetry Check Script](./scripts/check-px4-telemetry.sh)
- [Camera Bridge Check Script](./scripts/check-camera-bridge.sh)
- [Camera Subscriber Check Script](./scripts/check-camera-subscriber.sh)
- [Vehicle Command Check Script](./scripts/check-vehicle-command.sh)
- [Mode Command Check Script](./scripts/check-mode-command.sh)
- [Offboard Readiness Check Script](./scripts/check-offboard-readiness.sh)
- [Offboard Movement Check Script](./scripts/check-offboard-movement.sh)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Current Slice

All five maintained service slices now exist: `xrce_agent`, `ros2_app`, `px4`, `gazebo`, and `ros_gz_bridge`. The current integrated milestone is no longer basic service availability. The repo now has a truthful one-vehicle runtime, PX4 telemetry discovery, and a maintained Gazebo camera bridge into ROS 2.

This repo requires Docker Compose v2 via `docker compose`.

The first integrated baseline is now `plane_01` via [integration-single-vehicle.sh](./scripts/integration-single-vehicle.sh). It validates the shared one-vehicle launch contract without claiming full PX4-in-Gazebo vehicle runtime yet.

The first actual one-vehicle runtime attempt is [bringup-single-vehicle.sh](./scripts/bringup-single-vehicle.sh). It launches PX4's native `gz_rc_cessna` Gazebo path inside the `px4` container while `xrce_agent` and `ros2_app` run as companion services.

The local integrated aircraft GUI path is [bringup-single-vehicle-gui.sh](./scripts/bringup-single-vehicle-gui.sh). It uses the local override stack to route X11 into the `px4` runtime and forces `PX4_HEADLESS=0`.

The canonical operator entrypoint is now [phase1-launch.sh](./scripts/phase1-launch.sh). It selects the maintained phase-1 runtime path in either headless or GUI mode without changing the underlying one-vehicle contract.

The canonical validation entrypoint is now [phase1-acceptance.sh](./scripts/phase1-acceptance.sh). It chains the maintained phase-1 checks for telemetry, camera bridge, camera subscriber, command path, mode change, offboard readiness, and offboard movement.

The next narrow milestone is [check-px4-telemetry.sh](./scripts/check-px4-telemetry.sh), which attempts to observe one PX4 telemetry topic under `/plane_01/fmu/out/...` during the current runtime path.

For this telemetry step, the ROS workspace now carries a pinned [px4_msgs.repos](./ros2_ws/src/px4_msgs.repos) manifest so `ros2_app` can build the minimum PX4 message package needed for telemetry type and topic discovery.

The current camera milestone is [check-camera-bridge.sh](./scripts/check-camera-bridge.sh). It validates one forward camera on the `gz_rc_cessna` runtime and proves that:

- Gazebo publishes the live camera image and camera-info topics,
- the maintained `ros_gz_bridge` service stays alive alongside the separated runtime,
- ROS 2 sees `/plane_01/camera/image_raw` and `/plane_01/camera/camera_info`.

The next ROS-side proof is [check-camera-subscriber.sh](./scripts/check-camera-subscriber.sh). It builds the minimal `iconom_vision` package in `ros2_ws`, launches a subscriber in `ros2_app`, and verifies that one bridged image frame is actually received.

The next control-side proof is [check-vehicle-command.sh](./scripts/check-vehicle-command.sh). It builds the minimal `iconom_control` package in `ros2_ws`, publishes one `VehicleCommand` on `/plane_01/fmu/in/vehicle_command`, and requires a matching `VehicleCommandAck` on `/plane_01/fmu/out/vehicle_command_ack`.

The control check now supports both `disarm` and `arm` via `PX4_COMMAND_NAME`. For the current `gz_rc_cessna` phase-1 baseline, the PX4 image overrides two airframe defaults to make SITL arming achievable without a GCS or physical airspeed requirement:

- `NAV_DLL_ACT=0`
- `SYS_HAS_NUM_ASPD=0`

The next control proof is [check-mode-command.sh](./scripts/check-mode-command.sh). It waits for a preflight-ready `VehicleStatus`, arms through the existing command path, publishes one ROS-side mode request, and requires the resulting `VehicleStatus.nav_state` change on `/plane_01/fmu/out/vehicle_status_v1`.

The first validated mode for this phase-1 baseline is `mode_loiter`, which maps to `NAVIGATION_STATE_AUTO_LOITER`. `STAB` is intentionally not the first validated mode because PX4 requires manual-control availability for that mode in this SITL state.

The next control proof is [check-offboard-readiness.sh](./scripts/check-offboard-readiness.sh). It starts a repo-owned offboard hold publisher, streams `OffboardControlMode` plus `TrajectorySetpoint` on `/plane_01/fmu/in/...`, requests `mode_offboard`, and requires `VehicleStatus.nav_state=14`.

The current offboard milestone is intentionally narrow: it proves offboard entry readiness and a steady hold-style setpoint stream. It does not yet claim waypointing, trajectory logic, or fixed-wing mission behavior.

The next control proof is [check-offboard-movement.sh](./scripts/check-offboard-movement.sh). It uses a fixed-wing-compatible offboard primitive, `body_rate + thrust`, requests `mode_offboard`, and requires a bounded planar `VehicleLocalPosition` response while `VehicleStatus` remains in `nav_state=14`.

This movement result matters because fixed-wing position-style offboard from rest remains grounded by PX4's landed handling. The first real movement primitive in this SITL baseline is therefore rate/thrust offboard, not a position-step takeoff.

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

## Phase 1 Daily Use

Headless launch:

```bash
./scripts/phase1-launch.sh --headless
```

Integrated aircraft GUI launch:

```bash
xhost +local:docker
./scripts/phase1-launch.sh --gui
```

Headless acceptance:

```bash
./scripts/phase1-acceptance.sh --headless
```

GUI acceptance:

```bash
xhost +local:docker
./scripts/phase1-acceptance.sh --gui
```

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Phase 2 Direction

Phase 2 starts from the tagged `phase1-baseline` and keeps the same single-vehicle contract while removing the largest remaining architectural compromise: Gazebo should become a first-class standalone runtime service instead of being launched from inside the `px4` container.

The current phase-2 source of truth is [phase-2-plan.md](./docs/phase-2-plan.md).
