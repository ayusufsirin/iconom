# SESSION

## Goal
Phase 3 is complete and tagged. The immediate goal is to package the validated phase-4 dual-aircraft baseline into one maintained acceptance path.

## Current status
The repo has a tagged single-aircraft guidance loop through landing, a validated phase-4 runtime contract for `plane_02`, a passing live dual-aircraft isolation proof, and a passing dual-aircraft command-isolation proof. `plane_01` and `plane_02` now coexist in one world with isolated PX4 ROS topics, isolated camera topics, and separate arm targeting.

## Files touched
- `scripts/check-phase4-command-isolation.sh`
- `README.md`
- `SESSION.md`

## Last completed step
Added and validated `./scripts/check-phase4-command-isolation.sh` end to end.

## Current blocker
None

## Next exact step
Add `scripts/phase4-acceptance.sh` that runs the maintained phase-4 runtime contract, telemetry/camera isolation, and command-isolation proofs in sequence.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/check-phase4-runtime-contract.sh
./scripts/check-phase4-isolation.sh
./scripts/check-phase4-command-isolation.sh
./scripts/phase3-acceptance.sh --headless
```

## Notes
- Phase 4 is still limited to dual-aircraft coexistence and isolation, not swarm coordination.
- `px4_plane_02` and `ros_gz_bridge_plane_02` stay profile-gated behind `phase4` so single-aircraft flows remain unchanged.
- Keep local `.env`, `QGroundControl-x86_64.AppImage`, `opencode.json`, and ROS build/install/log outputs untracked.
