# SESSION

## Goal
Maintain the optimized phase-6 acceptance path as the current baseline for pursuit guidance and live-rival cueing.

## Current status
`perf(phase6): reuse guidance workspace in acceptance` is committed at `bc69642`. `scripts/phase6-acceptance.sh` now bootstraps `px4_msgs` and `iconom_guidance` once, reuses that workspace across the first three checks, and still passes in both headless and GUI modes.

## Files touched
- /home/joseph/Projects/iconom/scripts/check-phase6-target-selection.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-intercept-planner.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-pursuit-state-machine.sh
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Committed the optimized phase-6 acceptance slice after validating both `--headless` and `--gui`.

## Current blocker
None

## Next exact step
None

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

## Notes
- The first cold acceptance run still bootstraps `px4_msgs` once; the first three checks now reuse that prepared workspace instead of rebuilding it three times.
- GUI mode is only visually meaningful for the final live-rival cueing step; the earlier phase-6 checks remain non-visual.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
