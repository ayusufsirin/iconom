# SESSION

## Goal
Stabilize the phase-6 live-rival chase so `plane_01` can hold a sustained rear-aspect follow distance behind `plane_02` instead of overshooting through the target path.

## Current status
The repo now has a staged trailing-slot controller and a range-gated live-rival geometry check. The live two-plane run still reaches only brief close-range valid samples, not a sustained `5 m +/- tolerance` tail-chase hold.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh
- /home/joseph/Projects/iconom/scripts/evaluate-phase6-geometry.py
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Committed the intermediate trailing-range baseline: staged trailing-slot geometry, target-range gating, and live-rival hardening wiring are now saved before the next damping pass.

## Current blocker
The live-rival hardening check still fails because the controller is effectively underdamped in terminal follow. It can enter the target range band briefly, but it does not hold simultaneous cue, rear-cone geometry, and `5 m +/- tolerance` range for the required 10-second window.

## Next exact step
Replace the current proportional thrust law in `/home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/camera_cueing_bridge.py` with a PD-style range controller that uses closing-rate damping, then rerun `./scripts/check-phase6-live-rival-geometry.sh --incremental`.

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
- The strongest current signal is that rear-aspect geometry and close range are both reachable, but not yet simultaneously stable for the full hold window.
