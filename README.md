# iconom

This repository will host a PX4 + Gazebo + ROS 2 simulation stack for a fixed-wing FPV vehicle, with a path toward swarm simulation and automated agent-assisted development.

Phase 0 is documentation-first. No implementation should begin until the baseline decisions in the phase-0 document are either accepted or updated deliberately.

## Start Here

- [Phase 0 Baseline](./docs/phase-0-baseline.md)
- [Phase 1 Scaffold](./docs/phase-1-scaffold.md)
- [Phase 1 Integration](./docs/phase-1-integration.md)
- [Phase 2 Plan](./docs/phase-2-plan.md)
- [Phase 3 Plan](./docs/phase-3-plan.md)
- [Phase 4 Plan](./docs/phase-4-plan.md)
- [Phase 5 Plan](./docs/phase-5-plan.md)
- [Phase 6 Controller Scheme](./docs/phase-6-controller.md)
- [Agent Rules](./AGENTS.md)
- [Task Template](./docs/task-template.md)
- [Canonical Compose Stack](./docker-compose.yml)
- [Smoke Script](./scripts/smoke.sh)
- [Single-Vehicle Integration Script](./scripts/integration-single-vehicle.sh)
- [Single-Vehicle Bring-Up Script](./scripts/bringup-single-vehicle.sh)
- [Single-Vehicle GUI Bring-Up Script](./scripts/bringup-single-vehicle-gui.sh)
- [Phase 4 GUI Bring-Up Script](./scripts/bringup-phase4-gui.sh)
- [Phase 1 Launch Script](./scripts/phase1-launch.sh)
- [Phase 1 Acceptance Script](./scripts/phase1-acceptance.sh)
- [Phase 3 Acceptance Script](./scripts/phase3-acceptance.sh)
- [Phase 4 Runtime Contract Check Script](./scripts/check-phase4-runtime-contract.sh)
- [Phase 4 Isolation Check Script](./scripts/check-phase4-isolation.sh)
- [Phase 4 Command Isolation Check Script](./scripts/check-phase4-command-isolation.sh)
- [Phase 4 Mode Isolation Check Script](./scripts/check-phase4-mode-isolation.sh)
- [Phase 4 Nav Isolation Check Script](./scripts/check-phase4-nav-isolation.sh)
- [Phase 4 Dual Nav Loop Check Script](./scripts/check-phase4-dual-nav-loop.sh)
- [Phase 4 Acceptance Script](./scripts/phase4-acceptance.sh)
- [Phase 5 Referee Server Check Script](./scripts/check-phase5-referee-server.sh)
- [PX4 Telemetry Check Script](./scripts/check-px4-telemetry.sh)
- [Camera Bridge Check Script](./scripts/check-camera-bridge.sh)
- [Camera Subscriber Check Script](./scripts/check-camera-subscriber.sh)
- [Vehicle Command Check Script](./scripts/check-vehicle-command.sh)
- [Mode Command Check Script](./scripts/check-mode-command.sh)
- [Offboard Readiness Check Script](./scripts/check-offboard-readiness.sh)
- [Offboard Movement Check Script](./scripts/check-offboard-movement.sh)
- [Nav Takeoff Check Script](./scripts/check-nav-takeoff.sh)
- [Nav Loiter Check Script](./scripts/check-nav-loiter.sh)
- [Nav Reposition Check Script](./scripts/check-nav-reposition.sh)
- [Nav Route Check Script](./scripts/check-nav-route.sh)
- [Nav Land Check Script](./scripts/check-nav-land.sh)
- [Source Chat Export](./ChatGPT-Gazebo_PX4_FPV_Setup.md)

## Current Slice

All five maintained service slices now exist: `xrce_agent`, `ros2_app`, `px4`, `gazebo`, and `ros_gz_bridge`. The current integrated milestone is no longer basic service availability. The repo now has a truthful one-vehicle runtime, PX4 telemetry discovery, and a maintained Gazebo camera bridge into ROS 2.

This repo requires Docker Compose v2 via `docker compose`.

