# SESSION

## Goal
Stabilize the phase-6 live-rival chase with closing-speed damping so `plane_01` can hold a sustained rear-aspect follow distance behind `plane_02` instead of overshooting through the target path.

## Current status
The repo now has a PD-style range controller in `camera_cueing_bridge.py` that adds closing-speed damping on top of the staged trailing-slot geometry. The latest live-rival run completed and produced fresh CSV/CZML artifacts, but the strengthened geometry check still did not satisfy the required sustained `5 m +/- tolerance` stern-chase hold.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Ran the live two-plane simulation with the new PD controller and regenerated `/home/joseph/Projects/iconom/ros2_ws/.tmp-phase6-live-rival-geometry.csv.czml` from the resulting CSV.

## Current blocker
The current PD gains still do not hold simultaneous cue, rear-cone geometry, and `5 m +/- tolerance` range for the required sustained 10-second window.

## Next exact step
Tune `range_damping_gain` and `closing_speed_filter_alpha` in `/home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py`, then rerun `./scripts/check-phase6-live-rival-geometry.sh --incremental` and inspect the regenerated CZML.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
python3 ./scripts/export-phase6-czml.py ./ros2_ws/.tmp-phase6-live-rival-geometry.csv
```

```bash
cd /home/joseph/Projects/iconom
./scripts/serve-phase6-czml-viewer.sh
```

## Notes
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*.csv` / `.svg` / `.czml` artifacts out of git.
- The freshest replay artifact is `/home/joseph/Projects/iconom/ros2_ws/.tmp-phase6-live-rival-geometry.csv.czml`.
