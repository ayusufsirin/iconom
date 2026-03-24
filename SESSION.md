# SESSION

## Goal
Pin phase 6 before implementation so the next work stays bounded, acceptance-first, and consistent with the validated phase-5 server-aware substrate.

## Current status
Phase 5 is repaired and validated in git through the maintained headless acceptance path. The next source of truth is now `docs/phase-6-plan.md`, which defines deterministic target selection, bounded intercept planning, one pursuit state machine, and one camera-cueing proof as the phase-6 path.

## Files touched
- `docs/phase-6-plan.md`
- `README.md`
- `SESSION.md`

## Last completed step
Added the phase-6 planning baseline and linked it from the README so the next implementation slice starts from a pinned pursuit/cueing contract instead of ad hoc guidance code.

## Current blocker
None

## Next exact step
Implement the deterministic target-selection slice with one maintained check script and no aircraft guidance yet.

## Validation
- `cd /home/joseph/Projects/iconom && sed -n '1,240p' docs/phase-6-plan.md`
- `cd /home/joseph/Projects/iconom && rg -n "Phase 6 Next|phase-6-plan" README.md`

## Notes
- Keep phase 6 focused on pursuit guidance and camera cueing; visual lock logic is explicitly out of scope here.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of commits.
