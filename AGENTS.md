# AGENTS.md

## Repo Contract

- Treat [docs/phase-0-baseline.md](./docs/phase-0-baseline.md) as the active architecture contract.
- Do not redefine architecture, versions, namespace rules, CI model, or transport topology inside implementation tasks.
- Keep tasks narrow, reviewable, and acceptance-driven.
- Preserve the canonical Docker/Compose model shared by local execution and CI.
- Keep local-host and remote-CI behavior aligned: profiles may differ, but service names, images, environment model, and smoke-test assumptions must not drift.

## Phase Quick Reference

| Phase | Focus | Package | Acceptance Script |
|-------|-------|---------|-------------------|
| 1 | Single-vehicle scaffold | `iconom_control` | `./scripts/phase1-acceptance.sh` |
| 2 | Runtime separation | (validation only) | `./scripts/phase1-acceptance.sh` |
| 3 | Fixed-wing guidance | `iconom_guidance` | `./scripts/phase3-acceptance.sh` |
| 4 | Dual-aircraft | `iconom_*` (both vehicles) | `./scripts/phase4-acceptance.sh` |
| 5 | Server coordination | `iconom_competition` | `./scripts/phase5-acceptance.sh` |
| 6 | Pursuit/cueing | `iconom_guidance` | `./scripts/check-phase6-live-rival-geometry.sh` |
| 7 | Visual tracking + EKF fusion | `iconom_vision` + `iconom_competition` | `./scripts/check-phase7-*.sh` |

**Note on pre-Phase-7 EKF work**: Before Phase 7 visual tracking, implement EKF fusion combining 1 Hz referee data with 20 Hz live adapter to validate the fusion architecture.

**Always verify the relevant acceptance script passes before reporting a task complete.**

## Agent Command Mapping

Use the right tool for the job:

| Command | Use For |
|---------|---------|
| `/refactor` | ROS node refactoring, message changes, topic renaming, code structure improvements |
| `/playwright` | GUI verification, camera feed testing, visual confirmation, browser-based validation |
| `task(category="deep")` | New guidance algorithms, complex state machines, intercept planning, architecture decisions |
| `task(category="quick")` | Simple fixes, single-file changes, typo fixes, trivial modifications |
| `task(subagent_type="oracle")` | Debugging after 2+ failed attempts, unfamiliar patterns, multi-system tradeoffs |

**When in doubt**: Use `deep` category with acceptance criteria. Avoid `unspecified-*` categories — they produce worse results.

## High-Risk Files

Treat these as high-risk and change them only when the task explicitly requires it:

- `docker/`
- `.github/workflows/`
- Compose files
- simulator launch/config files
- bridge and networking configuration

## Task Rules

- Only edit files explicitly allowed by the task.
- Do not widen scope to "clean up" adjacent issues unless requested.
- Do not change the phase-0 baseline indirectly through implementation.
- Prefer project-owned images and the canonical stack over host-specific workarounds.

## Acceptance Rules

- Every implementation task must define concrete acceptance checks.
- Infrastructure-facing changes should include or preserve a smoke-test path.
- The smoke test is the primary gate for phase 1.

**The acceptance scripts ARE the agent interface.** End every task by running the relevant check script and confirming it passes.

## Out of Scope by Default

- Architecture changes
- Auto-merge behavior
- Source-build fallbacks for Gazebo or `ros_gz`
- Per-vehicle XRCE agent topologies
