# Phase 5 Plan

This document defines the next bounded phase after the tagged `phase4-dual-aircraft-baseline`.

Phase 5 does not expand into hardware integration, real-world reporting, or computer-vision lock logic. Its job is to prove that the maintained stack can host a server-aware two-aircraft substrate where each aircraft knows about the other through a mock competition referee.

## Purpose

Phase 4 proved that two aircraft can coexist without identity, topic, or command collisions:

- both aircraft run in one maintained runtime,
- each aircraft has unique transport identity and ports,
- each aircraft exposes isolated ROS telemetry and camera topics,
- one aircraft can be commanded without affecting the other,
- the bounded dual-aircraft nav loop completes successfully.

What is still unproven is whether the stack can coordinate two aircraft through shared competitive context and whether one aircraft can predict the other's behavior from observed history.

Phase 5 exists to validate coordinated two-aircraft behavior first. It does not yet try to execute real intercepts, formation maneuvers, or weapon engagements.

## Phase 5 Goal

Add a mock referee server, competition client, ownship telemetry adapter, rival history buffer, and predictor to the maintained simulator stack and prove that `plane_01` can observe, track, and predict `plane_02`'s bounded behavior through the server-mediated channel.

Success means:

1. a mock referee server runs alongside the dual-aircraft runtime,
2. a competition client connects to the referee and exchanges aircraft state,
3. an ownship telemetry adapter exposes the local aircraft state to the competition client,
4. a rival history buffer stores observed rival state history,
5. a predictor computes bounded rival trajectory predictions from history,
6. the proof is scriptable and repeatable in headless mode,
7. the same coordination can be observed in GUI mode.

## Phase 5 Scope

Phase 5 is limited to a server-aware two-aircraft substrate and bounded prediction proof.

Included:

- one mock referee server for competition context
- one competition client that connects to the referee
- one ownship telemetry adapter that publishes local aircraft state to the client
- one rival history buffer that stores observed rival state history
- one predictor that computes bounded trajectory predictions
- acceptance-first validation for server-aware coordination

Excluded:

- hardware integration
- real-world reporting
- computer-vision lock logic
- real intercept execution
- formation flight beyond prediction
- weapon engagement logic
- more than two aircraft coordination
- actual referee competition scoring beyond state exchange

## Locked Phase 5 Contract

The following constraints stay fixed unless deliberately revised:

- vehicle namespaces remain `plane_01` and `plane_02`
- PX4 model remains `gz_rc_cessna` for both aircraft
- Gazebo remains the maintained simulator owner
- one shared `Micro XRCE-DDS Agent` remains the maintained XRCE topology
- MAVLink port allocation remains sequential from the existing base
- ROS topics remain namespaced per aircraft under `/plane_XX/fmu/in/...` and `/plane_XX/fmu/out/...`
- camera topics remain namespaced per aircraft under `/plane_XX/camera/...`
- canonical entrypoints remain script-driven

## Mock Referee Server Contract

The mock referee server provides competition context to both aircraft:

- runs as a standalone ROS 2 node or external process
- listens on a defined port for competition client connections
- broadcasts periodic state updates containing both aircraft positions, velocities, and headings
- does not enforce rules, score points, or declare winners - only shares state
- the server identity and port are explicit in the phase-5 contract

Recommended:

- package name: `iconom_referee`
- server script: `referee_server.py`
- default port: `45678`
- message format: custom ROS messages or simple JSON over TCP

## Competition Client Contract

The competition client connects to the referee server and distributes referee state to the local stack:

- runs as a ROS 2 node or external process
- subscribes to referee state updates
- republishes rival aircraft state to a ROS topic for consumption by other components
- publishes ownship state to the referee for broadcast to the other aircraft

Recommended:

- package name: `iconom_competition`
- client script: `competition_client.py`
- input topic: `/referee/state` (from referee)
- output topics: `/competition/rival/state`, `/competition/ownship/state`

## Ownship Telemetry Adapter Contract

The ownship telemetry adapter bridges local PX4 telemetry to the competition client:

- subscribes to `/plane_01/fmu/out/vehicle_local_position` and `/plane_01/fmu/out/vehicle_global_position`
- repackages the local aircraft state into a competition-format message
- publishes to `/competition/ownship/state` for the competition client

Recommended:

- package name: `iconom_telemetry_adapter`
- adapter script: `ownship_adapter.py`
- input topics: `/plane_01/fmu/out/vehicle_local_position`, `/plane_01/fmu/out/vehicle_global_position`
- output topic: `/competition/ownship/state`

## Rival History Buffer Contract

The rival history buffer stores observed rival aircraft state history:

