#!/usr/bin/env python3
import math
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node


OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
RIVAL_STATE_TOPIC = "/competition/rival/state"


def yaw_from_quaternion(z: float, w: float) -> float:
    return math.atan2(2.0 * w * z, 1.0 - 2.0 * z * z)


class ScriptedRivalPublisher(Node):
    def __init__(self) -> None:
        super().__init__("scripted_rival_publisher")

        self.declare_parameter("publish_period_sec", 0.5)
        self.declare_parameter("rival_id", "plane_02")
        self.declare_parameter("bearing_offset_deg", 90.0)
        self.declare_parameter("distance_m", 150.0)
        self.declare_parameter("altitude_offset_m", 0.0)

        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self.rival_id = str(self.get_parameter("rival_id").value)
        self.bearing_offset_deg = float(self.get_parameter("bearing_offset_deg").value)
        self.distance_m = float(self.get_parameter("distance_m").value)
        self.altitude_offset_m = float(self.get_parameter("altitude_offset_m").value)

        self.initial_ownship_state: Optional[PoseStamped] = None
        self.fixed_rival_state: Optional[PoseStamped] = None
        self.publisher = self.create_publisher(PoseStamped, RIVAL_STATE_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.timer = self.create_timer(self.publish_period_sec, self._publish_rival)

        self.get_logger().info(
            f"scripted rival publisher listening on {OWNSHIP_STATE_TOPIC}; publishing fixed rival {self.rival_id} on {RIVAL_STATE_TOPIC}"
        )

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        if self.fixed_rival_state is not None:
            return

        self.initial_ownship_state = msg
        own = msg.pose.position
        heading = yaw_from_quaternion(msg.pose.orientation.z, msg.pose.orientation.w)
        target_heading = heading + math.radians(self.bearing_offset_deg)

        rival = PoseStamped()
        rival.header.frame_id = self.rival_id
        rival.pose.position.x = own.x + self.distance_m * math.cos(target_heading)
        rival.pose.position.y = own.y + self.distance_m * math.sin(target_heading)
        rival.pose.position.z = own.z + self.altitude_offset_m
        rival.pose.orientation = msg.pose.orientation

        self.fixed_rival_state = rival
        self.get_logger().info(
            f"initialized scripted rival {self.rival_id} at ({rival.pose.position.x:.1f}, {rival.pose.position.y:.1f}, {rival.pose.position.z:.1f})"
        )

    def _publish_rival(self) -> None:
        if self.fixed_rival_state is None:
            return

        self.fixed_rival_state.header.stamp = self.get_clock().now().to_msg()
        self.publisher.publish(self.fixed_rival_state)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = ScriptedRivalPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
