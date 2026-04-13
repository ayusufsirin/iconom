#!/usr/bin/env python3
# pyright: reportMissingImports=false, reportMissingTypeStubs=false, reportGeneralTypeIssues=false, reportInvalidTypeForm=false, reportCallIssue=false
import argparse
import math
import re
import subprocess
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


class GzModelPollBridge(Node):
    def __init__(self) -> None:
        super().__init__('gz_model_poll_bridge')

        self.declare_parameter('ownship_model', 'rc_cessna_0')
        self.declare_parameter('rival_model', 'rc_cessna_1')
        self.declare_parameter('poll_rate', 10.0)

        self.ownship_model = str(self.get_parameter('ownship_model').value)
        self.rival_model = str(self.get_parameter('rival_model').value)
        self.poll_rate = float(self.get_parameter('poll_rate').value)

        self.ownship_pub = self.create_publisher(PoseStamped, '/competition/ownship/state', 10)
        self.rival_pub = self.create_publisher(PoseStamped, '/fusion/rival/state', 10)

        timer_period = 1.0 / self.poll_rate if self.poll_rate > 0.0 else 0.1
        self.timer = self.create_timer(timer_period, self._poll_models)

        self.get_logger().info(
            'GZ model poll bridge started: polling rc_cessna_0 and rc_cessna_1 at 10 Hz'
        )

    def _poll_models(self) -> None:
        ownship_pose = self._query_pose(self.ownship_model)
        rival_pose = self._query_pose(self.rival_model)

        if ownship_pose is not None:
            self.ownship_pub.publish(ownship_pose)

        if rival_pose is not None:
            self.rival_pub.publish(rival_pose)

    def _query_pose(self, model_name: str) -> Optional[PoseStamped]:
        try:
            result = subprocess.run(
                ['gz', 'model', '-m', model_name, '-p'],
                capture_output=True,
                text=True,
                timeout=1.0,
            )
            if result.returncode != 0:
                self.get_logger().warn(f'gz model query failed for {model_name}: {result.stderr.strip()}')
                return None

            matches = re.findall(r'\[([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\]', result.stdout)
            if len(matches) < 2:
                self.get_logger().warn(f'Failed to parse gz model output for {model_name}')
                return None

            x, y, z = (float(v) for v in matches[0])
            roll, pitch, yaw = (float(v) for v in matches[1])
            qx, qy, qz, qw = self._rpy_to_quaternion(roll, pitch, yaw)

            pose = PoseStamped()
            pose.header.stamp = self.get_clock().now().to_msg()
            pose.header.frame_id = 'world'
            pose.pose.position.x = x
            pose.pose.position.y = y
            pose.pose.position.z = z
            pose.pose.orientation.x = qx
            pose.pose.orientation.y = qy
            pose.pose.orientation.z = qz
            pose.pose.orientation.w = qw
            return pose
        except subprocess.TimeoutExpired:
            self.get_logger().warn(f'Timeout querying gz model pose for {model_name}')
            return None
        except Exception as exc:  # noqa: BLE001
            self.get_logger().warn(f'Failed to query pose for {model_name}: {exc}')
            return None

    @staticmethod
    def _rpy_to_quaternion(roll: float, pitch: float, yaw: float) -> Tuple[float, float, float, float]:
        cy = math.cos(yaw * 0.5)
        sy = math.sin(yaw * 0.5)
        cp = math.cos(pitch * 0.5)
        sp = math.sin(pitch * 0.5)
        cr = math.cos(roll * 0.5)
        sr = math.sin(roll * 0.5)

        qw = cr * cp * cy + sr * sp * sy
        qx = sr * cp * cy - cr * sp * sy
        qy = cr * sp * cy + sr * cp * sy
        qz = cr * cp * sy - sr * sp * cy
        return qx, qy, qz, qw


def _parse_cli_args(argv: List[str]) -> Tuple[argparse.Namespace, List[str]]:
    parser = argparse.ArgumentParser(description='Poll Gazebo model poses and publish PoseStamped topics')
    _ = parser.add_argument('--once', action='store_true', help='Poll once and exit (self-test)')
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
            node._poll_models()
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
