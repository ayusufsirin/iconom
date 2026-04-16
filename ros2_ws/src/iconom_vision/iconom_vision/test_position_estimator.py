from __future__ import annotations

# pyright: reportAny=false, reportExplicitAny=false, reportMissingImports=false, reportMissingTypeStubs=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false, reportUnknownParameterType=false, reportMissingParameterType=false, reportUnusedFunction=false, reportUnannotatedClassAttribute=false, reportPossiblyUnboundVariable=false, reportMissingTypeArgument=false, reportUnusedImport=false, reportGeneralTypeIssues=false, reportIndexIssue=false, reportAttributeAccessIssue=false, reportImplicitStringConcatenation=false, reportUnknownLambdaType=false, reportUnusedCallResult=false, reportUntypedBaseClass=false, reportUnusedParameter=false

import importlib
import math
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _install_stubs() -> None:
    if "visualization_msgs" not in sys.modules:
        visualization_msgs = types.ModuleType("visualization_msgs")
        visualization_msgs_msg = types.ModuleType("visualization_msgs.msg")

        class Marker:
            DELETEALL = 3
            ADD = 0

            def __init__(self):
                self.header = types.SimpleNamespace(stamp=types.SimpleNamespace(sec=0, nanosec=0), frame_id="")
                self.action = 0
                self.pose = types.SimpleNamespace(position=types.SimpleNamespace(x=0.0, y=0.0, z=0.0))
                self.scale = types.SimpleNamespace(x=0.0, y=0.0, z=0.0)

        class MarkerArray:
            def __init__(self):
                self.markers = []

        visualization_msgs_msg.Marker = Marker
        visualization_msgs_msg.MarkerArray = MarkerArray
        visualization_msgs.msg = visualization_msgs_msg
        sys.modules["visualization_msgs"] = visualization_msgs
        sys.modules["visualization_msgs.msg"] = visualization_msgs_msg

    if "sensor_msgs" not in sys.modules:
        sensor_msgs = types.ModuleType("sensor_msgs")
        sensor_msgs_msg = types.ModuleType("sensor_msgs.msg")

        class CameraInfo:
            def __init__(self):
                self.header = types.SimpleNamespace(stamp=types.SimpleNamespace(sec=0, nanosec=0), frame_id="")
                self.k = [0.0] * 9
                self.width = 0
                self.height = 0

        sensor_msgs_msg.CameraInfo = CameraInfo
        sensor_msgs.msg = sensor_msgs_msg
        sys.modules["sensor_msgs"] = sensor_msgs
        sys.modules["sensor_msgs.msg"] = sensor_msgs_msg

    if "geometry_msgs" not in sys.modules:
        geometry_msgs = types.ModuleType("geometry_msgs")
        geometry_msgs_msg = types.ModuleType("geometry_msgs.msg")

        class PoseStamped:
            def __init__(self):
                self.header = types.SimpleNamespace(stamp=types.SimpleNamespace(sec=0, nanosec=0), frame_id="")
                self.pose = types.SimpleNamespace(
                    position=types.SimpleNamespace(x=0.0, y=0.0, z=0.0),
                    orientation=types.SimpleNamespace(x=0.0, y=0.0, z=0.0, w=1.0),
                )

        geometry_msgs_msg.PoseStamped = PoseStamped
        geometry_msgs.msg = geometry_msgs_msg
        sys.modules["geometry_msgs"] = geometry_msgs
        sys.modules["geometry_msgs.msg"] = geometry_msgs_msg


_install_stubs()

constants = importlib.import_module("iconom_vision.position_estimator_constants")
Marker = importlib.import_module("visualization_msgs.msg").Marker
MarkerArray = importlib.import_module("visualization_msgs.msg").MarkerArray
PoseStamped = importlib.import_module("geometry_msgs.msg").PoseStamped
CameraInfo = importlib.import_module("sensor_msgs.msg").CameraInfo


def _stamp(seconds: float):
    whole = int(seconds)
    frac = seconds - float(whole)
    return types.SimpleNamespace(sec=whole, nanosec=int(round(frac * 1_000_000_000)))


def _stamp_seconds(stamp) -> float:
    return float(stamp.sec) + float(stamp.nanosec) * 1e-9


def _build_camera_info(*, fx: float, fy: float, cx: float, cy: float, stamp_s: float):
    msg = CameraInfo()
    msg.header.stamp = _stamp(stamp_s)
    msg.k = [fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0]
    msg.width = 640
    msg.height = 480
    return msg


def _build_ownship(*, x: float, y: float, z: float, stamp_s: float):
    msg = PoseStamped()
    msg.header.stamp = _stamp(stamp_s)
    msg.header.frame_id = "world"
    msg.pose.position.x = x
    msg.pose.position.y = y
    msg.pose.position.z = z
    return msg


