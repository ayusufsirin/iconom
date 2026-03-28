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
    parser.add_argument("--target-range-m", type=float, default=None)
    parser.add_argument("--range-tolerance-m", type=float, default=None)
    parser.add_argument("--tail-angle-max-deg", type=float, default=None)
    parser.add_argument("--heading-alignment-max-deg", type=float, default=None)
    return parser.parse_args()


def wrap_angle(angle_rad: float) -> float:
    return math.atan2(math.sin(angle_rad), math.cos(angle_rad))


def angle_error_deg(a_deg: float, b_deg: float) -> float:
    return abs(math.degrees(wrap_angle(math.radians(a_deg - b_deg))))


def load_rows(csv_path: Path) -> list[dict[str, float]]:
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = []
        for raw in reader:
            own_yaw_deg = float(raw["own_yaw_deg"])
            rival_yaw_deg = float(raw["rival_yaw_deg"])
            rival_to_own_heading_deg = math.degrees(
                math.atan2(
                    float(raw["own_y"]) - float(raw["rival_y"]),
                    float(raw["own_x"]) - float(raw["rival_x"]),
                )
            )
            rival_rear_heading_deg = rival_yaw_deg + 180.0
            rows.append(
                {
                    "t_sec": float(raw["t_sec"]),
                    "own_x": float(raw["own_x"]),
                    "own_y": float(raw["own_y"]),
                    "own_z": float(raw["own_z"]),
                    "own_yaw_deg": own_yaw_deg,
                    "rival_x": float(raw["rival_x"]),
                    "rival_y": float(raw["rival_y"]),
                    "rival_z": float(raw["rival_z"]),
                    "rival_yaw_deg": rival_yaw_deg,
                    "bearing_error_deg": float(raw["bearing_error_deg"]),
                    "camera_cue_error_deg": float(raw["camera_cue_error_deg"]),
                    "heading_alignment_error_deg": angle_error_deg(own_yaw_deg, rival_yaw_deg),
                    "tail_angle_deg": angle_error_deg(rival_to_own_heading_deg, rival_rear_heading_deg),
                }
            )
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


def range_3d_m(row: dict[str, float]) -> float:
    return math.sqrt(
        (row["rival_x"] - row["own_x"]) ** 2
        + (row["rival_y"] - row["own_y"]) ** 2
        + (row["rival_z"] - row["own_z"]) ** 2
    )


def altitude_agl_m(row: dict[str, float]) -> float:
    return -row["own_z"]


def row_satisfies_hold(
    row: dict[str, float],
    final_bearing_max_deg: float,
    final_cue_max_deg: float,
    catch_min_altitude_m: float,
    final_range_max_m: float | None,
    target_range_m: float | None,
    range_tolerance_m: float | None,
    tail_angle_max_deg: float | None,
    heading_alignment_max_deg: float | None,
) -> bool:
    current_range = range_3d_m(row)
    if row["bearing_error_deg"] > final_bearing_max_deg:
        return False
    if row["camera_cue_error_deg"] > final_cue_max_deg:
        return False
    if altitude_agl_m(row) < catch_min_altitude_m:
        return False
    if final_range_max_m is not None and current_range > final_range_max_m:
        return False
    if target_range_m is not None and range_tolerance_m is not None:
        if abs(current_range - target_range_m) > range_tolerance_m:
            return False
    if tail_angle_max_deg is not None and row["tail_angle_deg"] > tail_angle_max_deg:
        return False
    if heading_alignment_max_deg is not None and row["heading_alignment_error_deg"] > heading_alignment_max_deg:
        return False
    return True


def find_hold_window(
    rows: list[dict[str, float]],
    final_bearing_max_deg: float,
    final_cue_max_deg: float,
    catch_min_altitude_m: float,
    hold_sec: float,
    sample_period: float,
    initial_range: float,
    range_reduction_min_m: float | None,
    final_range_max_m: float | None,
    target_range_m: float | None,
    range_tolerance_m: float | None,
    tail_angle_max_deg: float | None,
    heading_alignment_max_deg: float | None,
) -> tuple[int, int] | None:
    required_samples = max(1, math.ceil(hold_sec / sample_period))
    run_start = 0
    run_len = 0
    for idx, row in enumerate(rows):
        if row_satisfies_hold(
            row,
            final_bearing_max_deg,
            final_cue_max_deg,
            catch_min_altitude_m,
            final_range_max_m,
            target_range_m,
            range_tolerance_m,
            tail_angle_max_deg,
            heading_alignment_max_deg,
        ):
            if run_len == 0:
                run_start = idx
            run_len += 1
            if run_len >= required_samples:
                catch_range = range_3d_m(row)
                range_reduction = initial_range - catch_range
                if range_reduction_min_m is not None and range_reduction < range_reduction_min_m:
                    continue
                return run_start, idx
        else:
            run_len = 0
    return None