The first integrated baseline is now `plane_01` via [integration-single-vehicle.sh](./scripts/integration-single-vehicle.sh). It validates the shared one-vehicle launch contract without claiming full PX4-in-Gazebo vehicle runtime yet.

The maintained one-vehicle runtime is [bringup-single-vehicle.sh](./scripts/bringup-single-vehicle.sh). It starts the standalone `gazebo` service first, keeps `xrce_agent`, `ros2_app`, and `ros_gz_bridge` as companion services, and launches PX4 in external Gazebo-attachment mode.

The local integrated aircraft GUI path is [bringup-single-vehicle-gui.sh](./scripts/bringup-single-vehicle-gui.sh). It uses the local override stack to route X11 into the separated runtime and forces `PX4_HEADLESS=0`.

The canonical operator entrypoint is now [phase1-launch.sh](./scripts/phase1-launch.sh). It selects the maintained phase-1 runtime path in either headless or GUI mode without changing the underlying one-vehicle contract.

The canonical validation entrypoint is now [phase1-acceptance.sh](./scripts/phase1-acceptance.sh). It chains the maintained phase-1 checks for telemetry, camera bridge, camera subscriber, command path, mode change, offboard readiness, and offboard movement.

The next narrow milestone is [check-px4-telemetry.sh](./scripts/check-px4-telemetry.sh), which attempts to observe one PX4 telemetry topic under `/plane_01/fmu/out/...` during the current runtime path.

For this telemetry step, the ROS workspace now carries a pinned [px4_msgs.repos](./ros2_ws/src/px4_msgs.repos) manifest so `ros2_app` can build the minimum PX4 message package needed for telemetry type and topic discovery.

The current camera milestone is [check-camera-bridge.sh](./scripts/check-camera-bridge.sh). It validates one forward camera on the `gz_rc_cessna` runtime and proves that:

- Gazebo publishes the live camera image and camera-info topics,
- the maintained `ros_gz_bridge` service stays alive alongside the separated runtime,
- ROS 2 sees `/plane_01/camera/image_raw` and `/plane_01/camera/camera_info`.

The next ROS-side proof is [check-camera-subscriber.sh](./scripts/check-camera-subscriber.sh). It builds the minimal `iconom_vision` package in `ros2_ws`, launches a subscriber in `ros2_app`, and verifies that one bridged image frame is actually received.

The next control-side proof is [check-vehicle-command.sh](./scripts/check-vehicle-command.sh). It builds the minimal `iconom_control` package in `ros2_ws`, publishes one `VehicleCommand` on `/plane_01/fmu/in/vehicle_command`, and requires a matching `VehicleCommandAck` on `/plane_01/fmu/out/vehicle_command_ack`.

The control check now supports both `disarm` and `arm` via `PX4_COMMAND_NAME`. For the current `gz_rc_cessna` phase-1 baseline, the PX4 image overrides two airframe defaults to make SITL arming achievable without a GCS or physical airspeed requirement:

- `NAV_DLL_ACT=0`
- `SYS_HAS_NUM_ASPD=0`

The next control proof is [check-mode-command.sh](./scripts/check-mode-command.sh). It waits for a preflight-ready `VehicleStatus`, arms through the existing command path, publishes one ROS-side mode request, and requires the resulting `VehicleStatus.nav_state` change on `/plane_01/fmu/out/vehicle_status_v1`.

The first validated mode for this phase-1 baseline is `mode_loiter`, which maps to `NAVIGATION_STATE_AUTO_LOITER`. `STAB` is intentionally not the first validated mode because PX4 requires manual-control availability for that mode in this SITL state.

The next control proof is [check-offboard-readiness.sh](./scripts/check-offboard-readiness.sh). It starts a repo-owned offboard hold publisher, streams `OffboardControlMode` plus `TrajectorySetpoint` on `/plane_01/fmu/in/...`, requests `mode_offboard`, and requires `VehicleStatus.nav_state=14`.

The current offboard milestone is intentionally narrow: it proves offboard entry readiness and a steady hold-style setpoint stream. It does not yet claim waypointing, trajectory logic, or fixed-wing mission behavior.

