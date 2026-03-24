# SESSION

## Goal
Implement phase 5 slice 4 - the live ownship telemetry adapter. The immediate engineering goal is to map live ROS/PX4 state to competition telemetry and send it to the mock referee server.

## Current status
Phase 5 plan exists at `docs/phase-5-plan.md`. The mock referee server and competition client are complete. The ownship telemetry adapter is now implemented.

## Files touched
- `ros2_ws/src/iconom_competition/package.xml`
- `ros2_ws/src/iconom_competition/setup.py`
- `ros2_ws/src/iconom_competition/iconom_competition/ownship_telemetry_adapter.py`
- `scripts/check-phase5-telemetry-adapter.sh`
- `README.md`
- `SESSION.md`

## Last completed step
Implemented ownship_telemetry_adapter.py that subscribes to `/plane_01/fmu/out/vehicle_local_position`, maps live PX4 state to competition telemetry format, authenticates with referee, and sends telemetry at 1-second intervals.

## Current blocker
None

## Next exact step
Run `./scripts/check-phase5-telemetry-adapter.sh` to verify the telemetry adapter works correctly.

## Validation
- `cd /home/joseph/Projects/iconom && ./scripts/check-phase5-telemetry-adapter.sh`

## Notes
- Keep `QGroundControl-x86_64.AppImage` and `opencode.json` out of commits.
- Phase 5 should build on the phase-4 isolation baseline rather than replace it.
- Phase 5 remains simulation-only with no hardware, reporting, or vision lock logic.
