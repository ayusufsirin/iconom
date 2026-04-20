#!/usr/bin/env python3
# pyright: reportAny=false, reportExplicitAny=false, reportUnknownVariableType=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportMissingParameterType=false, reportUnusedFunction=false, reportUnannotatedClassAttribute=false, reportPossiblyUnboundVariable=false, reportMissingTypeArgument=false, reportUnusedImport=false
"""Reusable helpers for Phase 7 harness alignment and metrics."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import tempfile
from bisect import bisect_left
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any


def _get(sample: Any, *names: str, default: Any = None) -> Any:
    for name in names:
        if isinstance(sample, Mapping) and name in sample:
            return sample[name]
        if hasattr(sample, name):
            return getattr(sample, name)
    return default


def _resolve_path(sample: Any, path: str) -> Any:
    current = sample
    for part in path.split("."):
        if current is None:
            return None
        if isinstance(current, Mapping):
            current = current.get(part)
        else:
            current = getattr(current, part, None)
    return current


def _scalar(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        if len(value) >= 1 and isinstance(value[0], (int, float)):
            return float(value[0])
    return None


def _vector2(sample: Any, *paths: str) -> tuple[float, float] | None:
    for path in paths:
        value = _resolve_path(sample, path)
        if value is None:
            continue
        if isinstance(value, Mapping):
            x = _get(value, "x", "u", "cx")
            y = _get(value, "y", "v", "cy")
            if x is not None and y is not None:
                return float(x), float(y)
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes)) and len(value) >= 2:
            return float(value[0]), float(value[1])
        x = _get(value, "x", "u", "cx")
        y = _get(value, "y", "v", "cy")
        if x is not None and y is not None:
            return float(x), float(y)
    x = _get(sample, "x", "u", "cx")
    y = _get(sample, "y", "v", "cy")
    if x is not None and y is not None:
        return float(x), float(y)
    return None


def _vector3(sample: Any, *paths: str) -> tuple[float, float, float] | None:
    for path in paths:
        value = _resolve_path(sample, path)
        if value is None:
            continue
        if isinstance(value, Mapping):
            x = _get(value, "x")
            y = _get(value, "y")
            z = _get(value, "z")
            if x is not None and y is not None and z is not None:
                return float(x), float(y), float(z)
        if isinstance(value, Sequence) and not isinstance(value, (str, bytes)) and len(value) >= 3:
            return float(value[0]), float(value[1]), float(value[2])
        x = _get(value, "x")
        y = _get(value, "y")
        z = _get(value, "z")
        if x is not None and y is not None and z is not None:
            return float(x), float(y), float(z)
    x = _get(sample, "x")
    y = _get(sample, "y")
    z = _get(sample, "z")
    if x is not None and y is not None and z is not None:
        return float(x), float(y), float(z)
    return None


def _bearing_deg(sample: Any) -> float | None:
    for name in ("bearing_deg", "bearing", "yaw_deg", "yaw"):
        value = _get(sample, name)
        if value is not None:
            return float(value)
    return None


def _timestamp_seconds(sample: Any) -> float:
    direct = _get(sample, "timestamp_s", "timestamp_sec", "timestamp", "time_s", "time", "t", "stamp_s")
    if isinstance(direct, (int, float)):
        return float(direct)

    header = _get(sample, "header")
    if header is not None:
        stamp = _get(header, "stamp")
        seconds = _stamp_seconds(stamp)
        if seconds is not None:
            return seconds

    stamp = _get(sample, "stamp")
    seconds = _stamp_seconds(stamp)
    if seconds is not None:
        return seconds

    raise KeyError("sample is missing a timestamp")


def _stamp_seconds(stamp: Any) -> float | None:
    if stamp is None:
        return None
    if isinstance(stamp, (int, float)):
        return float(stamp)
    sec = _get(stamp, "sec", "seconds", "s")
    nsec = _get(stamp, "nanosec", "nsec", default=0)
    if sec is not None:
        return float(sec) + float(nsec) / 1_000_000_000.0
    return None


def _angle_error_deg(expected: float, actual: float) -> float:
    delta = (expected - actual + 180.0) % 360.0 - 180.0
    return abs(delta)


def _distance2(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _distance3(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


class AlignedPairs(list):
    def __init__(self, *args: Any, truth_count: int = 0, estimate_count: int = 0, rejected_count: int = 0):
        super().__init__(*args)
        self.truth_count = truth_count
        self.estimate_count = estimate_count
        self.rejected_count = rejected_count


def align_samples(truth_samples: Sequence[Mapping[str, Any]], estimate_samples: Sequence[Mapping[str, Any]], max_skew_ms: int = 100) -> AlignedPairs:
    truth_list = list(truth_samples)
    estimate_list = list(estimate_samples)
    if not truth_list or not estimate_list:
        return AlignedPairs(truth_count=len(truth_list), estimate_count=len(estimate_list))

    truth_times = [(_timestamp_seconds(sample), idx) for idx, sample in enumerate(truth_list)]
    estimate_times = sorted(((_timestamp_seconds(sample), idx) for idx, sample in enumerate(estimate_list)), key=lambda item: item[0])
    estimate_seconds = [item[0] for item in estimate_times]
    used_estimates: set[int] = set()
    aligned = AlignedPairs(truth_count=len(truth_list), estimate_count=len(estimate_list))
    max_skew_s = float(max_skew_ms) / 1000.0

    for truth_time, truth_idx in sorted(truth_times, key=lambda item: item[0]):
        insert_at = bisect_left(estimate_seconds, truth_time)
        candidate_positions = []
        for pos in (insert_at - 1, insert_at, insert_at + 1):
            if 0 <= pos < len(estimate_times):
                candidate_positions.append(pos)

        best_pos = None
        best_skew = None
        for pos in candidate_positions:
            est_time, est_idx = estimate_times[pos]
            if est_idx in used_estimates:
                continue
            skew = abs(est_time - truth_time)
            if best_skew is None or skew < best_skew:
                best_skew = skew
                best_pos = pos

        if best_pos is None or best_skew is None or best_skew > max_skew_s:
            continue

        est_time, est_idx = estimate_times[best_pos]
        used_estimates.add(est_idx)
        aligned.append(
            {
                "truth": truth_list[truth_idx],
                "estimate": estimate_list[est_idx],
                "truth_index": truth_idx,
                "estimate_index": est_idx,
                "truth_timestamp_s": truth_time,
                "estimate_timestamp_s": est_time,
                "skew_ms": best_skew * 1000.0,
            }
        )

    aligned.rejected_count = len(truth_list) - len(aligned)
    return aligned


def _artifact_row_from_pair(pair: Mapping[str, Any]) -> dict[str, Any]:
    truth = pair["truth"]
    estimate = pair["estimate"]
    row: dict[str, Any] = {
        "truth_index": pair.get("truth_index"),
        "estimate_index": pair.get("estimate_index"),
        "truth_timestamp_s": pair.get("truth_timestamp_s"),
        "estimate_timestamp_s": pair.get("estimate_timestamp_s"),
        "skew_ms": pair.get("skew_ms"),
    }

    truth_center = _vector2(truth, "center_px", "image_center_px", "center", "pixel_center")
    estimate_center = _vector2(estimate, "center_px", "image_center_px", "center", "pixel_center")
    if truth_center is not None:
        row["truth_center_x_px"], row["truth_center_y_px"] = truth_center
    if estimate_center is not None:
        row["estimate_center_x_px"], row["estimate_center_y_px"] = estimate_center

    truth_position = _vector3(truth, "position", "pose.position", "truth_position")
    estimate_position = _vector3(estimate, "position", "pose.position", "estimate_position")
    if truth_position is not None:
        row["truth_position_x_m"], row["truth_position_y_m"], row["truth_position_z_m"] = truth_position
    if estimate_position is not None:
        row["estimate_position_x_m"], row["estimate_position_y_m"], row["estimate_position_z_m"] = estimate_position

    truth_bearing = _bearing_deg(truth)
    estimate_bearing = _bearing_deg(estimate)
    if truth_bearing is not None:
        row["truth_bearing_deg"] = truth_bearing
    if estimate_bearing is not None:
        row["estimate_bearing_deg"] = estimate_bearing

    if truth_center is not None and estimate_center is not None:
        row["image_plane_center_error_px"] = _distance2(truth_center, estimate_center)
    if truth_position is not None and estimate_position is not None:
        row["position_error_m"] = _distance3(truth_position, estimate_position)
    if truth_bearing is not None and estimate_bearing is not None:
        row["bearing_error_deg"] = _angle_error_deg(truth_bearing, estimate_bearing)

    return row


def compute_slice3_metrics(
    aligned_pairs: Sequence[Mapping[str, Any]],
    coverage_thresh: float = 0.4,
    skew_thresh_ms: float = 100,
    bearing_thresh_deg: float = 12,
    pixel_thresh_px: float = 160,
    rmse_thresh_m: float = 8.0,
) -> dict[str, Any]:
    pairs = list(aligned_pairs)
    truth_count = getattr(aligned_pairs, "truth_count", len(pairs)) or len(pairs)
    coverage_pct = (len(pairs) / truth_count * 100.0) if truth_count else 0.0

    skews = [float(pair["skew_ms"]) for pair in pairs if pair.get("skew_ms") is not None]
    bearing_errors = []
    pixel_errors = []
    position_errors = []

    for pair in pairs:
        truth = pair["truth"]
        estimate = pair["estimate"]

        truth_bearing = _bearing_deg(truth)
        estimate_bearing = _bearing_deg(estimate)
        if truth_bearing is not None and estimate_bearing is not None:
            bearing_errors.append(_angle_error_deg(truth_bearing, estimate_bearing))

        truth_center = _vector2(truth, "center_px", "image_center_px", "center", "pixel_center")
        estimate_center = _vector2(estimate, "center_px", "image_center_px", "center", "pixel_center")
        if truth_center is not None and estimate_center is not None:
            pixel_errors.append(_distance2(truth_center, estimate_center))

        truth_position = _vector3(truth, "position", "pose.position", "truth_position")
        estimate_position = _vector3(estimate, "position", "pose.position", "estimate_position")
        if truth_position is not None and estimate_position is not None:
            position_errors.append(_distance3(truth_position, estimate_position))

    rmse_m = math.sqrt(sum(error * error for error in position_errors) / len(position_errors)) if position_errors else float("nan")
    mean_skew_ms = statistics.fmean(skews) if skews else float("nan")
    max_skew_ms = max(skews) if skews else float("nan")
    mean_bearing_error_deg = statistics.fmean(bearing_errors) if bearing_errors else float("nan")
    max_bearing_error_deg = max(bearing_errors) if bearing_errors else float("nan")
    mean_pixel_error_px = statistics.fmean(pixel_errors) if pixel_errors else float("nan")
    max_pixel_error_px = max(pixel_errors) if pixel_errors else float("nan")

    return {
        "truth_count": truth_count,
        "aligned_count": len(pairs),
        "coverage_pct": coverage_pct,
        "coverage_threshold_pct": coverage_thresh * 100.0,
        "meets_coverage": coverage_pct >= (coverage_thresh * 100.0),
        "mean_skew_ms": mean_skew_ms,
        "max_skew_ms": max_skew_ms,
        "skew_threshold_ms": skew_thresh_ms,
        "meets_skew": bool(skews) and max_skew_ms <= skew_thresh_ms,
        "mean_bearing_error_deg": mean_bearing_error_deg,
        "max_bearing_error_deg": max_bearing_error_deg,
        "bearing_threshold_deg": bearing_thresh_deg,
        "meets_bearing": bool(bearing_errors) and mean_bearing_error_deg <= bearing_thresh_deg,
        "mean_image_center_error_px": mean_pixel_error_px,
        "max_image_center_error_px": max_pixel_error_px,
        "pixel_threshold_px": pixel_thresh_px,
        "meets_pixel": bool(pixel_errors) and mean_pixel_error_px <= pixel_thresh_px,
        "position_rmse_m": rmse_m,
        "rmse_threshold_m": rmse_thresh_m,
        "meets_rmse": not math.isnan(rmse_m) and rmse_m <= rmse_thresh_m,
    }


def inject_dropout(sample_indices: Sequence[int], start_idx: int, count: int = 5) -> list[int]:
    indices = list(sample_indices)
    dropout_end = start_idx + count
    return [idx for idx in indices if start_idx <= idx < dropout_end]


def _triplet_samples(triplet: Any) -> tuple[Any, Any, Any]:
    if isinstance(triplet, Mapping):
        return triplet.get("baseline"), triplet.get("raw"), triplet.get("fused")
    if isinstance(triplet, Sequence) and not isinstance(triplet, (str, bytes)) and len(triplet) >= 3:
        return triplet[0], triplet[1], triplet[2]
    raise TypeError("aligned triplets must provide baseline, raw, and fused samples")


def _sample_valid(sample: Any, *, fallback: bool = True) -> bool:
    if sample is None:
        return False
    valid = _get(sample, "valid", "visual_valid", "fused_valid", "present")
    if valid is not None:
        return bool(valid)
    return fallback


def _position_norm(sample: Any) -> float | None:
    position = _vector3(sample, "position", "pose.position", "truth_position", "raw_position", "fused_position")
    if position is None:
        return None
    return math.sqrt(position[0] ** 2 + position[1] ** 2 + position[2] ** 2)


def _dropout_recovery_seconds(triplets: list[Mapping[str, Any]]) -> float | None:
    dropout_indices = [idx for idx, triplet in enumerate(triplets) if bool(triplet.get("dropout", False))]
    if not dropout_indices:
        return None

    runs: list[list[int]] = []
    current: list[int] = [dropout_indices[0]]
    for idx in dropout_indices[1:]:
        if idx == current[-1] + 1:
            current.append(idx)
        else:
            runs.append(current)
            current = [idx]
    runs.append(current)

    longest_run = max(runs, key=len)
    if len(longest_run) < 5:
        return None

    start_idx = longest_run[0]
    prev_valid_idx = start_idx - 1
    fused_prev = None
    while prev_valid_idx >= 0:
        _, _, fused_prev = _triplet_samples(triplets[prev_valid_idx])
        if _sample_valid(fused_prev):
            break
        prev_valid_idx -= 1

    if prev_valid_idx < 0:
        return None
    if fused_prev is None:
        return None

    resume_idx = longest_run[-1] + 1
    while resume_idx < len(triplets):
        _, _, fused_resume = _triplet_samples(triplets[resume_idx])
        if _sample_valid(fused_resume):
            return _timestamp_seconds(fused_resume) - _timestamp_seconds(fused_prev)
        resume_idx += 1

    return None


def compute_slice4_metrics(
    aligned_triplets: Sequence[Mapping[str, Any] | Sequence[Any]],
    jitter_thresh_pct: float = 0.0,
    recovery_thresh_s: float = 2.0,
) -> dict[str, Any]:
    triplets = list(aligned_triplets)
    raw_norms: list[float] = []
    fused_norms: list[float] = []

    for triplet in triplets:
        _, raw, fused = _triplet_samples(triplet)
        if _sample_valid(raw) and _sample_valid(fused):
            raw_norm = _position_norm(raw)
            fused_norm = _position_norm(fused)
            if raw_norm is not None:
                raw_norms.append(raw_norm)
            if fused_norm is not None:
                fused_norms.append(fused_norm)

    raw_stddev = statistics.pstdev(raw_norms) if len(raw_norms) >= 2 else 0.0
    fused_stddev = statistics.pstdev(fused_norms) if len(fused_norms) >= 2 else 0.0
    if raw_stddev == 0.0:
        jitter_reduction_pct = 0.0 if fused_stddev == 0.0 else 100.0
    else:
        jitter_reduction_pct = ((raw_stddev - fused_stddev) / raw_stddev) * 100.0

    recovery_s = _dropout_recovery_seconds([triplet if isinstance(triplet, Mapping) else {"baseline": triplet[0], "raw": triplet[1], "fused": triplet[2]} for triplet in triplets])

    return {
        "aligned_count": len(triplets),
        "raw_stddev": raw_stddev,
        "fused_stddev": fused_stddev,
        "jitter_reduction_pct": jitter_reduction_pct,
        "jitter_threshold_pct": jitter_thresh_pct,
        "meets_jitter": jitter_reduction_pct > jitter_thresh_pct,
        "dropout_recovery_s": recovery_s,
        "recovery_threshold_s": recovery_thresh_s,
        "meets_recovery": recovery_s is not None and recovery_s <= recovery_thresh_s,
    }


def build_slice3_rows(aligned_pairs: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return [_artifact_row_from_pair(pair) for pair in aligned_pairs]


def build_slice4_rows(aligned_triplets: Sequence[Mapping[str, Any] | Sequence[Any]]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for idx, triplet in enumerate(aligned_triplets):
        baseline, raw, fused = _triplet_samples(triplet)
        row: dict[str, Any] = {"sample_index": idx}
        if isinstance(triplet, Mapping):
            row["dropout"] = bool(triplet.get("dropout", False))
            row["timestamp_s"] = triplet.get("timestamp_s", triplet.get("timestamp"))
        else:
            row["dropout"] = False
            row["timestamp_s"] = _timestamp_seconds(raw) if raw is not None else None

        if baseline is not None:
            row["baseline_timestamp_s"] = _timestamp_seconds(baseline)
        if raw is not None:
            row["raw_timestamp_s"] = _timestamp_seconds(raw)
            raw_position = _vector3(raw, "position", "pose.position", "raw_position")
            if raw_position is not None:
                row["raw_position_x_m"], row["raw_position_y_m"], row["raw_position_z_m"] = raw_position
        if fused is not None:
            row["fused_timestamp_s"] = _timestamp_seconds(fused)
            fused_position = _vector3(fused, "position", "pose.position", "fused_position")
            if fused_position is not None:
                row["fused_position_x_m"], row["fused_position_y_m"], row["fused_position_z_m"] = fused_position
            row["fused_valid"] = _sample_valid(fused)
        rows.append(row)
    return rows


def write_artifacts(rows: Sequence[Mapping[str, Any]], summary: Mapping[str, Any], csv_path: str | Path, json_path: str | Path) -> None:
    csv_path = Path(csv_path)
    json_path = Path(json_path)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = sorted({key for row in rows for key in row.keys()})
    if not fieldnames:
        fieldnames = sorted(summary.keys())

    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})

    with json_path.open("w", encoding="utf-8") as handle:
        json.dump({"summary": dict(summary), "samples": [dict(row) for row in rows]}, handle, indent=2, sort_keys=True)
        _ = handle.write("\n")


def _fixture_test() -> None:
    truth_samples = [
        {"timestamp_s": 0.00, "center_px": {"x": 100.0, "y": 50.0}, "bearing_deg": 12.0, "position": {"x": 10.0, "y": 1.0, "z": 2.0}},
        {"timestamp_s": 0.10, "center_px": {"x": 120.0, "y": 55.0}, "bearing_deg": 14.0, "position": {"x": 11.0, "y": 2.0, "z": 2.0}},
        {"timestamp_s": 0.20, "center_px": {"x": 140.0, "y": 60.0}, "bearing_deg": 16.0, "position": {"x": 12.0, "y": 3.0, "z": 2.0}},
    ]
    estimate_samples = [
        {"timestamp_s": 0.08, "center_px": {"x": 104.0, "y": 53.0}, "bearing_deg": 11.0, "position": {"x": 10.5, "y": 1.5, "z": 2.0}},
        {"timestamp_s": 0.34, "center_px": {"x": 150.0, "y": 68.0}, "bearing_deg": 20.0, "position": {"x": 13.0, "y": 5.0, "z": 2.0}},
    ]
    aligned = align_samples(truth_samples, estimate_samples, max_skew_ms=100)
    assert len(aligned) == 1

    slice3 = compute_slice3_metrics(aligned)
    rows = build_slice3_rows(aligned)
    assert slice3["aligned_count"] == 1

    triplets: list[dict[str, Any]] = [
        {"baseline": truth_samples[0], "raw": estimate_samples[0], "fused": {"timestamp_s": 0.08, "position": {"x": 10.2, "y": 1.2, "z": 2.0}, "valid": True}},
        {"baseline": truth_samples[1], "raw": {"timestamp_s": 0.10, "position": {"x": 11.2, "y": 2.2, "z": 2.0}, "valid": False}, "fused": {"timestamp_s": 0.10, "position": {"x": 11.0, "y": 2.1, "z": 2.0}, "valid": False}, "dropout": True},
        {"baseline": truth_samples[2], "raw": {"timestamp_s": 0.20, "position": {"x": 12.2, "y": 3.2, "z": 2.0}, "valid": False}, "fused": {"timestamp_s": 0.20, "position": {"x": 12.0, "y": 3.1, "z": 2.0}, "valid": False}, "dropout": True},
        {"baseline": {"timestamp_s": 0.30, "position": {"x": 13.0, "y": 4.0, "z": 2.0}}, "raw": {"timestamp_s": 0.30, "position": {"x": 13.2, "y": 4.2, "z": 2.0}, "valid": True}, "fused": {"timestamp_s": 0.30, "position": {"x": 13.1, "y": 4.1, "z": 2.0}, "valid": True}},
        {"baseline": {"timestamp_s": 0.40, "position": {"x": 14.0, "y": 5.0, "z": 2.0}}, "raw": {"timestamp_s": 0.40, "position": {"x": 14.2, "y": 5.2, "z": 2.0}, "valid": True}, "fused": {"timestamp_s": 0.40, "position": {"x": 14.05, "y": 5.05, "z": 2.0}, "valid": True}},
        {"baseline": {"timestamp_s": 0.50, "position": {"x": 15.0, "y": 6.0, "z": 2.0}}, "raw": {"timestamp_s": 0.50, "position": {"x": 15.2, "y": 6.2, "z": 2.0}, "valid": True}, "fused": {"timestamp_s": 0.50, "position": {"x": 15.05, "y": 6.05, "z": 2.0}, "valid": True}},
        {"baseline": {"timestamp_s": 0.60, "position": {"x": 16.0, "y": 7.0, "z": 2.0}}, "raw": {"timestamp_s": 0.60, "position": {"x": 16.2, "y": 7.2, "z": 2.0}, "valid": True}, "fused": {"timestamp_s": 0.60, "position": {"x": 16.05, "y": 7.05, "z": 2.0}, "valid": True}},
    ]
    dropout_indices = inject_dropout(list(range(len(triplets))), start_idx=1, count=5)
    assert dropout_indices == [1, 2, 3, 4, 5]
    for idx in dropout_indices:
        triplets[idx]["dropout"] = True
        triplets[idx]["fused"]["valid"] = False
    slice4 = compute_slice4_metrics(triplets)
    rows4 = build_slice4_rows(triplets)

    with tempfile.TemporaryDirectory() as tmpdir:
        csv_path = Path(tmpdir) / "slice3.csv"
        json_path = Path(tmpdir) / "slice3.json"
        write_artifacts(rows, slice3, csv_path, json_path)
        assert csv_path.exists()
        assert json_path.exists()
        payload = json.loads(json_path.read_text(encoding="utf-8"))
        assert payload["summary"]["aligned_count"] == 1
        assert len(payload["samples"]) == 1
        assert "truth_timestamp_s" in csv_path.read_text(encoding="utf-8")

        csv_path4 = Path(tmpdir) / "slice4.csv"
        json_path4 = Path(tmpdir) / "slice4.json"
        write_artifacts(rows4, slice4, csv_path4, json_path4)
        assert csv_path4.exists()
        assert json_path4.exists()
        assert slice4["dropout_recovery_s"] is not None

    rejected = align_samples(
        [{"timestamp_s": 0.0}],
        [{"timestamp_s": 0.25}],
        max_skew_ms=100,
    )
    assert len(rejected) == 0


def main() -> int:
    parser = argparse.ArgumentParser()
    _ = parser.add_argument("--self-test", action="store_true", help="run the built-in fixture test")
    args = parser.parse_args()
    if args.self_test:
        _fixture_test()
        print("phase7_harness_metrics self-test passed")
    return 0


if __name__ == "__main__":
    exit_code = main()
    raise SystemExit(exit_code)