- subscribes to `/competition/rival/state`
- maintains a rolling buffer of the last N position, velocity, and heading observations
- publishes history to a topic for consumption by other components

Recommended:

- package name: `iconom_rival_buffer`
- buffer script: `rival_buffer.py`
- input topic: `/competition/rival/state`
- output topic: `/rival_buffer/history`
- default buffer size: 60 samples (1 second at 60 Hz)

## Predictor Contract

The predictor computes bounded trajectory predictions from rival history:

- subscribes to rival_buffer's history output topic (`/rival_buffer/history`)
- uses buffered history from rival_buffer to estimate velocity
- computes linear extrapolation prediction of future rival position
- publishes predicted rival position to a topic for consumption

Recommended:

- package name: `iconom_predictor`
- predictor script: `predictor.py`
- input topic: `/rival_buffer/history` (PoseArray from rival_buffer)
- output topic: `/competition/prediction/rival_position`
- prediction horizon: configurable, default 2 seconds

## Topic Naming Approach

All phase-5 topics follow the `/competition/...` root:

- `/competition/rival/state` - parsed rival state from referee (published by competition_client)
- `/competition/ownship/state` - local aircraft state for referee (published by ownship_telemetry_adapter or competition_client in fixture mode)
- `/competition/prediction/rival_position` - predicted rival trajectory (published by predictor)

The `/rival_buffer/...` topics are the official source of buffered history:

- `/rival_buffer/history` - buffered rival history as PoseArray (published by rival_buffer)

Note: `/referee/state` is internal to the referee server's HTTP API and not a ROS topic.

## Implementation Order

### Slice 1: Mock Referee Server

Implement the mock referee server that broadcasts bounded dual-aircraft state.

Success:

- referee server starts alongside dual-aircraft runtime,
- referee broadcasts periodic state containing both aircraft positions and velocities,
- no scoring or rule enforcement.

### Slice 2: Competition Client

Implement the competition client that connects to the referee and distributes state.

Success:

- client connects to referee server,
- client publishes rival state to `/competition/rival/state`,
- client sends ownship state to referee.

### Slice 3: Ownship Telemetry Adapter

Implement the ownship adapter that bridges PX4 telemetry to competition format.

Success:

- adapter subscribes to `/plane_01/fmu/out/vehicle_local_position`,
- adapter publishes competition-format state to `/competition/ownship/state`,
- adapter handles both position and velocity data.

### Slice 4: Rival History Buffer

Implement the rival buffer that stores observed rival state history.

Success:

- buffer subscribes to `/competition/rival/state`,
- buffer maintains rolling history of configurable size,
- buffer exposes history via service call.

### Slice 5: Predictor

Implement the predictor that computes bounded trajectory predictions.

Success:

- predictor queries buffer history,
- predictor computes simple trajectory extrapolation,
- predictor publishes predicted position to `/competition/prediction/rival_position`.

### Slice 6: Headless Acceptance Path

Add the maintained validation path for the server-aware substrate.

Success:

- one headless acceptance script proves server-aware coordination,
- the same coordination can be observed in GUI mode.

### Slice 7: GUI Integration

Tighten the maintained phase-5 GUI path so the coordination is visible.

Success:

- referee, client, adapter, buffer, and predictor all visible in the GUI runtime,
- coordination observable through topic introspection.

## Acceptance Criteria

Phase 5 is complete when all of the following are true:

- mock referee server runs and broadcasts dual-aircraft state,
- competition client connects to referee and distributes state,
- ownship adapter bridges PX4 telemetry to competition format,
- rival buffer stores and serves history,
- predictor computes bounded trajectory prediction,
- one maintained acceptance script proves server-aware coordination,
- the same baseline is observable in the GUI runtime.

## Risks

- the mock referee protocol may need iteration to match real competition semantics,
- predictor accuracy depends heavily on the simplicity of the motion model,
- race conditions may exist between referee broadcasts and local state updates,
- the phase-5 components may need explicit timing guarantees.

These are why phase 5 should stop at bounded prediction and not expand into intercept logic yet.

## Deliverables

Phase-5 completion should leave the repo with:

- one maintained mock referee server
- one maintained competition client
- one maintained ownship telemetry adapter
- one maintained rival history buffer
- one maintained predictor
- one maintained server-aware acceptance script
- updated documentation for the coordination contract

The next likely increment after this closed phase-5 slice is the first bounded intercept or engagement logic, not a larger uncontrolled expansion of coordination complexity.

## Initial Next Step

The first concrete phase-5 task should be:

- define the mock referee message format and wire protocol before any server implementation begins.