# ros2_ws

This directory is the mounted ROS 2 workspace root for the `ros2_app` service.

## Current Scope

- ROS 2 Humble base tools are available in the container.
- No project packages or nodes are implemented yet.
- The current telemetry milestone checks ROS 2 topic discovery first; it does not claim camera or full bridge validation yet.
- `src/px4_msgs.repos` pins the minimum PX4 ROS message dependency for telemetry discovery work.
- Future packages should be added under `src/`.

## Expected Layout

```text
ros2_ws/
  src/
```
