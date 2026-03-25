# SESSION

## Goal
Reduce phase-6 acceptance runtime by bootstrapping the guidance workspace once and reusing it across the prechecks.

## Current status
`scripts/phase6-acceptance.sh` now bootstraps `px4_msgs` and `iconom_guidance` once, then reuses that workspace for the first three phase-6 checks. Both `./scripts/phase6-acceptance.sh --headless` and `./scripts/phase6-acceptance.sh --gui` pass with the optimized wrapper.

## Files touched
- /home/joseph/Projects/iconom/scripts/check-phase6-target-selection.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-intercept-planner.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-pursuit-state-machine.sh
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Validated the optimized phase-6 acceptance wrapper in both headless and GUI modes.

## Current blocker
None

## Next exact step
Review and commit the optimized phase-6 acceptance slice.

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
