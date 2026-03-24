# SESSION

## Goal
Tighten the phase-4 dual-aircraft GUI baseline so both aircraft spawn cleanly and the maintained operator path matches the validated runtime shape.

## Current status
The repo has a tagged single-aircraft guidance loop through landing, passing phase-4 runtime/isolation/command/mode/nav proofs, and a maintained `phase4-acceptance.sh` entrypoint that passes end to end. The active slice adds explicit phase-4 spawn-height control plus a maintained dual-aircraft GUI bring-up path.

## Files touched
- `.env.example`
- `docker-compose.yml`
- `scripts/bringup-phase4-gui.sh`
- `README.md`
- `docs/phase-4-plan.md`
- `SESSION.md`

## Last completed step
Added and validated the bounded dual-aircraft nav-isolation proof, then reran `./scripts/phase4-acceptance.sh --headless` successfully.

## Current blocker
None

## Next exact step
Run `./scripts/phase4-acceptance.sh --headless`, then launch `./scripts/bringup-phase4-gui.sh` and visually confirm the adjusted spawn height for both aircraft.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/phase4-acceptance.sh --headless
./scripts/bringup-phase4-gui.sh
```

## Notes
- Phase 4 is still limited to dual-aircraft coexistence and isolation, not swarm coordination.
- `px4_plane_02` and `ros_gz_bridge_plane_02` stay profile-gated behind `phase4` so single-aircraft flows remain unchanged.
- Phase-4 GUI uses explicit `PLANE_01_PX4_GZ_MODEL_POSE` and `PLANE_02_PX4_GZ_MODEL_POSE` values from `.env.example`.
- Keep local `.env`, `QGroundControl-x86_64.AppImage`, `opencode.json`, and ROS build/install/log outputs untracked.
