# Phase 1 Scaffold

This scaffold defines the first implementation contract without claiming the simulator stack already works.

## Canonical Stack

- `docker-compose.yml` is the canonical stack for both CI and local execution.
- `docker-compose.override.yml` adds local-host execution extras only. It is not a separate stack.
- `.env.example` defines the current environment contract.

## Current Status

- Service names are locked: `px4`, `gazebo`, `xrce_agent`, `ros2_app`.
- The smoke workflow and script are present.
- The smoke script currently exits with a clear `not yet implemented` status by design.

## Next Implementation Step

Replace the placeholder service definitions with real project-owned images and implement the first deterministic headless smoke checks.
