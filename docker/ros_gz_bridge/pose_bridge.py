#!/usr/bin/env python3
# pyright: reportMissingImports=false, reportMissingTypeStubs=false, reportGeneralTypeIssues=false, reportInvalidTypeForm=false, reportCallIssue=false
import argparse
import sys
from typing import Any, List, Optional, Tuple

try:
    import rclpy
    from geometry_msgs.msg import PoseStamped
    from rclpy.node import Node
except ModuleNotFoundError:
    rclpy = None  # type: ignore[assignment]
    PoseStamped = Any  # type: ignore[assignment,misc]
    Node = object

try:
    import gz.transport13 as gt
    from gz.msgs10.pose_v_pb2 import Pose_V
except ModuleNotFoundError:
    gt = None  # type: ignore[assignment]
    Pose_V = None  # type: ignore[assignment]


class GzModelPollBridge(Node):
    def __init__(self) -> None:
        super().__init__('gz_model_poll_bridge')

        self.declare_parameter('ownship_model', 'rc_cessna_0')
        self.declare_parameter('rival_model', 'rc_cessna_1')
        self.declare_parameter('poll_rate', 10.0)

        self.ownship_model = str(self.get_parameter('ownship_model').value)
        self.rival_model = str(self.get_parameter('rival_model').value)
        self.poll_rate = float(self.get_parameter('poll_rate').value)

        if gt is None or Pose_V is None:
            raise RuntimeError('gz transport python bindings are not available (expected gz.transport13 + gz.msgs10)')

        self.ownship_pub = self.create_publisher(PoseStamped, '/competition/ownship/state', 10)
        self.rival_pub = self.create_publisher(PoseStamped, '/fusion/rival/state', 10)

        self._gz_node = gt.Node()
        self._subscribe_pose_info('/world/default/pose/info')

        self.get_logger().info(
            f'GZ model poll bridge started: subscribing /world/default/pose/info '
            f'for {self.ownship_model} and {self.rival_model}'
        )

    def _subscribe_pose_info(self, topic_name: str) -> None:
        subscribed = False

        subscribe_fn = getattr(self._gz_node, 'subscribe', None)
        if callable(subscribe_fn):
            try:
                subscribed = bool(subscribe_fn(Pose_V, topic_name, self._pose_info_callback))
            except TypeError:
                try:
                    subscribed = bool(subscribe_fn(topic_name, self._pose_info_callback))
                except TypeError:
                    subscribed = False

        if not subscribed:
            subscribe_fn = getattr(self._gz_node, 'Subscribe', None)
            if callable(subscribe_fn):
                try:
                    subscribed = bool(subscribe_fn(topic_name, self._pose_info_callback))
                except TypeError:
                    subscribed = False

        if not subscribed:
            raise RuntimeError(f'failed to subscribe to {topic_name} with gz transport node')

    def _pose_info_callback(self, msg: Any) -> None:
        pose_vector = self._coerce_pose_vector(msg)
        if pose_vector is None:
            return

        stamp = self.get_clock().now().to_msg()

        for pose in pose_vector.pose:
            model_name = getattr(pose, 'name', '')
            if self._model_name_matches(model_name, self.ownship_model):
                self.ownship_pub.publish(self._to_pose_stamped(pose, stamp))
            elif self._model_name_matches(model_name, self.rival_model):
                self.rival_pub.publish(self._to_pose_stamped(pose, stamp))

    def _coerce_pose_vector(self, msg: Any) -> Optional[Any]:
        if hasattr(msg, 'pose'):
            return msg

        if Pose_V is None:
            return None

        try:
            if isinstance(msg, (bytes, bytearray)):
                pose_vector = Pose_V()
                pose_vector.ParseFromString(msg)
                return pose_vector
        except Exception as exc:  # noqa: BLE001
            self.get_logger().warn(f'Failed to parse Pose_V message: {exc}')
            return None

        return None

    @staticmethod
    def _model_name_matches(observed_name: str, target_name: str) -> bool:
        if observed_name == target_name:
            return True

        tokens = observed_name.split('::')
        if tokens and (tokens[0] == target_name or tokens[-1] == target_name):
            return True

        return False

    @staticmethod
    def _to_pose_stamped(pose: Any, stamp: Any) -> PoseStamped:
        ros_pose = PoseStamped()
        ros_pose.header.stamp = stamp
        ros_pose.header.frame_id = 'world'
        ros_pose.pose.position.x = float(pose.position.x)
        ros_pose.pose.position.y = float(pose.position.y)
        ros_pose.pose.position.z = float(pose.position.z)
        ros_pose.pose.orientation.x = float(pose.orientation.x)
        ros_pose.pose.orientation.y = float(pose.orientation.y)
        ros_pose.pose.orientation.z = float(pose.orientation.z)
        ros_pose.pose.orientation.w = float(pose.orientation.w)
        return ros_pose


def _parse_cli_args(argv: List[str]) -> Tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(description='Subscribe to Gazebo Pose_V and publish PoseStamped topics')
    _ = parser.add_argument('--once', action='store_true', help='Spin once and exit (self-test)')
    return parser.parse_known_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    args, ros_args = _parse_cli_args(argv)

    if rclpy is None:
        print('rclpy is not available in this environment', file=sys.stderr)
        return 1

    rclpy.init(args=ros_args)
    node = GzModelPollBridge()

    try:
        if args.once:
            rclpy.spin_once(node, timeout_sec=1.0)
            return 0
        rclpy.spin(node)
        return 0
    except KeyboardInterrupt:
        return 0
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    sys.exit(main())
