# SESSION

## Goal
Evaluate whether a minimal rectangular live-rival route for `plane_02` is a useful phase-6 hardening variant before changing the maintained baseline.

## Current status
The standalone `check-phase6-live-rival-geometry.sh` experiment now drives `plane_02` through a minimal four-corner rectangular route while leaving the phase-5/phase-6 guidance stack and `plane_01` control path unchanged. The headless run passes: `plane_01` still achieves an airborne catch against the moving rival and both aircraft land successfully afterward.

## Files touched
- /home/joseph/Projects/iconom/SESSION.md
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh

## Last completed step
Validated the rectangular-route variant with `./scripts/check-phase6-live-rival-geometry.sh --incremental`; latest passing summary included `initial_bearing_error_deg=111.134`, `catch_bearing_error_deg=12.411`, `catch_cue_error_deg=13.507`, `catch_altitude_agl_m=19.207`, and `rival_route_distance_m=100.528`.

## Current blocker
None

## Next exact step
Decide whether to keep the rectangular `plane_02` route as an uncommitted experiment, commit it as the new default live-rival geometry path, or run a GUI confirmation first.

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

## Notes
- This is a minimal rival-only change: `plane_02` motion changed, `plane_01` guidance/controller logic did not.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, `ros2_ws/.tmp-phase6-live-rival-geometry.csv`, `ros2_ws/.tmp-phase6-live-rival-geometry.csv.svg`, `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv`, and `ros2_ws/.tmp-phase6-scripted-cue-geometry.csv.svg` out of git.