The next control proof is [check-offboard-movement.sh](./scripts/check-offboard-movement.sh). It uses a fixed-wing-compatible offboard primitive, `body_rate + thrust`, requests `mode_offboard`, and requires a bounded planar `VehicleLocalPosition` response while `VehicleStatus` remains in `nav_state=14`.

This movement result matters because fixed-wing position-style offboard from rest remains grounded by PX4's landed handling. The first real movement primitive in this SITL baseline is therefore rate/thrust offboard, not a position-step takeoff.

The first phase-3 guidance proof is [check-nav-takeoff.sh](./scripts/check-nav-takeoff.sh). It uses a PX4-native navigation command instead of raw offboard motion, seeds a bounded target from live `/plane_01/fmu/out/vehicle_global_position`, sends `NAV_TAKEOFF`, and requires both `VehicleStatus.nav_state=AUTO_TAKEOFF` and real takeoff motion in `VehicleLocalPosition`.

The intermediate phase-3 loiter proof is [check-nav-loiter.sh](./scripts/check-nav-loiter.sh). It chains a bounded `NAV_TAKEOFF` into an in-flight `mode_loiter` transition, requires `VehicleStatus.nav_state=AUTO_LOITER`, and verifies continued motion while PX4 remains in loiter guidance.

The current phase-3 guidance proof is [check-nav-reposition.sh](./scripts/check-nav-reposition.sh). It chains `NAV_TAKEOFF`, airborne `mode_loiter`, and `DO_REPOSITION`, requires `VehicleStatus` to remain in `AUTO_LOITER`, and verifies that `VehicleGlobalPosition` approaches the commanded reposition target.

The current phase-3 route proof is [check-nav-route.sh](./scripts/check-nav-route.sh). It keeps the same `NAV_TAKEOFF` and airborne `mode_loiter` chain, then sends two bounded `DO_REPOSITION` targets and verifies that `VehicleGlobalPosition` approaches both commanded route points while `VehicleStatus` remains in `AUTO_LOITER`.

The closing phase-3 guidance proof is [check-nav-land.sh](./scripts/check-nav-land.sh). It keeps the same `NAV_TAKEOFF` and airborne `mode_loiter` chain, then sends `NAV_LAND`, requires `VehicleStatus.nav_state=AUTO_LAND`, verifies real descent in `VehicleLocalPosition`, and waits for `/plane_01/fmu/out/vehicle_land_detected` to report `landed=true`.

The canonical validation entrypoint for the current phase-3 slice is [phase3-acceptance.sh](./scripts/phase3-acceptance.sh). It now runs the maintained landing proof in either headless or GUI mode.

## Local Gazebo GUI

The canonical stack remains headless in [docker-compose.yml](./docker-compose.yml). Local host GUI behavior is added only through [docker-compose.override.yml](./docker-compose.override.yml).

To run Gazebo with a local GUI from the repo root:

```bash
xhost +local:docker
docker compose up gazebo
```

To force the canonical headless path even on the local host:

```bash
docker compose -f docker-compose.yml up gazebo
```

## Phase 1 Daily Use

Headless launch:

```bash
./scripts/phase1-launch.sh --headless
```

Integrated aircraft GUI launch:

```bash
xhost +local:docker
./scripts/phase1-launch.sh --gui
```

Headless acceptance:

```bash
./scripts/phase1-acceptance.sh --headless
```

GUI acceptance:

```bash
xhost +local:docker
./scripts/phase1-acceptance.sh --gui
```

## Phase 3 Daily Use

Headless guidance acceptance:

```bash
./scripts/phase3-acceptance.sh --headless
```

GUI guidance acceptance:

```bash
xhost +local:docker
./scripts/phase3-acceptance.sh --gui
```

## Phase 0 Goal

Freeze the minimum set of architectural decisions required to let future coding agents work in isolation without redefining the project on every task.

## Phase 2 Direction

Phase 2 started from the tagged `phase1-baseline` and kept the same single-vehicle contract while removing the largest remaining architectural compromise: Gazebo is now the first-class standalone runtime service for the maintained stack.

