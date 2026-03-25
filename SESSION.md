# SESSION

## Goal
Keep the phase-6 build path incremental by default so maintained checks stop forcing cold ROS workspace rebuilds unless explicitly requested.

## Current status
Phase-6 scripts now default to incremental workspace reuse and accept `--cold` only when a clean rebuild is actually desired. The maintained headless wrapper `./scripts/phase6-acceptance.sh --headless` passes after the change, and the live-rival cueing slice also passes with `./scripts/check-phase6-live-rival-cueing.sh --incremental`.

## Files touched
- /home/joseph/Projects/iconom/scripts/phase6-acceptance.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-target-selection.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-intercept-planner.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-pursuit-state-machine.sh
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-cueing.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Switched phase-6 checks and the maintained wrapper to incremental-by-default workspace builds, reran the maintained headless acceptance, and confirmed that the lightweight checks reuse the prepared workspace while the live-rival cueing slice still passes.

## Current blocker
None

## Next exact step
None

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-live-rival-cueing.sh --incremental
```

```bash
cd /home/joseph/Projects/iconom
./scripts/phase6-acceptance.sh --headless
```

## Notes
- Phase-6 builds are incremental by default; use `--cold` only for an intentional clean rebuild.
- The lightweight phase-6 checks now reuse the prepared workspace when invoked through `phase6-acceptance.sh`.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
