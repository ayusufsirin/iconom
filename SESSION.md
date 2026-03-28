# SESSION

## Goal
Provide maintained operator camera-viewer paths for phase-6 GUI runs.

## Current status
The repo now has both a docker-side `rqt_image_view` helper and a rosbridge-based browser viewer for the phase-6 camera feed. The browser page was visually confirmed to connect to `rosbridge`, and the `rqt` helper now auto-starts `ros_gz_bridge` and waits for the camera topic before opening the window.

## Files touched
- /home/joseph/Projects/iconom/docker/ros2_app/Dockerfile
- /home/joseph/Projects/iconom/docker-compose.yml
- /home/joseph/Projects/iconom/.env.example
- /home/joseph/Projects/iconom/docs/phase6-camera-viewer.html
- /home/joseph/Projects/iconom/scripts/serve-phase6-camera-web.sh
- /home/joseph/Projects/iconom/scripts/view-phase6-ownship-camera.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Verified the browser viewer connection and the live ownship camera feed, and fixed the `rqt` path so it brings up `ros_gz_bridge` automatically when needed.

## Current blocker
None

## Next exact step
None

## Validation
```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/view-phase6-ownship-camera.sh
```

```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/serve-phase6-camera-web.sh
```

```bash
cd /home/joseph/Projects/iconom
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.override.yml config
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental
./scripts/view-phase6-ownship-camera.sh
```

## Notes
- `view-phase6-ownship-camera.sh` now handles the `ros_gz_bridge` dependency itself.
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*.csv` / `.svg` / `.czml` artifacts out of git.
