#!/usr/bin/env python3
import math
import os

import rclpy
from geometry_msgs.msg import PoseStamped
from px4_msgs.msg import VehicleLocalPosition
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import Header


AIRCRAFT_ID = os.environ.get("RIVAL_AIRCRAFT_ID", "plane_02")
RIVAL_STATE_TOPIC = "/competition/rival/state"


class LiveRivalStateAdapter(Node):
    def __init__(self) -> None:
        super().__init__("live_rival_state_adapter")

        self.declare_parameter("aircraft_id", AIRCRAFT_ID)
        self.declare_parameter("publish_rate_hz", 20.0)

        self.aircraft_id = str(self.get_parameter("aircraft_id").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.local_position_topic = f"/{self.aircraft_id}/fmu/out/vehicle_local_position"

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.latest_velocity = None
        self.latest_msg = None
        self.rival_state_pub = self.create_publisher(PoseStamped, RIVAL_STATE_TOPIC, 10)
        self.position_sub = self.create_subscription(
            VehicleLocalPosition,
            self.local_position_topic,
            self._handle_position,
            qos,
        )

        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._publish_rival)

        self.get_logger().info(
            f"live rival adapter starting for {self.aircraft_id}; subscribing to {self.local_position_topic} "
            f"and publishing {RIVAL_STATE_TOPIC} at {self.publish_rate_hz}Hz"
        )

    def _compute_heading(self) -> float:
        if self.latest_velocity is None:
            return 0.0
        vx = self.latest_velocity[0]
        vy = self.latest_velocity[1]
        if abs(vx) > 0.1 or abs(vy) > 0.1:
            return math.atan2(vy, vx)
        return 0.0

    def _handle_position(self, msg: VehicleLocalPosition) -> None:
        self.latest_velocity = (float(msg.vx), float(msg.vy), float(msg.vz))
        self.latest_msg = msg

    def _publish_rival(self) -> None:
        if self.latest_msg is None:
            return

        msg = self.latest_msg
        heading = self._compute_heading()

        rival = PoseStamped()
        rival.header = Header()
        rival.header.stamp = self.get_clock().now().to_msg()
        rival.header.frame_id = self.aircraft_id
        rival.pose.position.x = float(msg.x)
        rival.pose.position.y = float(msg.y)
        rival.pose.position.z = float(msg.z)
        rival.pose.orientation.x = 0.0
        rival.pose.orientation.y = 0.0
        rival.pose.orientation.z = math.sin(heading / 2.0)
        rival.pose.orientation.w = math.cos(heading / 2.0)
        self.rival_state_pub.publish(rival)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = LiveRivalStateAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
