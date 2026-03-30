# Phase 6 Controller Scheme

This page documents the current phase-6 cueing controller exactly as it is implemented now. It is meant to support controller review and design discussion before more tuning or redesign.

## Purpose

The phase-6 controller is the outer-loop guidance block for `plane_01`. It uses live ownship state and the selected rival state to build a trailing reference, then publishes PX4 attitude setpoints plus forward thrust.

Current responsibilities:

- compute a virtual trailing slot behind the selected rival
- steer laterally and vertically toward that slot
- regulate forward thrust from slot-spacing error

It does not implement visual detection, lock scoring, or a full formation controller.

## Top-Level Data Flow

```mermaid
flowchart LR
    A[plane_01 ownship state\n/competition/ownship/state]
    B[plane_02 rival state\n/competition/rival/state]
    C[target_selector]
    D[predictor]
    E[intercept_planner]
    F[pursuit_state_machine]
    G[camera_cueing_bridge]
    H[PX4 inner loop]
    I[plane_01 motion]

    B --> C
    A --> C
    B --> D
    C -->|selected_target| E
    D -->|predicted_rival| E
    A --> E
    C -->|selected_target| G
    F -->|pursuit_state| G
    A --> G
    E -. monitored only .-> G
    G -->|VehicleAttitudeSetpoint\n+ forward thrust| H
    H --> I
    I --> A
```

Important current fact:

- `camera_cueing_bridge` consumes `selected_target`
- it does not directly steer to `intercept_target`

## Target Reference Scheme

The controller does not fly directly at the rival body. It derives a virtual trailing slot from the selected target pose.

Inputs used for the slot:

- selected target position
- selected target heading
- active chase range

The active chase range has two regimes:

- `capture_chase_range_m` before valid tail chase
- `target_chase_range_m` after valid tail chase

```mermaid
flowchart TD
    A[selected_target pose]
    B[target heading]
    C[tail-chase gate\nrear angle + heading alignment]
    D[capture range]
    E[target chase range]
    F[active chase range]
    G[virtual trailing slot]

    A --> B
    A --> C
    B --> G
    C -->|false| D
    C -->|true| E
    D --> F
    E --> F
    F --> G
```

## Internal Controller Branches

The current controller is a slot-following outer loop with three branches.

```mermaid
flowchart LR
    A[ownship state]
    B[selected target]
    C[virtual trailing slot]

    A --> C
    B --> C

    C --> D[lateral branch]
    C --> E[vertical branch]
    C --> F[longitudinal branch]

    D --> D1[slot heading error]
    D1 --> D2[P roll command\nclamped by max_roll]

    E --> E1[slot altitude error]
    E1 --> E2[base pitch + P altitude bias]

    F --> F1[slot range]
    F1 --> F2[P + I + D spacing law]
    F2 --> F3[body-x thrust command]

    D2 --> G[attitude setpoint]
    E2 --> G
    F3 --> H[forward thrust]
    G --> I[PX4 VehicleAttitudeSetpoint]
    H --> I
```

### Lateral branch

The lateral branch computes heading error from ownship to the trailing slot and converts it to a bounded roll demand. This is the branch that has generally been working best in recent runs.

### Vertical branch

The vertical branch compares ownship altitude to slot altitude and adds a simple pitch bias. It is a bounded altitude bias, not a full energy controller.

### Longitudinal branch

The longitudinal branch is the part under active tuning. It currently uses:

- `P`: slot-range error
- `I`: integrated slot-range error with clamp
- `D`: filtered slot-error rate
- output: forward body thrust command between `min_thrust_x` and `thrust_x`

This is the branch most likely responsible for the current settle-too-far-back versus overshoot tradeoff.

## Tail-Chase Gating

The controller does not switch into the final short spacing immediately. It first checks whether ownship is already in acceptable rear-aspect geometry.

Current gates:

- tail angle within `capture_tail_angle_max_deg`
- heading alignment within `capture_heading_alignment_max_deg`

```mermaid
flowchart TD
    A[ownship + selected target]
    B[tail angle]
    C[heading alignment]
    D{tail chase ready?}
    E[use capture_chase_range_m]
    F[use target_chase_range_m]

    A --> B
    A --> C
    B --> D
    C --> D
    D -->|no| E
    D -->|yes| F
```

## What The Controller Does Not Use Directly

This is important for replay interpretation. The controller does not directly use:

- `intercept_target`
- `predicted_rival`
- raw rival history

Those are part of the broader phase-6 guidance stack, but the current controller directly tracks only:

- ownship state
- selected target
- pursuit state

So if the intercept target appears to lead the real rival in CZML, that is currently a planner observability fact, not the direct steering reference for the controller.

## Main Dynamic Weaknesses Observed So Far

- spacing settles too far back or overshoots
- capture-to-follow transition is sensitive to gains
- fixed-wing speed response is slower than the spacing law would ideally like
- the controller shapes thrust directly instead of commanding a higher-level speed target

The practical effect is that cue and bearing can become very good while stable rear-aspect range holding still fails.

## Main Runtime Parameters

| Parameter                           | Role                                          |
| ----------------------------------- | --------------------------------------------- |
| `thrust_x`                          | maximum forward thrust command                |
| `min_thrust_x`                      | minimum forward thrust floor                  |
| `range_thrust_gain`                 | proportional spacing gain                     |
| `range_integral_gain`               | integral spacing gain                         |
| `range_integral_limit`              | anti-windup clamp                             |
| `range_damping_gain`                | derivative-like damping gain                  |
| `closing_speed_filter_alpha`        | smoothing on slot-error rate                  |
| `target_chase_range_m`              | desired follow spacing after valid tail chase |
| `chase_range_tolerance_m`           | near-band tolerance                           |
| `capture_chase_range_m`             | larger spacing before valid tail chase        |
| `capture_tail_angle_max_deg`        | rear-cone gate                                |
| `capture_heading_alignment_max_deg` | same-heading gate                             |

## One-Sentence Summary

The current phase-6 controller is a selected-target-based virtual trailing-slot controller with P lateral steering, simple P vertical bias, and PI/PID-like longitudinal slot-range control, publishing PX4 attitude setpoints plus forward thrust.