The current phase-2 source of truth is [phase-2-plan.md](./docs/phase-2-plan.md).

## Phase 3 Direction

Phase 3 starts from the tagged `phase2-runtime-separation` state and keeps the same single-vehicle contract while adding the first bounded fixed-wing guidance primitive above the current raw movement layer.

The current phase-3 source of truth is [phase-3-plan.md](./docs/phase-3-plan.md).

The validated phase-3 guidance chain is now `NAV_TAKEOFF`, airborne `mode_loiter`, bounded route progression, and `NAV_LAND`. That is enough to call phase 3 closed at the single-aircraft guidance level.


## Phase 4 Direction

Phase 4 starts from the tagged `phase3-guidance-loop` state and keeps the existing single-aircraft guidance baseline intact while adding `plane_02` as the first maintained multi-vehicle increment.

The current phase-4 source of truth is [phase-4-plan.md](./docs/phase-4-plan.md).

The phase-4 goal is not swarm behavior. It is a truthful dual-aircraft isolation proof:

- `plane_01` and `plane_02` in one world,
- separate PX4 identities, XRCE keys, MAVLink ports, ROS namespaces, and camera topics,
- independent commandability,
- one maintained acceptance path for coexistence.

The phase-4 runtime contract guard is [check-phase4-runtime-contract.sh](./scripts/check-phase4-runtime-contract.sh). It pins the explicit `plane_02` runtime contract in env, compose, and PX4 runtime checks so multi-vehicle work stays aligned with the agreed namespace, identity, and port rules.

The first live phase-4 runtime proof is [check-phase4-isolation.sh](./scripts/check-phase4-isolation.sh). It brings up `plane_01` and `plane_02` together under the `phase4` compose profile and verifies that both telemetry roots and both camera topic roots appear in ROS 2 without namespace collisions.

The first phase-4 control proof is [check-phase4-command-isolation.sh](./scripts/check-phase4-command-isolation.sh). It reuses the same dual-aircraft runtime, arms `plane_01` without changing `plane_02`, then arms `plane_02` independently and verifies that both aircraft keep separate armed-state transitions.

The next phase-4 control proof is [check-phase4-mode-isolation.sh](./scripts/check-phase4-mode-isolation.sh). It reuses the same dual-aircraft runtime, arms both aircraft, starts namespaced offboard publishers, sends `mode_offboard` to `plane_01` without changing `plane_02`, then sends `mode_offboard` to `plane_02` independently and verifies that both aircraft keep separate mode-state transitions.

The next phase-4 control proof is [check-phase4-nav-isolation.sh](./scripts/check-phase4-nav-isolation.sh). It keeps `plane_02` disarmed, runs the bounded `NAV_TAKEOFF` -> `mode_loiter` -> `DO_REPOSITION` chain on `plane_01`, and verifies that the repositioned aircraft moves toward its commanded target without mutating `plane_02`.

The maintained phase-4 entrypoint is [phase4-acceptance.sh](./scripts/phase4-acceptance.sh). It runs the current dual-aircraft contract, isolation, command-isolation, mode-isolation, and nav-isolation proofs in sequence.

The maintained dual-aircraft GUI path is [bringup-phase4-gui.sh](./scripts/bringup-phase4-gui.sh). It keeps one Gazebo window open with `plane_01` and `plane_02` attached to the same world and uses explicit phase-4 spawn poses so both aircraft start at the rc_cessna model's native ground-contact height instead of visually clipping into it.

The next phase-4 navigation proof is [check-phase4-dual-nav-loop.sh](./scripts/check-phase4-dual-nav-loop.sh). It keeps one shared dual-aircraft runtime, runs the bounded phase-3-style `NAV_TAKEOFF` -> `mode_loiter` -> `NAV_LAND` loop for `plane_01`, confirms `plane_02` stayed untouched, then runs the same loop for `plane_02` in the same sim.

## Phase 5 Direction

Phase 5 starts from the tagged `phase4-dual-aircraft-baseline` state and keeps the existing dual-aircraft coexistence baseline intact while adding the first server-aware two-aircraft substrate.

