# Phase 1 Scaffold

This scaffold defines the first implementation contract without claiming the simulator stack already works.

## Canonical Stack

- `docker-compose.yml` is the canonical stack for both CI and local execution.
- `docker-compose.override.yml` adds local-host execution extras only. It is not a separate stack.
- `.env.example` defines the current environment contract.
- This repo requires Docker Compose v2 via `docker compose`.

## Current Status

- Service names are locked: `px4`, `gazebo`, `xrce_agent`, `ros2_app`.
- The smoke workflow and script are present.
- `xrce_agent` is the first real service slice.
- `xrce_agent` is built in a project-owned Ubuntu 22.04 image and installs eProsima Micro XRCE-DDS Agent from the upstream `v2.4.3` release source.
- `ros2_app` is now a real Ubuntu 22.04 + ROS 2 Humble base container with a mounted workspace root at `/workspaces/ros2_ws`.
- `px4` is now a real Ubuntu 22.04 PX4 `v1.16.0` build slice that validates the SITL binary and agreed runtime configuration without claiming a Gazebo-backed sim run.
- The smoke script now validates compose config and exercises `xrce_agent`, `ros2_app`, and `px4`, but still exits nonzero because the full stack is not implemented yet.

## Next Implementation Step

Keep `xrce_agent`, `ros2_app`, and `px4` as the reference slices, then replace the remaining `gazebo` placeholder with a real simulator slice and extend the smoke checks to the full single-vehicle stack.
