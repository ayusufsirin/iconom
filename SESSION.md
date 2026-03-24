# SESSION

## Goal
Phase 3 is complete and tagged. The immediate goal is to extend the validated phase-4 dual-aircraft baseline from coexistence into independent control checks.

## Current status
The repo has a tagged single-aircraft guidance loop through landing, a validated phase-4 runtime contract for `plane_02`, and a passing live dual-aircraft isolation proof under the `phase4` profile. Both `plane_01` and `plane_02` now publish isolated PX4 ROS topics and isolated camera topics in the same world.

## Files touched
- `.env.example`
- `docker-compose.yml`
- `docker/px4/Dockerfile`
- `docker/px4/run-vehicle.sh`
- `docker/px4/run-single-vehicle.sh`
- `scripts/check-phase4-runtime-contract.sh`
- `scripts/check-phase4-isolation.sh`
- `README.md`
- `SESSION.md`

## Last completed step
Fixed the PX4 multi-instance launch path and validated `./scripts/check-phase4-isolation.sh` end to end.

## Current blocker
None

## Next exact step
Add the first phase-4 independent command check, starting with separate `VehicleCommand` or mode-change validation for `plane_01` and `plane_02` in one live run.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/phase1-acceptance.sh --headless
./scripts/phase3-acceptance.sh --headless
./scripts/check-phase4-runtime-contract.sh
./scripts/check-phase4-isolation.sh
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-nav-land.sh
```

## Notes
- `phase3-acceptance.sh` still ends on the landing slice for the single-aircraft baseline.
- Phase 4 is intentionally limited to dual-aircraft coexistence and isolation, not swarm coordination.
- `px4_plane_02` and `ros_gz_bridge_plane_02` stay profile-gated behind `phase4` so single-aircraft flows remain unchanged.
- Keep local `.env`, `QGroundControl-x86_64.AppImage`, `opencode.json`, and ROS build/install/log outputs untracked.