The current phase-5 source of truth is [phase-5-plan.md](./docs/phase-5-plan.md).

The phase-5 goal is not intercept execution or weapon engagement. It is a truthful server-aware coordination and bounded prediction proof:

- mock referee server runs alongside dual-aircraft runtime,
- competition client connects to referee and exchanges aircraft state,
- ownship telemetry adapter bridges PX4 telemetry to competition format,
- rival history buffer stores observed rival state history,
- predictor computes bounded trajectory predictions from history.

The phase-5 mock referee contract pins `iconom_referee` as the package name, `referee_server.py` as the server script, and port `45678` as the default communication channel.

The phase-5 competition client contract pins `iconom_competition` as the package name, `competition_client.py` as the client script, and `/competition/rival/state` and `/competition/ownship/state` as the primary ROS topics.

The phase-5 ownship adapter contract pins `iconom_telemetry_adapter` as the package name, `ownship_adapter.py` as the adapter script, and `/competition/ownship/state` as the output topic fed by `/plane_01/fmu/out/vehicle_local_position`.

The phase-5 rival buffer contract pins `iconom_rival_buffer` as the package name, `rival_buffer.py` as the buffer script, and `/rival_buffer/history` as the output topic with a default 60-sample rolling buffer.

The phase-5 predictor contract pins `iconom_predictor` as the package name, `predictor.py` as the predictor script, and `/competition/prediction/rival_position` as the output topic with a default 2-second prediction horizon.

The phase-5 referee server implementation is in [sim/referee_server/referee_server.py](./sim/referee_server/referee_server.py). It provides deterministic endpoints:

- `GET /health` - returns `{"status": "ok", "service": "referee"}`
- `GET /time` - returns deterministic server time
- `POST /login` - accepts fixture credentials `{"username":"test_pilot","password":"test_pass_123"}`, returns session token
- `POST /telemetry` - accepts ownship payload, returns deterministic rival state

To run the referee server check:

```bash
./scripts/check-phase5-referee-server.sh
```

Or via Docker:

```bash
docker compose --profile phase5 up referee_server
```

The phase-5 competition client implementation is in [ros2_ws/src/iconom_competition](./ros2_ws/src/iconom_competition). It provides a ROS 2 node that:

- subscribes to `/competition/ownship/state` for live ownship telemetry from the adapter
- authenticates with the mock referee server
- requests server time
- sends telemetry packets to the referee
- publishes parsed rival state to `/competition/rival/state`

By default, the competition client expects live ownship telemetry from the ownship telemetry adapter. To run in fixture-only mode (for testing without the full PX4 stack), set `COMPETITION_FIXTURE_MODE=true`.

To run the competition client check:

```bash
./scripts/check-phase5-competition-client.sh
```

The maintained check now starts the compose-backed `referee_server`, launches the real `competition_client` with fixture mode disabled, injects one ownship pose on `/competition/ownship/state`, and requires referee-backed rival-state output before it passes.

The phase-5 ownship telemetry adapter is in [ros2_ws/src/iconom_competition/iconom_competition/ownship_telemetry_adapter.py](./ros2_ws/src/iconom_competition/iconom_competition/ownship_telemetry_adapter.py). It provides a ROS 2 node that:

- subscribes to `/${aircraft_id}/fmu/out/vehicle_local_position` for live PX4 state (`plane_01` by default)
- maps the live position and velocity to competition telemetry format
- authenticates with the mock referee server
- sends telemetry packets at 1-second intervals

To run the telemetry adapter check:

```bash
./scripts/check-phase5-telemetry-adapter.sh
```

The maintained check now starts the compose-backed `referee_server`, launches the real `ownship_telemetry_adapter`, injects one PX4-shaped `VehicleLocalPosition`, and requires both `/competition/ownship/state` output and a real referee-backed telemetry exchange before it passes.

The phase-5 rival history buffer is in [ros2_ws/src/iconom_competition/iconom_competition/rival_buffer.py](./ros2_ws/src/iconom_competition/iconom_competition/rival_buffer.py). It provides a ROS 2 node that:

