# SESSION

## Goal
Implement the third phase-6 slice: a deterministic pursuit state machine that coordinates selected-target and intercept-target inputs without commanding the aircraft yet.

## Current status
The `iconom_guidance` package now contains `pursuit_state_machine`, and the maintained check passes end to end. The node publishes `/guidance/pursuit_state` and republishes `/guidance/pursuit_goal` only while in `pursue`.

## Files touched
- `/home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/setup.py`
- `/home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/package.xml`
- `/home/joseph/Projects/iconom/ros2_ws/src/iconom_guidance/iconom_guidance/pursuit_state_machine.py`
- `/home/joseph/Projects/iconom/scripts/check-phase6-pursuit-state-machine.sh`
- `/home/joseph/Projects/iconom/README.md`
- `/home/joseph/Projects/iconom/SESSION.md`

## Last completed step
Validated the pursuit-state-machine slice with `./scripts/check-phase6-pursuit-state-machine.sh`, including the deterministic transition sequence `idle -> search -> pursue -> reacquire -> idle`.

## Current blocker
None

## Next exact step
Commit the pursuit-state-machine slice after review, then start the phase-6 camera-cueing slice.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase6-pursuit-state-machine.sh
```

## Notes
- The maintained check explicitly refreshes the selected target once after `pursue` so `reacquire` and later `idle` are asserted in a deterministic order.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, and `opencode.json.home_network` out of git.
