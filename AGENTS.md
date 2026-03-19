# AGENTS.md

## Repo Contract

- Treat [docs/phase-0-baseline.md](./docs/phase-0-baseline.md) as the active architecture contract.
- Do not redefine architecture, versions, namespace rules, CI model, or transport topology inside implementation tasks.
- Keep tasks narrow, reviewable, and acceptance-driven.
- Preserve the canonical Docker/Compose model shared by local execution and CI.
- Keep local-host and remote-CI behavior aligned: profiles may differ, but service names, images, environment model, and smoke-test assumptions must not drift.

## High-Risk Files

Treat these as high-risk and change them only when the task explicitly requires it:

- `docker/`
- `.github/workflows/`
- Compose files
- simulator launch/config files
- bridge and networking configuration

## Task Rules

- Only edit files explicitly allowed by the task.
- Do not widen scope to “clean up” adjacent issues unless requested.
- Do not change the phase-0 baseline indirectly through implementation.
- Prefer project-owned images and the canonical stack over host-specific workarounds.

## Acceptance Rules

- Every implementation task must define concrete acceptance checks.
- Infrastructure-facing changes should include or preserve a smoke-test path.
- The smoke test is the primary gate for phase 1.

## Out of Scope by Default

- Architecture changes
- Auto-merge behavior
- Source-build fallbacks for Gazebo or `ros_gz`
- Per-vehicle XRCE agent topologies
