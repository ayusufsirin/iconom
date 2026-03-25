# SESSION

## Goal
Stabilize the phase-6 live-rival cueing slice using PX4-supported offboard attitude setpoints so a real airborne catch is followed by successful landing of both aircraft.

## Current status
The live-rival cueing path now uses `OffboardControlMode.attitude=true` plus `VehicleAttitudeSetpoint` instead of raw body-rate setpoints. `ownship_telemetry_adapter.py` publishes ownship state on PX4 local-position cadence, and `check-phase6-live-rival-cueing.sh` now requires a sustained airborne catch before landing both aircraft. The revised headless live-rival cueing check now passes end to end.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_competition/iconom_competition/ownship_telemetry_adapter.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-cueing.sh
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Reworked the cueing bridge to use PX4 attitude setpoints, reran `./scripts/check-phase6-live-rival-cueing.sh`, and got a truthful green run with airborne catch and post-catch landing of both aircraft.

## Current blocker
None

## Next exact step
None

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-cueing.sh
```

## Notes
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
- Phase-6 live-rival cueing now depends on PX4 attitude setpoints, not repo-owned raw rate setpoints.
- The acceptance is intentionally strict: success requires a sustained airborne catch before both aircraft land.
