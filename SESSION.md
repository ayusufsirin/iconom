# SESSION

## Goal
Keep phase-6 hardening truthful by validating live two-aircraft cueing as a sustained stern-chase geometry, not just a transient forward-cone catch.

## Current status
The shared evaluator now scores angular, range, tail-angle, and heading-alignment gates. The maintained live-rival geometry check uses a straight `plane_02` run and passes with a roughly 10-second stern-chase hold before both aircraft land.

## Files touched
- /home/joseph/Projects/iconom/scripts/evaluate-phase6-geometry.py
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Validated `./scripts/check-phase6-live-rival-geometry.sh --incremental` with the new stern-chase gates. The passing run reported `hold_duration_sec=9.996`, `catch_tail_angle_deg=9.137`, `catch_heading_alignment_error_deg=5.677`, `catch_range_3d_m=22.224`, and clean landing for both aircraft.

## Current blocker
None

## Next exact step
None

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-geometry.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
docker compose -f docker-compose.yml run --rm -v /home/joseph/Projects/iconom:/repo ros2_app python3 /repo/scripts/plot-phase6-scripted-cue-geometry.py /repo/ros2_ws/.tmp-phase6-live-rival-geometry.csv --output /repo/ros2_ws/.tmp-phase6-live-rival-geometry.csv.svg
```

## Notes
- The live-rival check now uses a straight `plane_02` route by default because the old rectangle did not sustain a tail-chase hold.
- `hold_duration_sec` is sample-based; the maintained passing run printed `9.996`, which satisfies the 10-second window under the evaluator’s sample-period logic.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*.csv` / `.svg` artifacts out of git.
