# SESSION

## Goal
Package the current phase-6 pursuit-guidance baseline behind one maintained acceptance entrypoint.

## Current status
`scripts/phase6-acceptance.sh` is implemented and the maintained headless phase-6 flow now runs target selection, intercept planning, pursuit state transitions, and live-rival cueing in sequence. The live-rival cueing slice remains validated in both headless and GUI mode.

## Files touched
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-target-selection.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-intercept-planner.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-pursuit-state-machine.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Validated the maintained phase-6 acceptance wrapper with `./scripts/phase6-acceptance.sh --headless`.

## Current blocker
None

## Next exact step
Review the uncommitted phase-6 acceptance slice and commit it with a conventional commit if it still looks correct.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/phase6-acceptance.sh --headless
```

```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-cueing.sh
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-cueing.sh
```

## Notes
- The maintained phase-6 acceptance path stays headless; GUI remains useful for the live-rival cueing slice itself.
- The first cold acceptance run rebuilds `px4_msgs` inside the throwaway `ros2_app` containers, so it takes several minutes before the fast guidance checks finish.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