- subscribes to `/competition/rival/state` for rival state updates
- maintains a rolling buffer of 60 samples (configurable via `RIVAL_BUFFER_SIZE`)
- stores position, orientation, and timestamp for each sample
- publishes history to `/rival_buffer/history` for inspection

To run the rival history buffer check:

```bash
./scripts/check-phase5-rival-history.sh
```

The maintained check now launches the real `rival_buffer`, injects multiple rival `PoseStamped` samples on `/competition/rival/state`, and requires buffered `PoseArray` output on `/rival_buffer/history` before it passes.

The phase-5 predictor is in [ros2_ws/src/iconom_competition/iconom_competition/predictor.py](./ros2_ws/src/iconom_competition/iconom_competition/predictor.py). It provides a ROS 2 node that:

- subscribes to `/competition/rival/state` for rival state updates
- maintains an internal rolling history buffer for prediction
- publishes predicted rival position to `/competition/prediction/rival_position`
- uses a configurable prediction horizon (default 2 seconds)

To run the predictor check:

```bash
./scripts/check-phase5-predictor.sh
```

The maintained check now launches the real `predictor`, injects multiple rival-state samples, and requires a prediction on `/competition/prediction/rival_position` that advances beyond the last injected sample before it passes.

## Phase 5 Daily Use

The maintained phase-5 acceptance entrypoint is [phase5-acceptance.sh](./scripts/phase5-acceptance.sh). It runs all phase-5 checks in sequence:

```bash
./scripts/phase5-acceptance.sh --headless
```

The repaired headless acceptance path now passes through the real referee, competition client, telemetry adapter, rival buffer, and predictor checks instead of the earlier fixture-only shortcuts.

## Phase 6 Next

The source-of-truth planning document for the next phase is [docs/phase-6-plan.md](./docs/phase-6-plan.md).

Phase 6 is intentionally narrower than a full fighter round. It starts with deterministic target selection, then adds bounded intercept planning, one pursuit state machine, scripted cueing, and a maintained live-rival cueing proof before any visual lock logic.

The maintained acceptance entrypoint for the current phase-6 baseline is:

```bash
./scripts/phase6-acceptance.sh --headless
```

Phase-6 builds are incremental by default. Use `--cold` only when you want a clean rebuild of the ROS workspace.

To run the maintained phase-6 acceptance flow with GUI for the final live-rival cueing step:

```bash
xhost +local:docker
./scripts/phase6-acceptance.sh --gui
```

To force a clean rebuild before the maintained flow, run `./scripts/phase6-acceptance.sh --headless --cold` or `./scripts/phase6-acceptance.sh --gui --cold`.

## Phase 6 Target Selection

The first phase-6 slice is the deterministic target selector in [ros2_ws/src/iconom_guidance](./ros2_ws/src/iconom_guidance). It consumes maintained ownship and rival `PoseStamped` topics, chooses the nearest rival deterministically, and publishes the current selection on `/guidance/selected_target`.

To run the target-selection check:

```bash
./scripts/check-phase6-target-selection.sh
```

The maintained check launches the real selector, injects controlled ownship and rival states, and requires deterministic selection plus reselection before it passes.

## Phase 6 Intercept Planner

The second phase-6 slice is the bounded intercept planner in [ros2_ws/src/iconom_guidance](./ros2_ws/src/iconom_guidance). It consumes ownship state, the selected rival, and the predicted rival position, then publishes a bounded intercept target on `/guidance/intercept_target`.

To run the intercept-planner check:

```bash
./scripts/check-phase6-intercept-planner.sh
```

The maintained check launches the real planner, injects controlled ownship and predicted-target inputs, and requires both clamp-to-bound behavior and in-bounds passthrough behavior before it passes.

## Phase 6 Pursuit State Machine

The third phase-6 slice is the pursuit state machine in [ros2_ws/src/iconom_guidance](./ros2_ws/src/iconom_guidance). It consumes the selected target and bounded intercept target, publishes the current pursuit state on `/guidance/pursuit_state`, and republishes the pursuit goal on `/guidance/pursuit_goal` only while the machine is in `pursue`.

