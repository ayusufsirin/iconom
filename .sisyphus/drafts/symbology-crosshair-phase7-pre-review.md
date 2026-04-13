# Draft: Symbology Crosshair Phase7-Pre Review

## Requirements (confirmed)
- review changes against `phase7-pre` to understand missing crosshair on `/plane_01/camera/image_overlay`
- focus on pose topic publishers and any relevant pre-tag behavior

## Technical Decisions
- compare current overlay / pose-bridge / symbology test behavior against `phase7-pre`
- produce a decision-complete fix plan before further implementation

## Research Findings
- `phase7-pre` overlay already subscribed to `/competition/ownship/state` and `/fusion/rival/state`; topic names did not change.
- `phase7-pre` did not contain the new no-PX4 symbology test or `docker/ros_gz_bridge/pose_bridge.py`; those were introduced after the tag.
- `phase7-pre` got pose data from the established Phase 6 runtime (`ownship_telemetry_adapter` + EKF path), not from Gazebo world-state bridging.
- Current `camera_symbology_overlay.py` only draws a crosshair when both pose topics have arrived; missing pose data means no crosshair is rendered at all.
- Current runtime shows `/competition/ownship/state` and `/fusion/rival/state` have publishers/subscribers but no messages; `ros_gz_bridge_pose` subscribes to `/world/default/pose/info`, yet no ROS pose samples are emitted.

## Open Questions
- none

## Scope Boundaries
- INCLUDE: git-tag comparison, current file review, planning next fix
- EXCLUDE: direct source-code implementation in this step
