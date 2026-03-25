# SESSION

## Goal
Finish the standalone phase-6 scripted cue-geometry hardening slice so camera cueing is backed by route-comparison evidence, not just a transient cone hit.

## Current status
The scripted hardening slice is now implemented and validated. `./scripts/check-phase6-scripted-cue-geometry.sh --incremental` passes headless, and `ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-scripted-cue-geometry.sh --incremental` also passes. The maintained phase-6 baseline is still `phase6-acceptance.sh`; the scripted geometry check remains a standalone hardening proof.

## Files touched
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_control/iconom_control/vehicle_local_position_waiter.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/scripted_rival_publisher.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/cue_geometry_monitor.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/setup.py
- /home/joseph/Projects/iconom/scripts/check-phase6-scripted-cue-geometry.sh

## Last completed step
Validated the scripted cue-geometry check in headless and GUI mode after moving the climb gate before `mode_loiter` and switching the acceptance decision to CSV-based sustained-window validation.

## Current blocker
None

## Next exact step
Commit the scripted cue-geometry hardening slice and keep the generated `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv` artifact out of git.

## Validation
```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/check-phase6-scripted-cue-geometry.sh
```

```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

## Notes
- The scripted cue-geometry slice is intentionally standalone and is not wired into `phase6-acceptance.sh` yet.
- The pre-cue climb gate now happens during `NAV_TAKEOFF` before `mode_loiter`, which was necessary to avoid low-altitude false catches.
- The check now lands first and decides success from the recorded sustained geometry window in the CSV artifact.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv` out of git.
