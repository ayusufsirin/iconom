#!/usr/bin/env python3
"""Render the scripted cue-geometry CSV into a standalone SVG plot."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


SVG_WIDTH = 1400
SVG_HEIGHT = 920
PLOT_BG = "#f7f7f4"
AXIS_COLOR = "#6b6b66"
GRID_COLOR = "#d7d7d1"
TEXT_COLOR = "#1e1e1a"
OWN_COLOR = "#1565c0"
RIVAL_COLOR = "#c62828"
BEARING_COLOR = "#2e7d32"
CUE_COLOR = "#ef6c00"
CATCH_COLOR = "#6a1b9a"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Plot the phase-6 scripted cue geometry CSV as SVG."
    )
    parser.add_argument("csv_path", help="Path to the recorded cue-geometry CSV")
    parser.add_argument(
        "-o",
        "--output",
        help="Output SVG path. Defaults to <csv_path>.svg",
    )
    return parser.parse_args()


def load_rows(csv_path: Path) -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for raw in reader:
            rows.append(
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
                    "in_forward_cone": float(raw["in_forward_cone"]),
                }
            )
    if not rows:
        raise SystemExit("CSV is empty")
    return rows


def find_catch_index(rows: list[dict[str, float]]) -> int | None:
    for idx, row in enumerate(rows):
        if int(row["in_forward_cone"]) == 1:
            return idx
    return None


def escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def scale_point(
    value: float, low: float, high: float, pixel_low: float, pixel_high: float
) -> float:
    if math.isclose(high, low):
        return (pixel_low + pixel_high) / 2.0
    ratio = (value - low) / (high - low)
    return pixel_low + ratio * (pixel_high - pixel_low)


def make_polyline(points: list[tuple[float, float]]) -> str:
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in points)


def trajectory_panel(rows: list[dict[str, float]], catch_idx: int | None) -> str:
    panel_x = 60
    panel_y = 80
    panel_w = 620
    panel_h = 620
    pad = 40

    xs = [row["own_x"] for row in rows] + [row["rival_x"] for row in rows]
    ys = [row["own_y"] for row in rows] + [row["rival_y"] for row in rows]
    min_x = min(xs)
    max_x = max(xs)
    min_y = min(ys)
    max_y = max(ys)

    span_x = max_x - min_x
    span_y = max_y - min_y
    span = max(span_x, span_y, 1.0)
    center_x = (max_x + min_x) / 2.0
    center_y = (max_y + min_y) / 2.0
    half = span * 0.55
    plot_min_x = center_x - half
    plot_max_x = center_x + half
    plot_min_y = center_y - half
    plot_max_y = center_y + half

    def map_xy(x: float, y: float) -> tuple[float, float]:
        px = scale_point(x, plot_min_x, plot_max_x, panel_x + pad, panel_x + panel_w - pad)
        py = scale_point(y, plot_min_y, plot_max_y, panel_y + panel_h - pad, panel_y + pad)
        return px, py

    own_points = [map_xy(row["own_x"], row["own_y"]) for row in rows]
    rival_points = [map_xy(row["rival_x"], row["rival_y"]) for row in rows]

    grid_lines = []
    for step in range(6):
        x = panel_x + pad + step * ((panel_w - 2 * pad) / 5.0)
        y = panel_y + pad + step * ((panel_h - 2 * pad) / 5.0)
        grid_lines.append(
            f'<line x1="{x:.1f}" y1="{panel_y + pad:.1f}" '
            f'x2="{x:.1f}" y2="{panel_y + panel_h - pad:.1f}" '
            f'stroke="{GRID_COLOR}" stroke-width="1"/>'
        )
        grid_lines.append(
            f'<line x1="{panel_x + pad:.1f}" y1="{y:.1f}" '
            f'x2="{panel_x + panel_w - pad:.1f}" y2="{y:.1f}" '
            f'stroke="{GRID_COLOR}" stroke-width="1"/>'
        )

    start_own = own_points[0]
    start_rival = rival_points[0]
    catch_marker = ""
    if catch_idx is not None:
        own_catch = own_points[catch_idx]
        rival_catch = rival_points[catch_idx]
        catch_marker = (
            f'<circle cx="{own_catch[0]:.1f}" cy="{own_catch[1]:.1f}" r="7" fill="{CATCH_COLOR}"/>'
            f'<circle cx="{rival_catch[0]:.1f}" cy="{rival_catch[1]:.1f}" r="7" fill="{CATCH_COLOR}"/>'
        )

    return f"""
