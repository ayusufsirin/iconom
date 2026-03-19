# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Agent Rules](./AGENTS.md)
- [Task Template](./docs/task-template.md)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Immediate Next Outcome

With phase-0 decisions and guardrails in place, the next work should be:

1. implement the canonical phase-1 Compose stack and image skeleton,
2. add the first self-hosted CI workflow and smoke-test script,
3. implement the single-vehicle smoke-test target only.
