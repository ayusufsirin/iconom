# SESSION

## Goal
Phase 3 is complete and tagged. The immediate goal is to lock the phase-4 dual-aircraft baseline so implementation starts from a pinned isolation contract instead of ad hoc multi-vehicle changes.

## Current status
The repo has a validated single-vehicle stack with phase-1 acceptance and a tagged phase-3 guided-flight loop ending in auto landing. A new phase-4 planning doc now defines the dual-aircraft baseline around `plane_01` and `plane_02` with isolated IDs, ports, namespaces, and camera topics.

## Files touched
- `docs/phase-4-plan.md`
- `README.md`
- `SESSION.md`

## Last completed step
Defined the phase-4 dual-aircraft planning contract and linked it from the repo start-here docs.

## Current blocker
None

## Next exact step
Implement the phase-4 runtime contract for `plane_02`: explicit namespace, PX4 system id, XRCE key, MAVLink port, Gazebo model name, and camera topic root, before attempting a dual-aircraft launch.

## Validation
```bash
cd /home/joseph/Projects/iconom
./scripts/phase1-acceptance.sh --headless
./scripts/phase3-acceptance.sh --headless
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-nav-land.sh
```

## Notes
- `phase3-acceptance.sh` still ends on the landing slice for the single-aircraft baseline.
- Phase 4 is intentionally limited to dual-aircraft coexistence and isolation, not swarm coordination.
- Keep local `.env` and ROS build/install/log outputs untracked.