To run the pursuit-state-machine check:

```bash
./scripts/check-phase6-pursuit-state-machine.sh
```

The maintained check launches the real state machine and requires the deterministic transition sequence `idle -> search -> pursue -> reacquire -> idle` from controlled topic inputs.

## Phase 6 Camera Cueing

The fourth phase-6 slice is the first aircraft cueing proof in [ros2_ws/src/iconom_guidance](./ros2_ws/src/iconom_guidance). It keeps the maintained phase-5/phase-6 guidance inputs, then uses a repo-owned offboard body-rate controller to steer `plane_01` so the selected rival moves into the forward camera cone.

To run the headless camera-cueing check:

```bash
./scripts/check-phase6-camera-cueing.sh
```

To run the GUI camera-cueing check:

```bash
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-camera-cueing.sh
```

The maintained check now proves:
- `plane_01` takes off and stabilizes
- a deterministic scripted rival is injected into the guidance path
- the cueing node publishes PX4 attitude offboard setpoints
- PX4 enters `OFFBOARD`
- the published cue error drops into the forward cone


## Phase 6 Live Rival Cueing

The fifth phase-6 slice replaces the scripted rival with live `plane_02` data from the maintained dual-aircraft runtime. `plane_01` stays the ownship, `plane_02` becomes the live rival, and the cueing path reuses the maintained phase-5 competition topics plus the phase-6 guidance nodes.

To run the headless live-rival cueing check:

```bash
./scripts/check-phase6-live-rival-cueing.sh
```

This check also uses incremental workspace builds by default; add `--cold` only when you need a clean rebuild.

To run the GUI live-rival cueing check:

```bash
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-cueing.sh
```

This check also uses incremental workspace builds by default; add `--cold` only when you need a clean rebuild.

The maintained check now proves:
- `plane_01` and `plane_02` start in the shared phase-4 runtime
- both aircraft take off and stabilize
- live `plane_02` state is published on `/competition/rival/state`
- `plane_01` enters `OFFBOARD` against the real rival instead of a scripted target
- the published cue error drops into the forward cone in both headless and GUI runs

## Phase 6 Live-Rival Geometry Hardening

The maintained live-rival hardening path now uses a long straight `plane_02` run and requires a sustained stern-chase hold: forward-cone cueing, range closure, final proximity, heading alignment, and tail-angle containment for roughly `10s` before both aircraft land.

The maintained live-rival cueing slice now also has a stronger standalone hardening check against the real dual-aircraft simulation. It keeps `plane_01` as ownship, uses live `plane_02` state as the rival source, records ownship-versus-rival geometry to CSV, and only passes if a sustained airborne catch occurs with meaningful range closure and final proximity before both aircraft land successfully.

To run the headless live-rival geometry hardening check:

```bash
./scripts/check-phase6-live-rival-geometry.sh --incremental
```

To run the GUI live-rival geometry hardening check:

```bash
xhost +local:docker
ICONOM_USE_GUI=1 ICONOM_USE_NVIDIA=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental
```

This standalone check is not part of `phase6-acceptance.sh` yet. It exists to harden the meaning of live-rival cueing with recorded route-comparison evidence before phase 7 visual-lock work.

To run the GUI phase-6 test and open the ownship camera in `rqt_image_view`, use two terminals.

Terminal 1:

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 ICONOM_USE_NVIDIA=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental
```

Terminal 2:

```bash
cd /home/joseph/Projects/iconom
./scripts/view-phase6-ownship-camera.sh
```

The helper now starts `ros_gz_bridge` automatically if it is not already running and waits for the requested camera topic to appear before opening `rqt_image_view`. The helper defaults to `/plane_01/camera/image_raw`. Override the topic with `CAMERA_TOPIC=/plane_02/camera/image_raw` if you want the rival feed instead.

To export the recorded GUI run as CZML after the test finishes:

```bash
cd /home/joseph/Projects/iconom
python3 ./scripts/export-phase6-czml.py ./ros2_ws/.tmp-phase6-live-rival-geometry.csv
```

To run the CZML viewer server for that replay:

```bash
cd /home/joseph/Projects/iconom
./scripts/serve-phase6-czml-viewer.sh
```

To view the same feed in a browser over rosbridge while the sim is running:

```bash
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.override.yml up -d rosbridge
./scripts/serve-phase6-camera-web.sh
```

Then open `http://127.0.0.1:${PHASE6_CAMERA_WEB_PORT:-8766}/docs/phase6-camera-viewer.html` and connect to `ws://127.0.0.1:${ROSBRIDGE_PORT:-9090}` with `/plane_01/camera/image_raw` or `/plane_02/camera/image_raw`.

