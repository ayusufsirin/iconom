# SESSION

## Goal
Finish the fourth phase-6 slice: the first aircraft camera-cueing proof for `plane_01`, using the maintained phase-5/phase-6 guidance inputs plus a repo-owned offboard controller.

## Current status
The `camera_cueing_bridge` slice is implemented in `iconom_guidance` and the maintained camera-cueing check passes headless and GUI. The check now takes `plane_01` through takeoff, loiter, live guidance, OFFBOARD entry, and verifies that the published cue error drops into the forward cone.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py
- /home/joseph/Projects/iconom/scripts/check-phase6-camera-cueing.sh
- /home/joseph/Projects/iconom/README.md

## Last completed step
Validated the phase-6 camera-cueing slice with `./scripts/check-phase6-camera-cueing.sh` and `ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-camera-cueing.sh`.

## Current blocker
None

## Next exact step
Review the uncommitted phase-6 camera-cueing slice and commit it with a conventional commit if it still looks correct.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-camera-cueing.sh
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-camera-cueing.sh
```

## Notes
- The maintained cueing path no longer uses `DO_REPOSITION`; it uses repo-owned offboard body-rate setpoints after `mode_offboard` is accepted.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