<g>
  <text x="{panel_x}" y="40" fill="{TEXT_COLOR}" font-size="30" font-weight="700">Top-down trajectories</text>
  <rect x="{panel_x}" y="{panel_y}" width="{panel_w}" height="{panel_h}" rx="16" fill="{PLOT_BG}" stroke="{AXIS_COLOR}" stroke-width="2"/>
  {''.join(grid_lines)}
  <polyline points="{make_polyline(own_points)}" fill="none" stroke="{OWN_COLOR}" stroke-width="4"/>
  <polyline points="{make_polyline(rival_points)}" fill="none" stroke="{RIVAL_COLOR}" stroke-width="4" stroke-dasharray="10 8"/>
  <circle cx="{start_own[0]:.1f}" cy="{start_own[1]:.1f}" r="6" fill="{OWN_COLOR}"/>
  <circle cx="{start_rival[0]:.1f}" cy="{start_rival[1]:.1f}" r="6" fill="{RIVAL_COLOR}"/>
  {catch_marker}
  <text x="{panel_x + 18}" y="{panel_y + 32}" fill="{TEXT_COLOR}" font-size="18">ownship start</text>
  <circle cx="{panel_x + 170}" cy="{panel_y + 26}" r="6" fill="{OWN_COLOR}"/>
  <text x="{panel_x + 210}" y="{panel_y + 32}" fill="{TEXT_COLOR}" font-size="18">rival start</text>
  <circle cx="{panel_x + 330}" cy="{panel_y + 26}" r="6" fill="{RIVAL_COLOR}"/>
  <text x="{panel_x + 370}" y="{panel_y + 32}" fill="{TEXT_COLOR}" font-size="18">catch sample</text>
  <circle cx="{panel_x + 505}" cy="{panel_y + 26}" r="6" fill="{CATCH_COLOR}"/>
</g>
"""


def error_panel(rows: list[dict[str, float]], catch_idx: int | None) -> str:
    panel_x = 730
    panel_y = 80
    panel_w = 610
    panel_h = 300
    pad_x = 55
    pad_y = 35

    times = [row["t_sec"] for row in rows]
    max_time = max(times)
    max_err = max(
        max(row["bearing_error_deg"], row["camera_cue_error_deg"]) for row in rows
    )
    max_err = max(180.0, math.ceil(max_err / 10.0) * 10.0)

    def map_xy(t: float, err: float) -> tuple[float, float]:
        px = scale_point(t, 0.0, max_time, panel_x + pad_x, panel_x + panel_w - 20)
        py = scale_point(err, 0.0, max_err, panel_y + panel_h - pad_y, panel_y + 20)
        return px, py

    bearing_points = [map_xy(row["t_sec"], row["bearing_error_deg"]) for row in rows]
    cue_points = [map_xy(row["t_sec"], row["camera_cue_error_deg"]) for row in rows]

    threshold_y = map_xy(0.0, 25.0)[1]
    catch_line = ""
    if catch_idx is not None:
        catch_x = map_xy(rows[catch_idx]["t_sec"], 0.0)[0]
        catch_line = (
            f'<line x1="{catch_x:.1f}" y1="{panel_y + 20:.1f}" '
            f'x2="{catch_x:.1f}" y2="{panel_y + panel_h - pad_y:.1f}" '
            f'stroke="{CATCH_COLOR}" stroke-width="2" stroke-dasharray="8 6"/>'
        )

    return f"""