The helper now starts a compose-managed `camera_web` service instead of relying on a host-side Python HTTP server, so the whole browser-viewer path can stay inside Docker.

## Phase 6 Scripted Cue Geometry Hardening

The live-rival cueing slice is the maintained phase-6 baseline, but there is also a standalone hardening check for route-comparison evidence against a deterministic moving scripted rival. It keeps `plane_01` as the real simulated ownship, records ownship-versus-rival geometry to CSV, and only passes if a sustained forward-cone catch occurs while `plane_01` is still airborne, shows meaningful range closure and final proximity to the rival, and then lands cleanly afterward.

To run the headless scripted cue-geometry hardening check:

```bash
./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

To run the GUI scripted cue-geometry hardening check:

```bash
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-scripted-cue-geometry.sh --incremental
```

This standalone check is not part of `phase6-acceptance.sh` yet. It exists to harden the meaning of camera cueing with route-comparison evidence before phase 7 visual-lock work.

To render the latest scripted cue CSV as a standalone SVG:

```bash
python3 ./scripts/plot-phase6-scripted-cue-geometry.py ./ros2_ws/.tmp-phase6-scripted-cue-geometry.csv
```

You can also choose the output path explicitly:

```bash
python3 ./scripts/plot-phase6-scripted-cue-geometry.py ./ros2_ws/.tmp-phase6-scripted-cue-geometry.csv --output /tmp/phase6-scripted-cue.svg
```

To export either the scripted or live geometry CSV as a time-aware Cesium replay:

```bash
python3 ./scripts/export-phase6-czml.py ./ros2_ws/.tmp-phase6-live-rival-geometry.csv
```

The exporter writes `<csv>.czml` by default and uses a fixed visualization anchor for replay only. The tracked flight geometry remains in local simulation meters; the anchor simply places the replay on a deterministic WGS84 location so Cesium can play it over time.

To open a local Cesium viewer with drag-drop and same-origin path loading:

```bash
./scripts/serve-phase6-czml-viewer.sh
```

Then open `http://127.0.0.1:8765/docs/phase6-czml-viewer.html` and either drag a `.czml` file into the page or load `/ros2_ws/.tmp-phase6-live-rival-geometry.csv.czml` directly inside the viewer.

To run the planned five-case PD tuning batch on the unchanged live-rival route and preserve every CSV/CZML artifact for later visual review:

```bash
./scripts/run-phase6-pd-sweep.sh --incremental
```

The runner writes a timestamped artifact directory under `ros2_ws/phase6-pd-sweep-*`, with one subdirectory per run plus `summary.md` and `summary.csv`.

## Phase 6 Acceptance

The maintained phase-6 acceptance wrapper runs the current pursuit-guidance baseline in sequence:
- deterministic target selection
- bounded intercept planning
- pursuit state transitions
- live-rival cueing against real `plane_02` data

To run the maintained phase-6 acceptance flow:

```bash
./scripts/phase6-acceptance.sh --headless
```

Phase-6 builds are incremental by default. Use `--cold` only when you want a clean rebuild of the ROS workspace.

To run the maintained phase-6 acceptance flow with GUI for the final live-rival cueing step:

```bash
xhost +local:docker
./scripts/phase6-acceptance.sh --gui
```

To force a clean rebuild before the maintained flow, run `./scripts/phase6-acceptance.sh --headless --cold` or `./scripts/phase6-acceptance.sh --gui --cold`.
