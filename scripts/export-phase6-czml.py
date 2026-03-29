#!/usr/bin/env python3
"""Export phase-6 geometry CSV artifacts as Cesium CZML replays."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from datetime import datetime, timedelta, timezone


DEFAULT_ANCHOR_LAT_DEG = 41.015137
DEFAULT_ANCHOR_LON_DEG = 28.979530
DEFAULT_ANCHOR_ALT_M = 120.0
DEFAULT_EPOCH = "2026-01-01T00:00:00Z"
OWN_COLOR = [21, 101, 192, 255]
RIVAL_COLOR = [198, 40, 40, 255]
SELECTED_COLOR = [255, 179, 0, 255]
INTERCEPT_COLOR = [46, 204, 113, 255]


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
    return parser.parse_args()


def parse_float(value: str | None) -> float:
    if value is None or value == "":
        return float("nan")
    return float(value)


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
            row = {
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
            }
            rows.append(row)
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
    view_lon_deg, view_lat_deg, view_alt_m = local_offsets_to_wgs84(
        0.0,
        0.0,
        -250.0,
        anchor_lat_deg,
        anchor_lon_deg,
        anchor_alt_m,
    )
    packets: list[dict[str, object]] = []
    packets.append(
        {
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
        }
    )
    packets.append(
        {
            "id": "phase6-view",
            "name": "Replay View",
            "availability": availability,
            "position": {"cartographicDegrees": [view_lon_deg, view_lat_deg, view_alt_m]},
            "viewFrom": {"cartesian": [0.0, -450.0, 220.0]},
        }
    )
    for packet in (
        make_entity_packet("ownship", "plane_01 ownship", OWN_COLOR, rows, "own_x", "own_y", "own_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("rival", "plane_02 rival", RIVAL_COLOR, rows, "rival_x", "rival_y", "rival_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("selected_target", "selected target", SELECTED_COLOR, rows, "selected_x", "selected_y", "selected_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
        make_entity_packet("intercept_target", "intercept target", INTERCEPT_COLOR, rows, "intercept_x", "intercept_y", "intercept_z", anchor_lat_deg, anchor_lon_deg, anchor_alt_m, epoch, availability),
    ):
        if packet is not None:
            packets.append(packet)
    return packets


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv_path).resolve()
    if not csv_path.is_file():
        raise SystemExit(f"missing CSV: {csv_path}")
    output_path = (
        Path(args.output).resolve()
        if args.output
        else csv_path.with_suffix(csv_path.suffix + ".czml")
    )
    rows = load_rows(csv_path)
    czml = build_czml(
        rows,
        args.anchor_lat_deg,
        args.anchor_lon_deg,
        args.anchor_alt_m,
        args.epoch,
    )
    output_path.write_text(json.dumps(czml, indent=2), encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
