#!/usr/bin/env python3
"""Export phase-6 geometry CSV artifacts as Cesium CZML replays."""

from __future__ import annotations

import argparse
import csv
import json
import math
from datetime import datetime, timedelta, timezone
from pathlib import Path


DEFAULT_ANCHOR_LAT_DEG = 41.015137
DEFAULT_ANCHOR_LON_DEG = 28.979530
DEFAULT_ANCHOR_ALT_M = 120.0
DEFAULT_EPOCH = "2026-01-01T00:00:00Z"
DEFAULT_TARGET_CHASE_RANGE_M = 5.0
DEFAULT_CHASE_RANGE_TOLERANCE_M = 3.0
DEFAULT_CAPTURE_CHASE_RANGE_M = 18.0
DEFAULT_CAPTURE_TAIL_ANGLE_MAX_DEG = 45.0
DEFAULT_CAPTURE_HEADING_ALIGNMENT_MAX_DEG = 35.0
OWN_COLOR = [21, 101, 192, 255]
RIVAL_COLOR = [198, 40, 40, 255]
SELECTED_COLOR = [255, 179, 0, 255]
INTERCEPT_COLOR = [46, 204, 113, 255]
SLOT_COLOR = [244, 114, 182, 255]
TRANSITION_COLOR = [255, 255, 255, 255]
PHASE_COLOR_MAP = {
    "capture": [37, 99, 235, 255],
    "settle": [245, 158, 11, 255],
    "follow_lock": [16, 185, 129, 255],
    "follow_hold": [34, 197, 94, 255],
    "recovery": [239, 68, 68, 255],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", help="Path to a phase-6 geometry CSV artifact")
    parser.add_argument("-o", "--output", help="Output CZML path. Defaults to <csv_path>.czml")
    parser.add_argument(
        "--anchor-lat-deg",
        type=float,
        default=DEFAULT_ANCHOR_LAT_DEG,
        help=f"Fixed replay anchor latitude in degrees (default: {DEFAULT_ANCHOR_LAT_DEG})",
    )
    parser.add_argument(
        "--anchor-lon-deg",
        type=float,
        default=DEFAULT_ANCHOR_LON_DEG,
        help=f"Fixed replay anchor longitude in degrees (default: {DEFAULT_ANCHOR_LON_DEG})",
    )
    parser.add_argument(
        "--anchor-alt-m",
        type=float,
        default=DEFAULT_ANCHOR_ALT_M,
        help=f"Fixed replay anchor altitude in meters (default: {DEFAULT_ANCHOR_ALT_M})",
    )
    parser.add_argument("--epoch", default=DEFAULT_EPOCH, help=f"CZML epoch timestamp (default: {DEFAULT_EPOCH})")
    parser.add_argument("--target-chase-range-m", type=float, default=DEFAULT_TARGET_CHASE_RANGE_M)
    parser.add_argument("--chase-range-tolerance-m", type=float, default=DEFAULT_CHASE_RANGE_TOLERANCE_M)
    parser.add_argument("--capture-chase-range-m", type=float, default=DEFAULT_CAPTURE_CHASE_RANGE_M)
    parser.add_argument("--capture-tail-angle-max-deg", type=float, default=DEFAULT_CAPTURE_TAIL_ANGLE_MAX_DEG)
    parser.add_argument("--capture-heading-alignment-max-deg", type=float, default=DEFAULT_CAPTURE_HEADING_ALIGNMENT_MAX_DEG)
    return parser.parse_args()


def parse_float(value: str | None) -> float:
    if value is None or value == "":
        return float("nan")
    return float(value)


def wrap_angle(angle_rad: float) -> float:
    return math.atan2(math.sin(angle_rad), math.cos(angle_rad))


def angle_error_deg(a_deg: float, b_deg: float) -> float:
    return abs(math.degrees(wrap_angle(math.radians(a_deg - b_deg))))


def load_rows(csv_path: Path) -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        required = {
            "t_sec", "own_x", "own_y", "own_z", "own_yaw_deg",
            "rival_x", "rival_y", "rival_z", "rival_yaw_deg",
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise SystemExit("CSV is missing required geometry fields for CZML export")
        for raw in reader:
            rows.append(
                {
                    "t_sec": parse_float(raw.get("t_sec")),
                    "own_x": parse_float(raw.get("own_x")),
                    "own_y": parse_float(raw.get("own_y")),
                    "own_z": parse_float(raw.get("own_z")),
                    "own_yaw_deg": parse_float(raw.get("own_yaw_deg")),
                    "rival_x": parse_float(raw.get("rival_x")),
                    "rival_y": parse_float(raw.get("rival_y")),
                    "rival_z": parse_float(raw.get("rival_z")),
                    "rival_yaw_deg": parse_float(raw.get("rival_yaw_deg")),
                    "selected_x": parse_float(raw.get("selected_x")),
                    "selected_y": parse_float(raw.get("selected_y")),
                    "selected_z": parse_float(raw.get("selected_z")),
                    "selected_yaw_deg": parse_float(raw.get("selected_yaw_deg")),
                    "selected_age_sec": parse_float(raw.get("selected_age_sec")),
                    "intercept_x": parse_float(raw.get("intercept_x")),
                    "intercept_y": parse_float(raw.get("intercept_y")),
                    "intercept_z": parse_float(raw.get("intercept_z")),
                    "intercept_yaw_deg": parse_float(raw.get("intercept_yaw_deg")),
                    "intercept_age_sec": parse_float(raw.get("intercept_age_sec")),
                    "longitudinal_phase": (raw.get("longitudinal_phase") or "").strip().lower(),
                    "spacing_mode": (raw.get("spacing_mode") or "").strip().lower(),
                }
            )
    if not rows:
        raise SystemExit("geometry CSV is empty")
    return rows


def local_offsets_to_wgs84(
    north_m: float,
    east_m: float,
    down_m: float,
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
) -> tuple[float, float, float]:
    meters_per_deg_lat = 111_111.0
    lat_rad = math.radians(anchor_lat_deg)
    meters_per_deg_lon = max(1.0, meters_per_deg_lat * math.cos(lat_rad))
    lat_deg = anchor_lat_deg + (north_m / meters_per_deg_lat)
    lon_deg = anchor_lon_deg + (east_m / meters_per_deg_lon)
    alt_m = anchor_alt_m - down_m
    return lon_deg, lat_deg, alt_m


def row_has_position(row: dict[str, float], x_key: str, y_key: str, z_key: str) -> bool:
    return not any(math.isnan(row[key]) for key in (x_key, y_key, z_key))


def make_position_series(
    rows: list[dict[str, float]],
    x_key: str,
    y_key: str,
    z_key: str,
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
) -> list[float]:
    series: list[float] = []
    for row in rows:
        if not row_has_position(row, x_key, y_key, z_key):
            continue
        lon_deg, lat_deg, alt_m = local_offsets_to_wgs84(
            row[x_key],
            row[y_key],
            row[z_key],
            anchor_lat_deg,
            anchor_lon_deg,
            anchor_alt_m,
        )
        series.extend([row["t_sec"], lon_deg, lat_deg, alt_m])
    return series


def make_label_style(text: str, color: list[int]) -> dict[str, object]:
    return {
        "text": text,
        "font": "16pt sans-serif",
        "style": "FILL_AND_OUTLINE",
        "fillColor": {"rgba": color},
        "outlineColor": {"rgba": [255, 255, 255, 255]},
        "outlineWidth": 2,
        "pixelOffset": {"cartesian2": [0, -18]},
        "horizontalOrigin": "CENTER",
        "verticalOrigin": "BOTTOM",
    }


def make_entity_packet(
    entity_id: str,
    name: str,
    color: list[int],
    rows: list[dict[str, float]],
    x_key: str,
    y_key: str,
    z_key: str,
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
    epoch: str,
    availability: str,
) -> dict[str, object] | None:
    series = make_position_series(rows, x_key, y_key, z_key, anchor_lat_deg, anchor_lon_deg, anchor_alt_m)
    if not series:
        return None
    return {
        "id": entity_id,
        "name": name,
        "availability": availability,
        "label": make_label_style(name, color),
        "point": {
            "pixelSize": 10,
            "color": {"rgba": color},
            "outlineColor": {"rgba": [255, 255, 255, 255]},
            "outlineWidth": 2,
        },
        "path": {
            "material": {"solidColor": {"color": {"rgba": color}}},
            "width": 3,
            "leadTime": 0,
            "trailTime": rows[-1]["t_sec"],
            "resolution": 1,
        },
        "position": {
            "interpolationAlgorithm": "LAGRANGE",
            "interpolationDegree": 1,
            "epoch": epoch,
            "cartographicDegrees": series,
        },
    }


def normalize_phase(value: object) -> str:
    if not isinstance(value, str):
        return ""
    phase = value.strip().lower()
    return phase if phase in PHASE_COLOR_MAP else ""


def make_phase_segments(rows: list[dict[str, float]]) -> list[tuple[str, list[dict[str, float]]]]:
    segments: list[tuple[str, list[dict[str, float]]]] = []
    current_phase = ""
    current_rows: list[dict[str, float]] = []
    for row in rows:
        phase = normalize_phase(row.get("longitudinal_phase", ""))
        if not phase:
            if current_rows:
                segments.append((current_phase, current_rows))
                current_rows = []
                current_phase = ""
            continue
        if phase != current_phase:
            if current_rows:
                segments.append((current_phase, current_rows))
            current_phase = phase
            current_rows = [row]
        else:
            current_rows.append(row)
    if current_rows:
        segments.append((current_phase, current_rows))
    return segments


def make_phase_packets(
    rows: list[dict[str, float]],
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
    epoch: str,
    availability: str,
) -> list[dict[str, object]]:
    packets: list[dict[str, object]] = []
    phase_counts: dict[str, int] = {}
    for phase, segment_rows in make_phase_segments(rows):
        color = PHASE_COLOR_MAP.get(phase)
        if color is None or len(segment_rows) < 2:
            continue
        phase_counts[phase] = phase_counts.get(phase, 0) + 1
        packet = make_entity_packet(
            f"ownship-phase-{phase}-{phase_counts[phase]}",
            f"plane_01 {phase}",
            color,
            segment_rows,
            "own_x",
            "own_y",
            "own_z",
            anchor_lat_deg,
            anchor_lon_deg,
            anchor_alt_m,
            epoch,
            availability,
        )
        if packet is None:
            continue
        packet["label"] = {"show": False}
        packet["point"] = {"show": False}
        packet["path"]["width"] = 6
        packets.append(packet)
    return packets


def make_transition_packets(
    rows: list[dict[str, float]],
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
    availability: str,
) -> list[dict[str, object]]:
    packets: list[dict[str, object]] = []
    previous_phase = ""
    transition_index = 0
    for row in rows:
        phase = normalize_phase(row.get("longitudinal_phase", ""))
        if not phase:
            continue
        if previous_phase and phase != previous_phase and row_has_position(row, "own_x", "own_y", "own_z"):
            transition_index += 1
            lon_deg, lat_deg, alt_m = local_offsets_to_wgs84(
                row["own_x"],
                row["own_y"],
                row["own_z"],
                anchor_lat_deg,
                anchor_lon_deg,
                anchor_alt_m,
            )
            packets.append({
                "id": f"phase-transition-{transition_index}",
                "name": f"{previous_phase}->{phase}",
                "availability": availability,
                "label": make_label_style(f"{previous_phase}->{phase}", TRANSITION_COLOR),
                "point": {
                    "pixelSize": 12,
                    "color": {"rgba": TRANSITION_COLOR},
                    "outlineColor": {"rgba": [16, 19, 26, 255]},
                    "outlineWidth": 2,
                },
                "position": {"cartographicDegrees": [lon_deg, lat_deg, alt_m]},
            })
        previous_phase = phase
    return packets


def augment_with_virtual_slot(rows: list[dict[str, float]], args: argparse.Namespace) -> None:
    for row in rows:
        row["slot_x"] = float("nan")
        row["slot_y"] = float("nan")
        row["slot_z"] = float("nan")
        row["slot_yaw_deg"] = float("nan")
        if not all(
            not math.isnan(row[key])
            for key in ("own_x", "own_y", "own_z", "own_yaw_deg", "selected_x", "selected_y", "selected_z", "selected_yaw_deg")
        ):
            continue
        dx = row["selected_x"] - row["own_x"]
        dy = row["selected_y"] - row["own_y"]
        dz = row["selected_z"] - row["own_z"]
        range_to_target_m = math.sqrt(dx * dx + dy * dy + dz * dz)
        rival_to_own_heading_deg = math.degrees(math.atan2(row["own_y"] - row["selected_y"], row["own_x"] - row["selected_x"]))
        rival_rear_heading_deg = row["selected_yaw_deg"] + 180.0
        tail_angle_deg = angle_error_deg(rival_to_own_heading_deg, rival_rear_heading_deg)
        heading_alignment_deg = angle_error_deg(row["own_yaw_deg"], row["selected_yaw_deg"])
        in_tail_chase = (
            tail_angle_deg <= args.capture_tail_angle_max_deg
            and heading_alignment_deg <= args.capture_heading_alignment_max_deg
        )
        if not in_tail_chase:
            active_range_m = args.capture_chase_range_m
        elif range_to_target_m > (args.target_chase_range_m + 2.0 * args.chase_range_tolerance_m):
            active_range_m = max(
                args.target_chase_range_m + args.chase_range_tolerance_m,
                args.capture_chase_range_m * 0.5,
            )
        else:
            active_range_m = args.target_chase_range_m
        target_heading_rad = math.radians(row["selected_yaw_deg"])
        row["slot_x"] = row["selected_x"] - math.cos(target_heading_rad) * active_range_m
        row["slot_y"] = row["selected_y"] - math.sin(target_heading_rad) * active_range_m
        row["slot_z"] = row["selected_z"]
        row["slot_yaw_deg"] = row["selected_yaw_deg"]


def offset_iso8601(epoch: str, seconds: float) -> str:
    base = datetime.fromisoformat(epoch.replace("Z", "+00:00"))
    return (base + timedelta(seconds=seconds)).astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def build_czml(
    rows: list[dict[str, float]],
    anchor_lat_deg: float,
    anchor_lon_deg: float,
    anchor_alt_m: float,
    epoch: str,
) -> list[dict[str, object]]:
    end_t = rows[-1]["t_sec"]
    availability = f"{epoch}/{offset_iso8601(epoch, end_t)}"
    view_lon_deg, view_lat_deg, view_alt_m = local_offsets_to_wgs84(0.0, 0.0, -250.0, anchor_lat_deg, anchor_lon_deg, anchor_alt_m)
    packets: list[dict[str, object]] = []
    packets.append({
        "id": "document",
        "name": "Phase 6 Replay",
        "version": "1.0",
        "clock": {
            "interval": availability,
            "currentTime": epoch,
            "multiplier": 1,
            "range": "LOOP_STOP",
            "step": "SYSTEM_CLOCK_MULTIPLIER",
        },
    })
    packets.append({
        "id": "phase6-view",
        "name": "Replay View",
        "availability": availability,
        "position": {"cartographicDegrees": [view_lon_deg, view_lat_deg, view_alt_m]},
        "viewFrom": {"cartesian": [0.0, -450.0, 220.0]},
    })
    for packet in (
        make_entity_packet("ownship", "plane_01 ownship", OWN_COLOR, rows, "own_x", "own_y", "own_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("rival", "plane_02 rival", RIVAL_COLOR, rows, "rival_x", "rival_y", "rival_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("selected_target", "selected target", SELECTED_COLOR, rows, "selected_x", "selected_y", "selected_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("intercept_target", "intercept target", INTERCEPT_COLOR, rows, "intercept_x", "intercept_y", "intercept_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("trailing_slot", "virtual trailing slot", SLOT_COLOR, rows, "slot_x", "slot_y", "slot_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
    ):
        if packet is not None:
            packets.append(packet)
    packets.extend(make_phase_packets(rows, anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability))
    packets.extend(make_transition_packets(rows, anchor_lat_deg, anchor_lon_deg, anchor_alt_m, availability))
    return packets


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv_path).resolve()
    if not csv_path.is_file():
        raise SystemExit(f"missing CSV: {csv_path}")
    output_path = Path(args.output).resolve() if args.output else csv_path.with_suffix(csv_path.suffix + ".czml")
    rows = load_rows(csv_path)
    augment_with_virtual_slot(rows, args)
    czml = build_czml(rows, args.anchor_lat_deg, args.anchor_lon_deg, args.anchor_alt_m, args.epoch)
    output_path.write_text(json.dumps(czml, indent=2), encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
