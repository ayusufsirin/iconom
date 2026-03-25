# SESSION

## Goal
Extend the maintained phase-6 acceptance entrypoint so it can also run in GUI mode.

## Current status
`scripts/phase6-acceptance.sh` now supports both `--headless` and `--gui`. The maintained headless flow passes, and the GUI flow runs the same phase-6 sequence with the final live-rival cueing step visible in Gazebo.

## Files touched
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Validated the GUI-capable phase-6 acceptance wrapper with `xhost +local:docker` and `./scripts/phase6-acceptance.sh --gui`.

## Current blocker
None

## Next exact step
Review the uncommitted GUI-acceptance slice and commit it with a conventional commit if it still looks correct.

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
- GUI mode is only visually meaningful for the final live-rival cueing step; the earlier phase-6 checks remain non-visual.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
