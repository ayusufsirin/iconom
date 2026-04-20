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
    if "geometry_msgs" not in sys.modules:
        geometry_msgs = types.ModuleType("geometry_msgs")
        geometry_msgs_msg = types.ModuleType("geometry_msgs.msg")

        class PoseStamped:
            def __init__(self):
                self.header = types.SimpleNamespace(
                    stamp=types.SimpleNamespace(sec=0, nanosec=0),
                    frame_id="",
                )
                self.pose = types.SimpleNamespace(
                    position=types.SimpleNamespace(x=0.0, y=0.0, z=0.0),
                    orientation=types.SimpleNamespace(x=0.0, y=0.0, z=0.0, w=1.0),
                )

        geometry_msgs_msg.PoseStamped = PoseStamped
        geometry_msgs.msg = geometry_msgs_msg
        sys.modules["geometry_msgs"] = geometry_msgs
        sys.modules["geometry_msgs.msg"] = geometry_msgs_msg

    if "std_msgs" not in sys.modules:
        std_msgs = types.ModuleType("std_msgs")
        std_msgs_msg = types.ModuleType("std_msgs.msg")

        class String:
            def __init__(self):
                self.data = ""

        std_msgs_msg.String = String
        std_msgs.msg = std_msgs_msg
        sys.modules["std_msgs"] = std_msgs
        sys.modules["std_msgs.msg"] = std_msgs_msg

    if "rclpy" not in sys.modules:
        rclpy = types.ModuleType("rclpy")
        rclpy_node = types.ModuleType("rclpy.node")
        rclpy_qos = types.ModuleType("rclpy.qos")

        class _FakeNow:
            def __init__(self, sec: float):
                self.nanoseconds = int(sec * 1_000_000_000)

            def to_msg(self):
                whole = int(self.nanoseconds // 1_000_000_000)
                nanos = int(self.nanoseconds % 1_000_000_000)
                return types.SimpleNamespace(sec=whole, nanosec=nanos)

        class _FakeClock:
            def __init__(self):
                self._time_sec = 0.0

            def now(self):
                return _FakeNow(self._time_sec)

            def set_time(self, sec: float) -> None:
                self._time_sec = sec

        class _FakeLogger:
            def info(self, _msg: str) -> None:
                return None

            def warn(self, _msg: str, **_kwargs) -> None:
                return None

        class _FakePublisher:
            def __init__(self):
                self.published = []

            def publish(self, msg):
                self.published.append(msg)

        class Node:
            parameter_overrides: dict[str, object] = {}

            def __init__(self, _name: str):
                self._params: dict[str, object] = {}
                self._clock = _FakeClock()
                self._logger = _FakeLogger()
                self.subscriptions = []
                self.publishers = []
                self.timers = []

            def declare_parameter(self, name: str, default_value):
                self._params[name] = self.parameter_overrides.get(name, default_value)

            def get_parameter(self, name: str):
                return types.SimpleNamespace(value=self._params[name])

            def create_subscription(self, msg_type, topic: str, callback, qos):
                sub = types.SimpleNamespace(msg_type=msg_type, topic=topic, callback=callback, qos=qos)
                self.subscriptions.append(sub)
                return sub

            def create_publisher(self, msg_type, topic: str, depth: int):
                pub = _FakePublisher()
                pub.msg_type = msg_type
                pub.topic = topic
                pub.depth = depth
                self.publishers.append(pub)
                return pub

            def create_timer(self, period: float, callback):
                timer = types.SimpleNamespace(period=period, callback=callback)
                self.timers.append(timer)
                return timer

            def get_clock(self):
                return self._clock

            def get_logger(self):
                return self._logger

            def destroy_node(self):
                return None

        class QoSProfile:
            def __init__(self, reliability=None, history=None, depth=10):
                self.reliability = reliability
                self.history = history
                self.depth = depth

        class ReliabilityPolicy:
            BEST_EFFORT = "best_effort"

        class HistoryPolicy:
            KEEP_LAST = "keep_last"

        def init(args=None):
            return None

        def shutdown():
            return None

        def spin(_node):
            return None

        rclpy.init = init
        rclpy.shutdown = shutdown
        rclpy.spin = spin
        rclpy.node = rclpy_node
        rclpy.qos = rclpy_qos

        rclpy_node.Node = Node
        rclpy_qos.QoSProfile = QoSProfile
        rclpy_qos.ReliabilityPolicy = ReliabilityPolicy
        rclpy_qos.HistoryPolicy = HistoryPolicy

        sys.modules["rclpy"] = rclpy
        sys.modules["rclpy.node"] = rclpy_node
        sys.modules["rclpy.qos"] = rclpy_qos


def _pose(*, x: float, y: float = 0.0, z: float = 0.0, stamp: float | None = None):
    msg_cls = importlib.import_module("geometry_msgs.msg").PoseStamped
    global _pose_call_count
    msg = msg_cls()
    if stamp is None:
        stamp = _pose_call_count * 0.5
        _pose_call_count += 1
    msg.header.stamp.sec = int(stamp)
    msg.header.stamp.nanosec = int(round((stamp - int(stamp)) * 1_000_000_000))
    msg.pose.position.x = x
    msg.pose.position.y = y
    msg.pose.position.z = z
    return msg


_pose_call_count = 0


def _load_module_with_overrides(overrides: dict[str, object]):
    _install_stubs()
    node_cls = importlib.import_module("rclpy.node").Node
    node_cls.parameter_overrides = overrides
    sys.modules.pop("iconom_competition.ekf_fusion", None)
    return importlib.import_module("iconom_competition.ekf_fusion")


def test_phase6_defaults_remain_unchanged():
    mod = _load_module_with_overrides({})
    node = mod.EKFFusion()

    assert node.high_rate_input_topic == "/competition/rival/state/live"
    assert node.high_rate_input_requires_follow_lock is True
    assert node.publish_rate_hz == 20.0
    assert math.isclose(node.timer.period, 0.05)


def test_phase7_visual_input_mode_bypasses_follow_lock_and_uses_30hz():
    mod = _load_module_with_overrides(
        {
            "high_rate_input_topic": "/vision/rival_pose",
            "high_rate_input_requires_follow_lock": False,
            "publish_rate_hz": 30.0,
        }
    )
    node = mod.EKFFusion()

    assert node.high_rate_input_topic == "/vision/rival_pose"
    assert node.high_rate_input_requires_follow_lock is False
    assert math.isclose(node.timer.period, 1.0 / 30.0)
    assert node.live_sub.topic == "/vision/rival_pose"

    node.get_clock().set_time(1.0)
    node._handle_live(_pose(x=12.0, y=-3.0, z=40.0))

    assert node.live_received is True
    assert node.state[0] == 12.0
    assert node.state[1] == -3.0
    assert node.state[2] == 40.0


def test_referee_only_fallback_still_publishes_fused_output():
    mod = _load_module_with_overrides({})
    node = mod.EKFFusion()

    node.get_clock().set_time(2.0)
    node._handle_referee(_pose(x=100.0, y=15.0, z=6.0))
    node._publish_fused()

    assert len(node.fused_pub.published) == 1
    fused = node.fused_pub.published[0]
    assert fused.pose.position.x == 100.0
    assert fused.pose.position.y == 15.0
    assert fused.pose.position.z == 6.0
    assert fused.header.frame_id == "fusion"


def test_dropout_recovery_preserves_velocity_for_long_gap_then_recovers_on_short_gap():
    mod = _load_module_with_overrides(
        {
            "high_rate_input_topic": "/vision/rival_pose",
            "high_rate_input_requires_follow_lock": False,
        }
    )
    node = mod.EKFFusion()

    node.get_clock().set_time(0.0)
    node._handle_live(_pose(x=0.0, stamp=0.0))

    node.get_clock().set_time(0.5)
    node._handle_live(_pose(x=5.0, stamp=0.5))
    velocity_after_short_gap = node.state[3]
    assert velocity_after_short_gap > 0.0

    node.get_clock().set_time(2.0)
    node._handle_live(_pose(x=20.0, stamp=2.0))
    assert math.isclose(node.state[3], velocity_after_short_gap, rel_tol=1e-9, abs_tol=1e-9)

    node.get_clock().set_time(2.2)
    node._handle_live(_pose(x=24.0, stamp=2.2))
    assert node.state[3] > velocity_after_short_gap
