# SESSION

## Goal
Finish the fifth phase-6 slice: live-rival camera cueing for `plane_01` against real `plane_02` data from the maintained dual-aircraft runtime.

## Current status
The live-rival cueing slice is implemented and validated headless and GUI. The maintained check now starts the shared phase-4 stack, brings both aircraft to loiter, republishes live `plane_02` state into `/competition/rival/state`, and verifies that `plane_01` reduces the published cue error while flying in `OFFBOARD`.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_competition/setup.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_competition/iconom_competition/live_rival_state_adapter.py
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-cueing.sh
- /home/joseph/Projects/iconom/README.md

## Last completed step
Validated the live-rival cueing slice with `./scripts/check-phase6-live-rival-cueing.sh` and `ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-cueing.sh`.

## Current blocker
None

## Next exact step
Review the uncommitted live-rival cueing slice and commit it with a conventional commit if it still looks correct.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-cueing.sh
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-cueing.sh
```

## Notes
- The live-rival slice keeps `plane_01` as ownship and uses real `plane_02` telemetry as the rival source.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
