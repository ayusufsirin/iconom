#!/usr/bin/env python3
"""Contract tests for aircraft detector MarkerArray output."""

from __future__ import annotations

# pyright: reportAny=false, reportExplicitAny=false, reportMissingImports=false, reportMissingTypeStubs=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false, reportUnknownParameterType=false, reportMissingParameterType=false, reportUnusedFunction=false, reportUnannotatedClassAttribute=false, reportPossiblyUnboundVariable=false, reportMissingTypeArgument=false, reportUnusedImport=false, reportGeneralTypeIssues=false, reportIndexIssue=false, reportAttributeAccessIssue=false, reportImplicitStringConcatenation=false, reportUntypedBaseClass=false, reportUnusedCallResult=false, reportUnusedParameter=false

import importlib
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _install_stubs() -> None:
    if "rclpy" not in sys.modules:
        rclpy = types.ModuleType("rclpy")
        rclpy.init = lambda *args, **kwargs: None
        rclpy.ok = lambda: False
        rclpy.spin_once = lambda *args, **kwargs: None
        rclpy.shutdown = lambda: None

        rclpy_node = types.ModuleType("rclpy.node")

        class Node:
            def __init__(self, *args, **kwargs):
                pass

        rclpy_node.Node = Node
        rclpy_qos = types.ModuleType("rclpy.qos")
        rclpy_qos.qos_profile_sensor_data = object()
        rclpy.node = rclpy_node
        rclpy.qos = rclpy_qos
        sys.modules["rclpy"] = rclpy
        sys.modules["rclpy.node"] = rclpy_node
        sys.modules["rclpy.qos"] = rclpy_qos

    if "cv_bridge" not in sys.modules:
        cv_bridge = types.ModuleType("cv_bridge")

        class CvBridge:
            pass

        class CvBridgeError(Exception):
            pass

        cv_bridge.CvBridge = CvBridge
        cv_bridge.CvBridgeError = CvBridgeError
        sys.modules["cv_bridge"] = cv_bridge

    if "sensor_msgs" not in sys.modules:
        sensor_msgs = types.ModuleType("sensor_msgs")
        sensor_msgs_msg = types.ModuleType("sensor_msgs.msg")

        class Image:
            pass

        sensor_msgs_msg.Image = Image
        sensor_msgs.msg = sensor_msgs_msg
        sys.modules["sensor_msgs"] = sensor_msgs
        sys.modules["sensor_msgs.msg"] = sensor_msgs_msg

    if "ultralytics" not in sys.modules:
        ultralytics = types.ModuleType("ultralytics")

        class YOLO:
            def __init__(self, *args, **kwargs):
                self.names = {0: "airplane"}

            def to(self, *args, **kwargs):
                return self

            def __call__(self, *args, **kwargs):
                return []

        ultralytics.YOLO = YOLO
        sys.modules["ultralytics"] = ultralytics

    if "visualization_msgs" not in sys.modules:
        visualization_msgs = types.ModuleType("visualization_msgs")
        visualization_msgs_msg = types.ModuleType("visualization_msgs.msg")

        class Marker:
            DELETEALL = 3
            ADD = 0
            CUBE = 1

            def __init__(self):
                self.header = types.SimpleNamespace()
                self.ns = ""
                self.id = 0
                self.action = 0
                self.type = 0
                self.pose = types.SimpleNamespace(
                    position=types.SimpleNamespace(x=0.0, y=0.0, z=0.0),
                    orientation=types.SimpleNamespace(x=0.0, y=0.0, z=0.0, w=1.0),
                )
                self.scale = types.SimpleNamespace(x=0.0, y=0.0, z=0.0)
                self.color = types.SimpleNamespace(r=0.0, g=0.0, b=0.0, a=0.0)
                self.text = ""

        class MarkerArray:
            def __init__(self):
                self.markers = []

        visualization_msgs_msg.Marker = Marker
        visualization_msgs_msg.MarkerArray = MarkerArray
        visualization_msgs.msg = visualization_msgs_msg
        sys.modules["visualization_msgs"] = visualization_msgs
        sys.modules["visualization_msgs.msg"] = visualization_msgs_msg


_install_stubs()
aircraft_detector = importlib.import_module("iconom_vision.aircraft_detector")


class _FakeTensor:
    def __init__(self, values):
        self._values = values

    def cpu(self):
        return self

    def numpy(self):
        return self

    def astype(self, dtype):
        if dtype is int:
            return _FakeTensor([int(v) for v in self._values])
        return self

    def __iter__(self):
        return iter(self._values)

    def __getitem__(self, index):
        return self._values[index]


class _FakeBoxes:
    def __init__(self, xyxy, cls, conf):
        self.xyxy = _FakeTensor(xyxy)
        self.cls = _FakeTensor(cls)
        self.conf = _FakeTensor(conf)


class _FakeResult:
    def __init__(self, boxes):
        self.boxes = boxes


def _build_detector():
    detector = object.__new__(aircraft_detector.AircraftDetector)
    detector.model = types.SimpleNamespace(names={0: "airplane"})
    detector.get_logger = lambda: types.SimpleNamespace(info=lambda *args, **kwargs: None, warn=lambda *args, **kwargs: None, error=lambda *args, **kwargs: None)
    detector._allowed_labels = {"airplane"}
    detector._empty_count = 0
    detector._log_interval = 30
    return detector


def test_detector_emits_deleteall_first():
    detector = _build_detector()
    msg = types.SimpleNamespace(header=types.SimpleNamespace())
    marker_array = detector._build_marker_array(
        [_FakeResult(_FakeBoxes([[10.0, 20.0, 30.0, 44.0]], [0], [0.91]))], msg
    )

    assert marker_array.markers[0].action == aircraft_detector.Marker.DELETEALL


def test_detector_encodes_bbox_center_scale_and_text():
    detector = _build_detector()
    msg = types.SimpleNamespace(header=types.SimpleNamespace())
    marker_array = detector._build_marker_array(
        [_FakeResult(_FakeBoxes([[10.0, 20.0, 30.0, 44.0]], [0], [0.91]))], msg
    )

    marker = marker_array.markers[1]
    assert marker.pose.position.x == 20.0
    assert marker.pose.position.y == 32.0
    assert marker.scale.x == 20.0
    assert marker.scale.y == 24.0
    assert marker.text == "airplane:0.91"