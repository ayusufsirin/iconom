#!/usr/bin/env python3
"""Move Gazebo objects via gz CLI for Phase 3 integration test."""
import argparse
import subprocess
import time


def run_cmd(cmd):
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.returncode, result.stdout, result.stderr


def move_object(model_name, x, y, z, roll=0, pitch=0, yaw=0):
    """Move a Gazebo model to specified pose."""
    cmd = f"gz model -m {model_name} -p x={x},y={y},z={z},roll={roll},pitch={pitch},yaw={yaw}"
    code, out, err = run_cmd(cmd)
    if code != 0:
        print(f"ERROR moving {model_name}: {err}")
        return False
    print(f"Moved {model_name} to ({x}, {y}, {z})")
    return True


def main():
    parser = argparse.ArgumentParser(description="Move Gazebo objects")
    parser.add_argument("--model", required=True, help="Model name (e.g., plane_01)")
    parser.add_argument("--waypoints", required=True, help="JSON: [[x,y,z],...]")
    parser.add_argument("--dwell", type=float, default=2.0, help="Seconds per waypoint")
    args = parser.parse_args()

    import json
    waypoints = json.loads(args.waypoints)

    for i, (x, y, z) in enumerate(waypoints):
        print(f"Waypoint {i+1}/{len(waypoints)}: ({x}, {y}, {z})")
        if not move_object(args.model, x, y, z):
            exit(1)
        time.sleep(args.dwell)

    print(f"Completed {len(waypoints)} waypoints")


if __name__ == "__main__":
    main()
