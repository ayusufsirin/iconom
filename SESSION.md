# SESSION

## Goal
Run the first five-case phase-6 PD tuning batch on the fixed live-rival route and preserve every CSV/CZML artifact for visual review.

## Current status
The maintained live-rival check now forwards `range_damping_gain`, and the repo has a dedicated `run-phase6-pd-sweep.sh` batch runner that executes exactly the planned five parameter cases while preserving per-run logs, CSV files, CZML exports, and a summary table.

## Files touched
- /home/joseph/Projects/iconom/scripts/check-phase6-live-rival-geometry.sh
- /home/joseph/Projects/iconom/scripts/run-phase6-pd-sweep.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Implemented the maintained PD sweep runner and wired the live-rival check so the damping term is now runtime-tunable.

## Current blocker
None. The next step is to run the planned five cases and stop for review.

## Next exact step
```bash
cd /home/joseph/Projects/iconom
./scripts/run-phase6-pd-sweep.sh --incremental
```

## Validation
```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/run-phase6-pd-sweep.sh
```

```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/check-phase6-live-rival-geometry.sh
```

```bash
cd /home/joseph/Projects/iconom
git diff --check
```

## Notes
- The first batch is intentionally limited to five runs: sharp underdamped, mild underdamped, midpoint, mild overdamped, and strong overdamped.
- The runner preserves each run under `ros2_ws/phase6-pd-sweep-*/run*/` and does not automatically continue beyond that batch.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*` artifacts out of git.
