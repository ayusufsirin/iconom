# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Phase 1 Scaffold](./docs/phase-1-scaffold.md)
- [Agent Rules](./AGENTS.md)
- [Task Template](./docs/task-template.md)
- [Canonical Compose Stack](./docker-compose.yml)
- [Smoke Script](./scripts/smoke.sh)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Immediate Next Outcome

With phase-0 decisions and guardrails in place, the next work should be:

1. replace the placeholder service definitions with real project-owned images,
2. implement the deterministic headless smoke checks in `scripts/smoke.sh`,
3. wire the smoke workflow to a functioning single-vehicle stack.
