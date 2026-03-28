# SESSION

## Goal
Add a docker-side camera-view helper so the ownship camera feed can be inspected while the phase-6 GUI sim is running.

## Current status
The repo already exposes `/plane_01/camera/image_raw` and `/plane_02/camera/image_raw`, but `ros2_app` did not have GUI image-view tooling or X11 wiring. This slice adds `rqt_image_view` to the `ros2_app` image, routes X11 into that service in the local override stack, and adds a helper script to open the ownship feed from inside the running container.

## Files touched
- /home/joseph/Projects/iconom/docker/ros2_app/Dockerfile
- /home/joseph/Projects/iconom/docker-compose.override.yml
- /home/joseph/Projects/iconom/scripts/view-phase6-ownship-camera.sh
- /home/joseph/Projects/iconom/README.md
- /home/joseph/Projects/iconom/SESSION.md

## Last completed step
Patched the repo for docker-side camera viewing: package install, X11 wiring, and a maintained helper script.

## Current blocker
Runtime validation is still pending against a rebuilt `ros2_app` image.

## Next exact step
Rebuild `ros2_app`, then run `/home/joseph/Projects/iconom/scripts/view-phase6-ownship-camera.sh` while the GUI sim is active and confirm that `rqt_image_view` opens `/plane_01/camera/image_raw`.

## Validation
```bash
cd /home/joseph/Projects/iconom
bash -n ./scripts/view-phase6-ownship-camera.sh
```

```bash
cd /home/joseph/Projects/iconom
docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.override.yml build ros2_app
```

```bash
cd /home/joseph/Projects/iconom
xhost +local:docker
ICONOM_USE_GUI=1 PX4_HEADLESS=0 ./scripts/check-phase6-live-rival-geometry.sh --incremental
./scripts/view-phase6-ownship-camera.sh
```

## Notes
- Keep `QGroundControl-x86_64.AppImage`, `opencode.json`, `opencode.json.home_network`, and the `.tmp-phase6-*.csv` / `.svg` / `.czml` artifacts out of git.
- Override the viewed topic with `CAMERA_TOPIC=/plane_02/camera/image_raw` for the rival camera.
