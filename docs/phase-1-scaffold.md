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
- `gazebo` is now a real Ubuntu 22.04 Gazebo Harmonic headless slice with the deliberate Humble/Harmonic `ros_gz` bridge packages installed.
- `scripts/smoke.sh` now covers slice-level availability checks only.
- `scripts/integration-single-vehicle.sh` defines the first integrated `plane_01` launch contract for `xrce_agent`, `gazebo`, `ros2_app`, and `px4`.
- `scripts/bringup-single-vehicle.sh` is now the first actual PX4-in-Gazebo bring-up attempt for one aircraft.

## Next Implementation Step

Use the first actual bring-up path as the starting point, then move from PX4-native Gazebo launch to the fully container-separated runtime path and add camera plus runtime ROS bridge validation.
