#!/usr/bin/env python3
# pyright: reportMissingImports=false
"""Validate deterministic symbology primitives on overlay frames."""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass
from typing import Any

import cv2
import numpy as np
import rclpy
from rclpy.executors import SingleThreadedExecutor
from rclpy.exceptions import RCLError
from rclpy.node import Node
from sensor_msgs.msg import Image


@dataclass
class CheckResult:
    ok: bool
    reason: str


def color_mask(frame: Any, bgr: tuple[int, int, int], tol: int = 20) -> Any:
    target = np.array(bgr, dtype=np.int16)
    lo = np.clip(target - tol, 0, 255).astype(np.uint8)
    hi = np.clip(target + tol, 0, 255).astype(np.uint8)
    return cv2.inRange(frame, lo, hi)


def validate_red_box(frame: Any, min_overlap: float) -> CheckResult:
    h, w = frame.shape[:2]
    box_w, box_h = 100, 80
    x0 = (w - box_w) // 2
    y0 = (h - box_h) // 2
    x1 = x0 + box_w
    y1 = y0 + box_h

    red = color_mask(frame, (0, 0, 255), tol=25)
    expected = np.zeros((h, w), dtype=np.uint8)
    cv2.rectangle(expected, (x0, y0), (x1, y1), 255, 2)

    expected_pixels = int(np.count_nonzero(expected))
    overlap = int(np.count_nonzero(cv2.bitwise_and(red, expected)))
    ratio = overlap / expected_pixels if expected_pixels else 0.0

    ok = ratio >= min_overlap
    return CheckResult(
        ok=ok,
        reason=(
            f"red box overlap={overlap}/{expected_pixels} ({ratio:.2f}), "
            f"threshold={min_overlap:.2f}"
        ),
    )


def _line_density(mask: Any, cx: int, cy: int, half_len: int = 30, half_thickness: int = 1) -> tuple[int, int]:
    h, w = mask.shape[:2]
    x0 = max(0, cx - half_len)
    x1 = min(w, cx + half_len + 1)
    y0 = max(0, cy - half_thickness)
    y1 = min(h, cy + half_thickness + 1)
    horizontal = int(np.count_nonzero(mask[y0:y1, x0:x1]))

    x0v = max(0, cx - half_thickness)
    x1v = min(w, cx + half_thickness + 1)
    y0v = max(0, cy - half_len)
    y1v = min(h, cy + half_len + 1)
    vertical = int(np.count_nonzero(mask[y0v:y1v, x0v:x1v]))
    return horizontal, vertical


def _has_circle_cardinals(mask: Any, cx: int, cy: int, radius: int = 20) -> bool:
    points = [(cx - radius, cy), (cx + radius, cy), (cx, cy - radius), (cx, cy + radius)]
    h, w = mask.shape[:2]
    for px, py in points:
        if px < 0 or py < 0 or px >= w or py >= h:
            return False
        x0 = max(0, px - 2)
        x1 = min(w, px + 3)
        y0 = max(0, py - 2)
        y1 = min(h, py + 3)
        if np.count_nonzero(mask[y0:y1, x0:x1]) == 0:
            return False
    return True


def _best_crosshair_center(mask: Any) -> tuple[int, int, float]:
    fmask = (mask > 0).astype(np.float32)
    h_kernel = np.ones((3, 61), dtype=np.float32)
    v_kernel = np.ones((61, 3), dtype=np.float32)
    h_score = cv2.filter2D(fmask, -1, h_kernel)
    v_score = cv2.filter2D(fmask, -1, v_kernel)
    score = h_score * v_score
    _, max_val, _, max_loc = cv2.minMaxLoc(score)
    return max_loc[0], max_loc[1], float(max_val)


