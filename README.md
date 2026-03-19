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
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Current Slice

All four service slices now exist: `xrce_agent`, `ros2_app`, `px4`, and `gazebo`. The remaining gap is full vehicle and sensor integration, not basic service availability.

This repo requires Docker Compose v2 via `docker compose`.

The first integrated baseline is now `plane_01` via [integration-single-vehicle.sh](./scripts/integration-single-vehicle.sh). It validates the shared one-vehicle launch contract without claiming full PX4-in-Gazebo vehicle runtime yet.

The first actual one-vehicle runtime attempt is [bringup-single-vehicle.sh](./scripts/bringup-single-vehicle.sh). It launches PX4's native `gz_rc_cessna` Gazebo path inside the `px4` container while `xrce_agent` and `ros2_app` run as companion services.

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

1. validate and stabilize the actual `gz_rc_cessna` one-vehicle bring-up path,
2. add the first runtime ROS bridge and telemetry topic checks,
3. reconcile the PX4-native bring-up path with the standalone `gazebo` service for a fully separated runtime.
