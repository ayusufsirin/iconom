# POLICY

## Engineering Style
- Prefer minimal, scoped changes that preserve the current architecture.
- Reuse the maintained scripts and ROS packages before adding new entrypoints.
- Keep phase work truthful: do not claim a capability until the maintained validation proves it.
- Use sub-agents for bounded test/review tasks when that reduces coordination cost.

## Change Boundaries
- Avoid unrelated refactors, renames, or formatting churn.
- Do not broaden phase scope just because the stack can be extended.
- Preserve the existing namespace, port, system-id, XRCE-key, and compose conventions unless a validated change requires otherwise.
- Keep local untracked artifacts out of git.

## Validation
- Verify before claiming completion.
- Prefer the maintained acceptance/check scripts over ad hoc commands.
- For runtime changes, validate the narrow slice first, then rerun the packaged acceptance path when it exists.
- When GUI behavior matters, confirm it separately from headless validation.

## Git Safety
- Commit only the files that belong to the current slice.
- Use conventional commit messages.
- Do not rewrite history or revert unrelated user changes.
- Do not commit until the claimed validation has actually passed.

## Security
- Do not add secrets, tokens, host-specific credentials, or private local artifacts to the repo.
- Keep environment changes scoped to the project and documented in tracked files when they are part of the contract.
- Treat host-level package, Docker, or display changes as operational actions, not repo changes.

## Handoff Rules
- Keep SESSION.md short, current, and fully replace stale content.
- Record the immediate goal, exact current status, concrete next step, and copy-paste validation commands.
- State blockers explicitly; if none, say None.
- Update SESSION.md at meaningful stopping points and before ending with an uncommitted slice.