<g>
  <text x="{panel_x}" y="40" fill="{TEXT_COLOR}" font-size="30" font-weight="700">Cue and bearing error</text>
  <rect x="{panel_x}" y="{panel_y}" width="{panel_w}" height="{panel_h}" rx="16" fill="{PLOT_BG}" stroke="{AXIS_COLOR}" stroke-width="2"/>
  <line x1="{panel_x + pad_x:.1f}" y1="{panel_y + panel_h - pad_y:.1f}" x2="{panel_x + panel_w - 20:.1f}" y2="{panel_y + panel_h - pad_y:.1f}" stroke="{AXIS_COLOR}" stroke-width="2"/>
  <line x1="{panel_x + pad_x:.1f}" y1="{panel_y + 20:.1f}" x2="{panel_x + pad_x:.1f}" y2="{panel_y + panel_h - pad_y:.1f}" stroke="{AXIS_COLOR}" stroke-width="2"/>
  <line x1="{panel_x + pad_x:.1f}" y1="{threshold_y:.1f}" x2="{panel_x + panel_w - 20:.1f}" y2="{threshold_y:.1f}" stroke="{GRID_COLOR}" stroke-width="2" stroke-dasharray="6 6"/>
  {catch_line}
  <polyline points="{make_polyline(bearing_points)}" fill="none" stroke="{BEARING_COLOR}" stroke-width="3.5"/>
  <polyline points="{make_polyline(cue_points)}" fill="none" stroke="{CUE_COLOR}" stroke-width="3.5"/>
  <text x="{panel_x + 30}" y="{panel_y + 32}" fill="{TEXT_COLOR}" font-size="18">25 deg cone threshold</text>
  <text x="{panel_x + 30}" y="{panel_y + 62}" fill="{BEARING_COLOR}" font-size="18">bearing error</text>
  <text x="{panel_x + 190}" y="{panel_y + 62}" fill="{CUE_COLOR}" font-size="18">camera cue error</text>
</g>
"""


def summary_panel(rows: list[dict[str, float]], catch_idx: int | None, csv_path: Path) -> str:
    panel_x = 730
    panel_y = 420
    panel_w = 610
    panel_h = 280

    initial = rows[0]
    final = rows[-1]
    own_start = (initial["own_x"], initial["own_y"])
    own_end = (final["own_x"], final["own_y"])
    rival_start = (initial["rival_x"], initial["rival_y"])
    rival_end = (final["rival_x"], final["rival_y"])

    rival_route = math.dist(rival_start, rival_end)
    own_route = math.dist(own_start, own_end)

    lines = [
        f"csv: {csv_path.name}",
        f"samples: {len(rows)}",
        f"ownship path delta: {own_route:.1f} m",
        f"rival path delta: {rival_route:.1f} m",
        f"initial bearing error: {initial['bearing_error_deg']:.2f} deg",
        f"initial cue error: {initial['camera_cue_error_deg']:.2f} deg",
    ]
    if catch_idx is not None:
        catch = rows[catch_idx]
        lines.extend(
            [
                f"catch t: {catch['t_sec']:.2f} s",
                f"catch bearing error: {catch['bearing_error_deg']:.2f} deg",
                f"catch cue error: {catch['camera_cue_error_deg']:.2f} deg",
                f"catch altitude AGL: {-catch['own_z']:.2f} m",
            ]
        )
    else:
        lines.append("catch: none")

    text_lines = []
    y = panel_y + 55
    for line in lines:
        text_lines.append(
            f'<text x="{panel_x + 24}" y="{y}" fill="{TEXT_COLOR}" font-size="22">{escape(line)}</text>'
        )
        y += 30

    return f"""
<g>
  <text x="{panel_x}" y="{panel_y - 20}" fill="{TEXT_COLOR}" font-size="30" font-weight="700">Run summary</text>
  <rect x="{panel_x}" y="{panel_y}" width="{panel_w}" height="{panel_h}" rx="16" fill="{PLOT_BG}" stroke="{AXIS_COLOR}" stroke-width="2"/>
  {''.join(text_lines)}
</g>
"""


def render_svg(rows: list[dict[str, float]], catch_idx: int | None, csv_path: Path) -> str:
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{SVG_WIDTH}" height="{SVG_HEIGHT}" viewBox="0 0 {SVG_WIDTH} {SVG_HEIGHT}">
<rect width="100%" height="100%" fill="#ffffff"/>
<text x="60" y="28" fill="{TEXT_COLOR}" font-size="36" font-weight="700">Phase 6 scripted cue geometry</text>
{trajectory_panel(rows, catch_idx)}
{error_panel(rows, catch_idx)}
{summary_panel(rows, catch_idx, csv_path)}
</svg>
"""


def main() -> int:
    args = parse_args()
    csv_path = Path(args.csv_path).resolve()
    if not csv_path.is_file():
        raise SystemExit(f"missing CSV: {csv_path}")
    output_path = (
        Path(args.output).resolve()
        if args.output
        else csv_path.with_suffix(csv_path.suffix + ".svg")
    )
    rows = load_rows(csv_path)
    catch_idx = find_catch_index(rows)
    svg = render_svg(rows, catch_idx, csv_path)
    output_path.write_text(svg, encoding="utf-8")
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
