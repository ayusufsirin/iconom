# SESSION

## Goal
Decide whether phase 6 is complete enough to close or whether the scripted cue-geometry hardening check should be folded into the maintained phase-6 baseline first.

## Current status
Phase 6 now has a maintained headless and GUI-capable acceptance path plus a separate scripted cue-geometry hardening check. The scripted check is committed and passes headless and GUI, but it is intentionally still outside `phase6-acceptance.sh`. There is also now a standalone SVG plot utility for visually comparing ownship and rival trajectories from the recorded CSV.

## Files touched
- /home/joseph/Projects/iconom/SESSION.md
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-scripted-cue-geometry.sh
- /home/joseph/Projects/iconom/scripts/plot-phase6-scripted-cue-geometry.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/cue_geometry_monitor.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_competition/iconom_competition/live_rival_state_adapter.py

## Last completed step
Committed the standalone scripted cue-geometry hardening slice in `aaa4ed6` after validating it in both headless and GUI mode, then added a plot utility for the recorded CSV.

## Current blocker
None

## Next exact step
Choose one: either wire `check-phase6-scripted-cue-geometry.sh` into `phase6-acceptance.sh`, or treat phase 6 as complete and start phase-7 planning.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/phase6-acceptance.sh --headless
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
./scripts/phase6-acceptance.sh --gui
```

```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
python3 ./scripts/plot-phase6-scripted-cue-geometry.py ./ros2_ws/.tmp-phase6-scripted-cue-geometry.csv
```

## Notes
- `check-phase6-scripted-cue-geometry.sh` is a standalone hardening proof and is not part of `phase6-acceptance.sh` yet.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv` out of git.
