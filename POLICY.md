# POLICY

## Engineering Style
- Prefer minimal, scoped changes that preserve the current PX4/Gazebo/ROS architecture.
- Extend the existing script-driven flow instead of adding parallel ad hoc entrypoints.
- Keep docs short and operational; update them only when behavior or operator flow changes.

## Change Boundaries
- Avoid unrelated refactors, renames, or layout changes while shipping a slice.
- Do not replace the current Compose-based runtime model unless a concrete blocker requires it.
- Keep phase work incremental: prove one behavior end to end before adding complexity.

## Validation
- Verify behavior with the maintained repo scripts before claiming completion.
- Prefer end-to-end checks over static inspection when runtime behavior is the point of the slice.
- If a maintained acceptance path changes, rerun it before handoff.

## Git Safety
- Do not rewrite published history or revert user/other-agent work without explicit direction.
- Commit only cohesive changes with a conventional commit message.
- Leave the worktree clean at phase boundaries when practical.

## Security
- Never commit secrets, tokens, local `.env` files, or generated workspace artifacts.
- Do not weaken container or host settings beyond what the current slice requires.
- Keep host-specific setup out of tracked files unless it is required for the maintained operator flow.

## Handoff Rules
- Keep `SESSION.md` short, current, and based on the actual repo state.
- Rewrite `SESSION.md` instead of appending history.
- State one exact next step, or `None` when the active task is fully complete.
