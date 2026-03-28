# SESSION

## Goal
Keep phase-6 hardening truthful by applying angular and range-gated catch definitions to scripted and live geometry checks, and keep the trajectory plot aligned with the recorded geometry fields.

## Current status
The shared evaluator supports angular and range gates, the scripted and live geometry checks both use it, and the live two-plane check passes with the tighter default rectangular route for `plane_02`. The geometry monitor records `rival_yaw_deg`, and the plotter now requires fresh CSVs with that field so it cannot silently draw line-of-sight bearing as rival heading.

## Files touched
- /home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/cue_geometry_monitor.py
- /home/joseph/Projects/iconom/scripts/evaluate-phase6-geometry.py
- /home/joseph/Projects/iconom/scripts/check-phase6-scripted-cue-geometry.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh
- /home/joseph/Projects/iconom/scripts/plot-phase6-scripted-cue-geometry.py
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Tightened the phase-6 geometry tooling so both scripted and live hardening use the shared range-gated evaluator, the live check passes with the maintained rectangular rival route, and the plotter now refuses stale CSVs that lack `rival_yaw_deg` instead of drawing the wrong arrow.

## Current blocker
None

## Next exact step
None

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
docker compose -f docker-compose.yml run --rm -v /home/joseph/Projects/iconom:/repo ros2_app python3 /repo/scripts/plot-phase6-scripted-cue-geometry.py /repo/ros2_ws/.tmp-phase6-scripted-cue-geometry.csv
```

## Notes
- Regenerate the `.tmp-phase6-*.csv` artifacts before plotting if they were created before `rival_yaw_deg` was added.
- The plotter should show blue ownship heading and red rival heading at the catch sample only when the CSV includes `rival_yaw_deg`.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*.csv` / `.svg` artifacts out of git.
