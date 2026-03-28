#!/usr/bin/env python3
"""Evaluate phase-6 geometry CSV artifacts against sustained cue criteria."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path")
    parser.add_argument("--initial-bearing-min-deg", type=float, required=True)
    parser.add_argument("--bearing-improvement-min-deg", type=float, required=True)
    parser.add_argument("--rival-route-min-distance-m", type=float, required=True)
    parser.add_argument("--final-bearing-max-deg", type=float, required=True)
    parser.add_argument("--final-cue-max-deg", type=float, required=True)
    parser.add_argument("--catch-min-altitude-m", type=float, required=True)
    parser.add_argument("--hold-sec", type=float, required=True)
    parser.add_argument("--initial-range-min-m", type=float, default=None)
    parser.add_argument("--range-reduction-min-m", type=float, default=None)
    parser.add_argument("--final-range-max-m", type=float, default=None)
    return parser.parse_args()


def load_rows(csv_path: Path) -> list[dict[str, float]]:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = [
            {
                "t_sec": float(raw["t_sec"]),
                "own_x": float(raw["own_x"]),
                "own_y": float(raw["own_y"]),
                "own_z": float(raw["own_z"]),
                "rival_x": float(raw["rival_x"]),
                "rival_y": float(raw["rival_y"]),
                "rival_z": float(raw["rival_z"]),
                "bearing_error_deg": float(raw["bearing_error_deg"]),
                "camera_cue_error_deg": float(raw["camera_cue_error_deg"]),
            }
            for raw in reader
        ]
    if not rows:
        raise SystemExit("geometry CSV is empty")
    return rows


def estimate_sample_period(rows: list[dict[str, float]]) -> float:
    if len(rows) < 2:
        return 0.2
    deltas = [
        max(0.0001, rows[i]["t_sec"] - rows[i - 1]["t_sec"])
        for i in range(1, min(len(rows), 6))
    ]
    return sum(deltas) / len(deltas)


def find_catch_index(
    rows: list[dict[str, float]],
    final_bearing_max_deg: float,
    final_cue_max_deg: float,
    hold_sec: float,
    initial_range: float,
    range_reduction_min_m: float | None,
    final_range_max_m: float | None,
) -> int | None:
    required_samples = max(1, math.ceil(hold_sec / estimate_sample_period(rows)))
    run_len = 0
    for idx, row in enumerate(rows):
        if (
            row["bearing_error_deg"] <= final_bearing_max_deg
            and row["camera_cue_error_deg"] <= final_cue_max_deg
        ):
            run_len += 1
            if run_len >= required_samples:
                catch_range = range_3d_m(row)
                range_reduction = initial_range - catch_range
                if final_range_max_m is not None and catch_range > final_range_max_m:
                    continue
                if range_reduction_min_m is not None and range_reduction < range_reduction_min_m:
                    continue
                return idx
        else:
            run_len = 0
    return None


def range_3d_m(row: dict[str, float]) -> float:
    return math.sqrt(
        (row["rival_x"] - row["own_x"]) ** 2
        + (row["rival_y"] - row["own_y"]) ** 2
        + (row["rival_z"] - row["own_z"]) ** 2
    )


def main() -> int:
    args = parse_args()
    rows = load_rows(Path(args.csv_path))

    initial = rows[0]
    if initial["bearing_error_deg"] < args.initial_bearing_min_deg:
        raise SystemExit(
            f"initial bearing error {initial['bearing_error_deg']:.3f} deg was below required {args.initial_bearing_min_deg:.3f} deg"
        )

    initial_range = range_3d_m(initial)
    if args.initial_range_min_m is not None and initial_range < args.initial_range_min_m:
        raise SystemExit(
            f"initial range {initial_range:.3f} m was below required {args.initial_range_min_m:.3f} m"
        )

    catch_idx = find_catch_index(
        rows,
        args.final_bearing_max_deg,
        args.final_cue_max_deg,
        args.hold_sec,
        initial_range,
        args.range_reduction_min_m,
        args.final_range_max_m,
    )
    if catch_idx is None:
        raise SystemExit("no sustained catch window satisfied the angular and range gates")

    catch = rows[catch_idx]
    catch_altitude_agl = -catch["own_z"]
    if catch_altitude_agl < args.catch_min_altitude_m:
        raise SystemExit(
            f"catch altitude {catch_altitude_agl:.3f} m was below required {args.catch_min_altitude_m:.3f} m"
        )

    bearing_improvement = initial["bearing_error_deg"] - catch["bearing_error_deg"]
    if bearing_improvement < args.bearing_improvement_min_deg:
        raise SystemExit(
            f"bearing improvement {bearing_improvement:.3f} deg was below required {args.bearing_improvement_min_deg:.3f} deg"
        )

    first = rows[0]
    last = rows[-1]
    rival_route_distance = math.sqrt(
        (last["rival_x"] - first["rival_x"]) ** 2
        + (last["rival_y"] - first["rival_y"]) ** 2
        + (last["rival_z"] - first["rival_z"]) ** 2
    )
    if rival_route_distance < args.rival_route_min_distance_m:
        raise SystemExit(
            f"rival route distance {rival_route_distance:.3f} m was below required {args.rival_route_min_distance_m:.3f} m"
        )

    initial_range = range_3d_m(initial)
    catch_range = range_3d_m(catch)
    range_reduction = initial_range - catch_range

    if args.initial_range_min_m is not None and initial_range < args.initial_range_min_m:
        raise SystemExit(
            f"initial range {initial_range:.3f} m was below required {args.initial_range_min_m:.3f} m"
        )
    if args.range_reduction_min_m is not None and range_reduction < args.range_reduction_min_m:
        raise SystemExit(
            f"net range reduction {range_reduction:.3f} m was below required {args.range_reduction_min_m:.3f} m"
        )
    if args.final_range_max_m is not None and catch_range > args.final_range_max_m:
        raise SystemExit(
            f"catch range {catch_range:.3f} m was above required {args.final_range_max_m:.3f} m"
        )

    print(f"initial_bearing_error_deg={initial['bearing_error_deg']:.3f}")
    print(f"initial_cue_error_deg={initial['camera_cue_error_deg']:.3f}")
    print(f"initial_range_3d_m={initial_range:.3f}")
    print(f"catch_bearing_error_deg={catch['bearing_error_deg']:.3f}")
    print(f"catch_cue_error_deg={catch['camera_cue_error_deg']:.3f}")
    print(f"catch_range_3d_m={catch_range:.3f}")
    print(f"catch_altitude_agl_m={catch_altitude_agl:.3f}")
    print(f"net_bearing_improvement_deg={bearing_improvement:.3f}")
    print(f"net_range_reduction_m={range_reduction:.3f}")
    print(f"rival_route_distance_m={rival_route_distance:.3f}")
    print(f"catch_t_sec={catch['t_sec']:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