def validate_crosshair(frame: Any, expect: str, min_line_pixels: int) -> CheckResult:
    h, w = frame.shape[:2]
    color = (0, 255, 0) if expect == "green" else (128, 128, 128)
    mask = color_mask(frame, color, tol=20)

    if np.count_nonzero(mask) == 0:
        return CheckResult(False, f"{expect} crosshair color pixels not found")

    if expect == "grey":
        cx, cy = w // 2, h // 2
        score_info = f"center=({cx},{cy})"
    else:
        cx, cy, peak = _best_crosshair_center(mask)
        score_info = f"best=({cx},{cy}), peak_score={peak:.1f}"

    horizontal, vertical = _line_density(mask, cx, cy)
    has_circle = _has_circle_cardinals(mask, cx, cy)

    if expect == "grey":
        tol = 3
        bx, by, _ = _best_crosshair_center(mask)
        if abs(bx - (w // 2)) > tol or abs(by - (h // 2)) > tol:
            return CheckResult(
                False,
                f"grey crosshair not centered: detected=({bx},{by}) expected=({w//2},{h//2}) tol={tol}",
            )

    ok = horizontal >= min_line_pixels and vertical >= min_line_pixels and has_circle
    return CheckResult(
        ok=ok,
        reason=(
            f"{expect} crosshair {score_info}, horizontal={horizontal}, "
            f"vertical={vertical}, circle_cardinals={has_circle}, threshold={min_line_pixels}"
        ),
    )


def run(topic: str, expect: str, timeout_s: float, min_red_overlap: float, min_line_pixels: int) -> int:
    class OverlayFrameCollector(Node):
        def __init__(self, topic_name: str) -> None:
            super().__init__("overlay_frame_validator")
            self._frame = None
            self._frame_count = 0
            self.create_subscription(Image, topic_name, self._on_image, 10)

        def _on_image(self, msg: Any) -> None:
            if msg.encoding == "bgr8":
                self._frame = np.frombuffer(msg.data, dtype=np.uint8).reshape((msg.height, msg.width, 3))
            else:
                buffer = np.frombuffer(msg.data, dtype=np.uint8)
                self._frame = cv2.imdecode(buffer, cv2.IMREAD_COLOR)
            self._frame_count += 1

        @property
        def frame(self) -> Any:
            return self._frame

        @property
        def frame_count(self) -> int:
            return self._frame_count

    if not rclpy.ok():
        rclpy.init()
    node = OverlayFrameCollector(topic)
    executor = SingleThreadedExecutor()
    executor.add_node(node)
    deadline = time.monotonic() + timeout_s
    analyzed_count = 0
    last_failure = "no frames received"

    try:
        while time.monotonic() < deadline:
            executor.spin_once(timeout_sec=0.25)
            if node.frame is None or node.frame_count == analyzed_count:
                continue

            analyzed_count = node.frame_count
            frame = node.frame.copy()
            red_result = validate_red_box(frame, min_red_overlap)
            cross_result = validate_crosshair(frame, expect, min_line_pixels)

            print(f"frame #{analyzed_count}: {red_result.reason}")
            print(f"frame #{analyzed_count}: {cross_result.reason}")

            if red_result.ok and cross_result.ok:
                print(f"PASS: overlay validation succeeded for expect={expect}")
                return 0

            last_failure = (
                f"red_ok={red_result.ok} ({red_result.reason}); "
                f"crosshair_ok={cross_result.ok} ({cross_result.reason})"
            )

        print(f"FAIL: timeout after {timeout_s:.1f}s; last failure: {last_failure}", file=sys.stderr)
        return 1
    finally:
        executor.remove_node(node)
        node.destroy_node()
        try:
            rclpy.shutdown()
        except RCLError:
            pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate symbology overlay frame content")
    parser.add_argument("--topic", default="/plane_01/camera/image_overlay")
    parser.add_argument("--expect", choices=("green", "grey"), required=True)
    parser.add_argument("--timeout", type=float, default=12.0)
    parser.add_argument("--min-red-overlap", type=float, default=0.60)
    parser.add_argument("--min-line-pixels", type=int, default=90)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return run(
        topic=args.topic,
        expect=args.expect,
        timeout_s=args.timeout,
        min_red_overlap=args.min_red_overlap,
        min_line_pixels=args.min_line_pixels,
    )


if __name__ == "__main__":
    sys.exit(main())
