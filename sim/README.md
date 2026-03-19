# sim

This directory holds minimal simulation assets shared by the canonical Gazebo service.

## Current Scope

- A single empty Gazebo Harmonic world for headless startup checks.
- No PX4 vehicle spawning or camera integration yet.

The next simulation step is wiring the PX4 `gz_rc_cessna` model into this stack without breaking the existing slice checks.
