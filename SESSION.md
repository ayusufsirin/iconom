# SESSION

## Goal
Phase 5.3 architecture closure — force a single final phase-5 history/prediction architecture and remove the alternative path.

## Architecture Decision
**Option A — Buffer-centered architecture** is the official maintained design:

- rival_buffer is the only maintained owner of buffered rival history
- predictor consumes rival_buffer's `/rival_buffer/history` topic output
- predictor does NOT maintain a competing long-lived raw-rival-state history path
- raw rival-state subscription exists ONLY inside rival_buffer

## Current status
Phase 5 is complete with a single, unambiguous architecture. The mock referee server, competition client, ownship telemetry adapter, rival history buffer, and predictor are all implemented and aligned with the official buffer-centered architecture.

## Files touched
- `docs/phase-5-plan.md` - updated predictor contract to consume from rival_buffer
- `README.md` - updated predictor description to match buffer-centered architecture
- `scripts/check-phase5-rival-history.sh` - now tests ROS pipeline: rival_buffer publishes to /rival_buffer/history
- `scripts/check-phase5-predictor.sh` - now tests ROS pipeline: predictor subscribes to /rival_buffer/history and publishes to /competition/prediction/rival_position

## Last completed step
Phase 5.3 architecture closure complete:
1. Chose Option A (buffer-centered architecture) as the single official design
2. Updated docs/phase-5-plan.md to reflect predictor consuming from `/rival_buffer/history`
3. Updated README.md to match the implemented architecture
4. Updated check-phase5-rival-history.sh to test ROS pipeline (not just HTTP)
5. Updated check-phase5-predictor.sh to test ROS pipeline (not just HTTP)
6. Verified predictor.py correctly subscribes to `/rival_buffer/history` (PoseArray)
7. Verified rival_buffer.py is the only component subscribing to raw `/competition/rival/state`
8. All acceptance tests pass - tests now prove the ROS pipeline works

## Current blocker
None

## Next exact step
Phase 6 is now ready to start. The phase-5 stack has exactly one truthful source of rival history for prediction.

## Validation
- `cd /home/joseph/Projects/iconom && ./scripts/phase5-acceptance.sh --headless`

## Notes
- Keep `QGroundControl-x86_64.AppImage` and `opencode.json` out of commits.
- Phase 5 remains simulation-only with no hardware, reporting, or vision lock logic.
- Competition client default behavior: subscribes to `/competition/ownship/state` for live telemetry
- Competition client fixture mode: set `COMPETITION_FIXTURE_MODE=true` for testing without full PX4 stack
- Predictor official input: `/rival_buffer/history` (PoseArray from rival_buffer)
- Rival buffer official input: `/competition/rival/state` (PoseStamped from competition_client)
- Acceptance tests now verify the full ROS pipeline