def main() -> int:
    args = parse_args()
    rows = load_rows(Path(args.csv_path))
    sample_period = estimate_sample_period(rows)

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

    hold_window = find_hold_window(
        rows,
        args.final_bearing_max_deg,
        args.final_cue_max_deg,
        args.catch_min_altitude_m,
        args.hold_sec,
        sample_period,
        initial_range,
        args.range_reduction_min_m,
        args.final_range_max_m,
        args.target_range_m,
        args.range_tolerance_m,
        args.tail_angle_max_deg,
        args.heading_alignment_max_deg,
    )
    if hold_window is None:
        raise SystemExit("no sustained catch window satisfied the angular, range, and chase-geometry gates")

    hold_start_idx, hold_end_idx = hold_window
    hold_start = rows[hold_start_idx]
    catch = rows[hold_end_idx]
    catch_altitude_agl = altitude_agl_m(catch)

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

    catch_range = range_3d_m(catch)
    range_reduction = initial_range - catch_range
    if args.range_reduction_min_m is not None and range_reduction < args.range_reduction_min_m:
        raise SystemExit(
            f"net range reduction {range_reduction:.3f} m was below required {args.range_reduction_min_m:.3f} m"
        )
    if args.final_range_max_m is not None and catch_range > args.final_range_max_m:
        raise SystemExit(
            f"catch range {catch_range:.3f} m was above required {args.final_range_max_m:.3f} m"
        )
    if args.target_range_m is not None and args.range_tolerance_m is not None:
        if abs(catch_range - args.target_range_m) > args.range_tolerance_m:
            raise SystemExit(
                f"catch range {catch_range:.3f} m was outside target band {args.target_range_m:.3f} +/- {args.range_tolerance_m:.3f} m"
            )

    hold_rows = rows[hold_start_idx : hold_end_idx + 1]
    hold_duration = max(sample_period, catch["t_sec"] - hold_start["t_sec"] + sample_period)
    hold_tail_angle_max = max(row["tail_angle_deg"] for row in hold_rows)
    hold_heading_alignment_max = max(row["heading_alignment_error_deg"] for row in hold_rows)
    hold_range_max = max(range_3d_m(row) for row in hold_rows)
    hold_range_min = min(range_3d_m(row) for row in hold_rows)

    print(f"initial_bearing_error_deg={initial['bearing_error_deg']:.3f}")
    print(f"initial_cue_error_deg={initial['camera_cue_error_deg']:.3f}")
    print(f"initial_range_3d_m={initial_range:.3f}")
    print(f"catch_bearing_error_deg={catch['bearing_error_deg']:.3f}")
    print(f"catch_cue_error_deg={catch['camera_cue_error_deg']:.3f}")
    print(f"catch_range_3d_m={catch_range:.3f}")
    print(f"catch_altitude_agl_m={catch_altitude_agl:.3f}")
    print(f"catch_tail_angle_deg={catch['tail_angle_deg']:.3f}")
    print(f"catch_heading_alignment_error_deg={catch['heading_alignment_error_deg']:.3f}")
    print(f"net_bearing_improvement_deg={bearing_improvement:.3f}")
    print(f"net_range_reduction_m={range_reduction:.3f}")
    print(f"rival_route_distance_m={rival_route_distance:.3f}")
    print(f"hold_duration_sec={hold_duration:.3f}")
    print(f"hold_start_t_sec={hold_start['t_sec']:.3f}")
    print(f"hold_end_t_sec={catch['t_sec']:.3f}")
    print(f"hold_tail_angle_max_deg={hold_tail_angle_max:.3f}")
    print(f"hold_heading_alignment_error_max_deg={hold_heading_alignment_max:.3f}")
    print(f"hold_range_min_m={hold_range_min:.3f}")
    print(f"hold_range_max_m={hold_range_max:.3f}")
    print(f"catch_t_sec={catch['t_sec']:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
