# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Immediate Next Outcome

After phase 0, the next work should be:

1. create `AGENTS.md` and task templates,
2. create the initial repository layout for simulation and ROS work,
3. implement a single-vehicle smoke-test target only.
