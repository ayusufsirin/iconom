# SESSION

## Goal
Decide whether to fold the new real-sim live-rival geometry hardening check into the maintained phase-6 baseline, or keep it standalone and start phase-7 planning.

## Current status
Phase 6 now has a maintained headless and GUI-capable acceptance path, a standalone scripted cue-geometry hardening check, and a new standalone real-sim live-rival geometry hardening check. The new live-rival geometry check uses real `plane_02` state, records ownship-versus-rival geometry to CSV, and passes in both headless and GUI mode with sustained airborne catch plus successful landing of both aircraft.

## Files touched
- /home/joseph/Projects/iconom/SESSION.md
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh
- /home/joseph/Projects/iconom/scripts/evaluate-phase6-geometry.py

## Last completed step
Validated the standalone real-sim live-rival geometry hardening slice in both modes with `./scripts/check-phase6-live-rival-geometry.sh --incremental` and `ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental` after fixing the compose profile handling for `referee_server` and the missing `wait_for_topic` call.

## Current blocker
None

## Next exact step
Choose one: either wire `check-phase6-live-rival-geometry.sh` into `phase6-acceptance.sh`, or keep it standalone and start phase-7 planning.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
./scripts/phase6-acceptance.sh --headless
```

## Notes
- `check-phase6-live-rival-geometry.sh` is a stronger standalone hardening proof than the maintained phase-6 acceptance path; it is not wired into `phase6-acceptance.sh` yet.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, `ros2_ws/.tmp-phase6-live-rival-geometry.csv`, `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv`, and `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv.svg` out of git.