def _build_detection_array(*, cx: float, cy: float, w: float, h: float, stamp_s: float):
    marker_array = MarkerArray()
    clear = Marker()
    clear.action = Marker.DELETEALL
    marker_array.markers.append(clear)

    marker = Marker()
    marker.action = Marker.ADD
    marker.header.stamp = _stamp(stamp_s)
    marker.pose.position.x = cx
    marker.pose.position.y = cy
    marker.scale.x = w
    marker.scale.y = h
    marker_array.markers.append(marker)
    return marker_array


def _extract_bbox_measurement(marker_array):
    for marker in marker_array.markers:
        if marker.action == Marker.ADD:
            return (
                float(marker.pose.position.x),
                float(marker.pose.position.y),
                float(marker.scale.x),
                float(marker.scale.y),
                marker.header.stamp,
            )
    return None


def _estimate_depth_m(bbox_width_px: float, bbox_height_px: float, camera_info) -> float | None:
    if bbox_width_px <= 0.0 or bbox_height_px <= 0.0:
        return None
    if len(camera_info.k) < 9:
        return None
    fx = float(camera_info.k[0])
    fy = float(camera_info.k[4])
    if fx <= 0.0 or fy <= 0.0:
        return None

    depth_from_width = fx * constants.RIVAL_WINGSPAN_M / bbox_width_px
    depth_from_height = fy * constants.RIVAL_HEIGHT_M / bbox_height_px
    return (depth_from_width + depth_from_height) / 2.0


def _project_measurement_to_world_pose(
    *,
    center_u: float,
    center_v: float,
    depth_m: float,
    camera_info,
    ownship_pose,
    out_stamp,
):
    if depth_m <= 0.0:
        return None
    if len(camera_info.k) < 9:
        return None

    fx = float(camera_info.k[0])
    fy = float(camera_info.k[4])
    cx = float(camera_info.k[2])
    cy = float(camera_info.k[5])
    if fx <= 0.0 or fy <= 0.0:
        return None

    lateral_m = (center_u - cx) * depth_m / fx
    vertical_m = (center_v - cy) * depth_m / fy

    pose = PoseStamped()
    pose.header.frame_id = "world"
    pose.header.stamp = out_stamp
    pose.pose.position.x = ownship_pose.pose.position.x + depth_m
    pose.pose.position.y = ownship_pose.pose.position.y + lateral_m
    pose.pose.position.z = ownship_pose.pose.position.z + vertical_m
    return pose


def _is_stale(msg, *, now_s: float, timeout_s: float) -> bool:
    stamp_s = _stamp_seconds(msg.header.stamp)
    return now_s - stamp_s > timeout_s


def _estimate_pose_from_marker_array(
    marker_array,
    camera_info,
    ownship_pose,
    *,
    now_s: float,
    max_staleness_s: float,
):
    if marker_array is None or not marker_array.markers:
        return None
    if camera_info is None or _is_stale(camera_info, now_s=now_s, timeout_s=max_staleness_s):
        return None
    if ownship_pose is None or _is_stale(ownship_pose, now_s=now_s, timeout_s=max_staleness_s):
        return None

    measurement = _extract_bbox_measurement(marker_array)
    if measurement is None:
        return None

    center_u, center_v, bbox_w, bbox_h, detection_stamp = measurement
    depth_m = _estimate_depth_m(bbox_w, bbox_h, camera_info)
    if depth_m is None:
        return None

    return _project_measurement_to_world_pose(
        center_u=center_u,
        center_v=center_v,
        depth_m=depth_m,
        camera_info=camera_info,
        ownship_pose=ownship_pose,
        out_stamp=detection_stamp,
    )


class TestEstimatorConstants:
    def test_rival_dimensions_are_locked(self):
        assert constants.RIVAL_WINGSPAN_M == 1.2
        assert constants.RIVAL_LENGTH_M == 0.86
        assert constants.RIVAL_HEIGHT_M == 0.28


class TestMarkerArrayExtraction:
    def test_extract_bbox_center_and_size_from_marker_array(self):
        marker_array = _build_detection_array(cx=320.0, cy=240.0, w=120.0, h=42.0, stamp_s=11.5)
        measurement = _extract_bbox_measurement(marker_array)

        assert measurement is not None
        center_u, center_v, width_px, height_px, stamp = measurement
        assert center_u == 320.0
        assert center_v == 240.0
        assert width_px == 120.0
        assert height_px == 42.0
        assert _stamp_seconds(stamp) == 11.5

    def test_extract_returns_none_for_empty_detections(self):
        marker_array = MarkerArray()
        assert _extract_bbox_measurement(marker_array) is None


