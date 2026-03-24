# SESSION

## Goal
Implement the first phase-6 slice: deterministic target selection on top of the validated phase-5 rival-state outputs, with one maintained check and no aircraft guidance yet.

## Current status
The new `iconom_guidance` package is in the working tree with a validated `target_selector` node that consumes `/competition/ownship/state` and `/competition/rival/state`, then publishes the selected rival on `/guidance/selected_target`. The maintained `./scripts/check-phase6-target-selection.sh` check now passes end to end.

## Files touched
- `ros2_ws/src/iconom_guidance/setup.py`
- `ros2_ws/src/iconom_guidance/package.xml`
- `ros2_ws/src/iconom_guidance/resource/iconom_guidance`
- `ros2_ws/src/iconom_guidance/iconom_guidance/__init__.py`
- `ros2_ws/src/iconom_guidance/iconom_guidance/target_selector.py`
- `scripts/check-phase6-target-selection.sh`
- `README.md`
- `SESSION.md`

## Last completed step
Validated the deterministic target-selector slice with `./scripts/check-phase6-target-selection.sh`, including reselection when a different rival became nearer.

## Current blocker
None

## Next exact step
Prepare this phase-6 target-selection slice for review/commit, then start the bounded intercept-planner slice.

## Validation
- `cd /home/joseph/Projects/iconom && ./scripts/check-phase6-target-selection.sh`

## Notes
- The selector is intentionally narrow: nearest-rival by Euclidean distance, with lexicographic frame-id tie-break.
- No aircraft guidance or pursuit-state logic belongs in this slice.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of commits.