class TestDepthEstimation:
    def test_depth_estimation_from_known_dimensions(self):
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=1.0)
        depth_m = _estimate_depth_m(120.0, 42.0, camera_info)

        assert depth_m is not None
        expected_from_width = 600.0 * constants.RIVAL_WINGSPAN_M / 120.0
        expected_from_height = 600.0 * constants.RIVAL_HEIGHT_M / 42.0
        expected = (expected_from_width + expected_from_height) / 2.0
        assert math.isclose(depth_m, expected, rel_tol=1e-9, abs_tol=1e-9)

    def test_depth_monotonicity_larger_bbox_is_closer(self):
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=1.0)

        far_depth = _estimate_depth_m(60.0, 21.0, camera_info)
        near_depth = _estimate_depth_m(120.0, 42.0, camera_info)

        assert far_depth is not None
        assert near_depth is not None
        assert near_depth < far_depth


class TestProjectionToWorldPose:
    def test_projection_center_pixel_maps_straight_ahead(self):
        camera_info = _build_camera_info(fx=500.0, fy=500.0, cx=320.0, cy=240.0, stamp_s=2.0)
        ownship_pose = _build_ownship(x=100.0, y=200.0, z=50.0, stamp_s=2.0)

        world_pose = _project_measurement_to_world_pose(
            center_u=320.0,
            center_v=240.0,
            depth_m=10.0,
            camera_info=camera_info,
            ownship_pose=ownship_pose,
            out_stamp=_stamp(3.25),
        )

        assert world_pose is not None
        assert world_pose.header.frame_id == "world"
        assert _stamp_seconds(world_pose.header.stamp) == 3.25
        assert world_pose.pose.position.x == 110.0
        assert world_pose.pose.position.y == 200.0
        assert world_pose.pose.position.z == 50.0

    def test_projection_off_center_maps_lateral_and_vertical(self):
        camera_info = _build_camera_info(fx=500.0, fy=250.0, cx=320.0, cy=240.0, stamp_s=2.0)
        ownship_pose = _build_ownship(x=10.0, y=-2.0, z=3.0, stamp_s=2.0)

        world_pose = _project_measurement_to_world_pose(
            center_u=420.0,
            center_v=290.0,
            depth_m=20.0,
            camera_info=camera_info,
            ownship_pose=ownship_pose,
            out_stamp=_stamp(9.0),
        )

        assert world_pose is not None
        assert world_pose.pose.position.x == 30.0
        assert world_pose.pose.position.y == 2.0
        assert world_pose.pose.position.z == 7.0


class TestStalenessAndFailurePaths:
    def test_stale_camera_info_blocks_estimate(self):
        marker_array = _build_detection_array(cx=320.0, cy=240.0, w=120.0, h=42.0, stamp_s=10.0)
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=8.0)
        ownship_pose = _build_ownship(x=0.0, y=0.0, z=0.0, stamp_s=10.0)

        pose = _estimate_pose_from_marker_array(
            marker_array,
            camera_info,
            ownship_pose,
            now_s=10.0,
            max_staleness_s=1.0,
        )

        assert pose is None

    def test_stale_ownship_pose_blocks_estimate(self):
        marker_array = _build_detection_array(cx=320.0, cy=240.0, w=120.0, h=42.0, stamp_s=10.0)
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=10.0)
        ownship_pose = _build_ownship(x=0.0, y=0.0, z=0.0, stamp_s=8.5)

        pose = _estimate_pose_from_marker_array(
            marker_array,
            camera_info,
            ownship_pose,
            now_s=10.0,
            max_staleness_s=1.0,
        )

        assert pose is None

    def test_empty_detections_do_not_publish_pose(self):
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=5.0)
        ownship_pose = _build_ownship(x=2.0, y=3.0, z=4.0, stamp_s=5.0)

        pose = _estimate_pose_from_marker_array(
            MarkerArray(),
            camera_info,
            ownship_pose,
            now_s=5.1,
            max_staleness_s=1.0,
        )

        assert pose is None

    def test_valid_inputs_return_world_pose(self):
        marker_array = _build_detection_array(cx=330.0, cy=245.0, w=120.0, h=42.0, stamp_s=12.0)
        camera_info = _build_camera_info(fx=600.0, fy=600.0, cx=320.0, cy=240.0, stamp_s=12.0)
        ownship_pose = _build_ownship(x=1.0, y=2.0, z=3.0, stamp_s=12.0)

        pose = _estimate_pose_from_marker_array(
            marker_array,
            camera_info,
            ownship_pose,
            now_s=12.2,
            max_staleness_s=1.0,
        )

        assert pose is not None
        assert pose.header.frame_id == "world"
        assert _stamp_seconds(pose.header.stamp) == 12.0
        assert pose.pose.position.x > ownship_pose.pose.position.x
