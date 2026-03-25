#!/usr/bin/env python3
import math
import time
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node

OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
RIVAL_STATE_TOPIC = "/competition/rival/state"


def yaw_from_quaternion(z: float, w: float) -> float:
    return math.atan2(2.0 * w * z, 1.0 - 2.0 * z * z)


def quaternion_from_yaw(yaw: float) -> tuple[float, float]:
    return math.sin(yaw / 2.0), math.cos(yaw / 2.0)


class ScriptedRivalPublisher(Node):
    def __init__(self) -> None:
        super().__init__("scripted_rival_publisher")

        self.declare_parameter("publish_period_sec", 0.2)
        self.declare_parameter("rival_id", "plane_02")
        self.declare_parameter("bearing_offset_deg", 60.0)
        self.declare_parameter("distance_m", 120.0)
        self.declare_parameter("altitude_offset_m", 0.0)
        self.declare_parameter("rival_speed_mps", 12.0)
        self.declare_parameter("rival_course_offset_deg", -90.0)
        self.declare_parameter("route_duration_sec", 45.0)

        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self.rival_id = str(self.get_parameter("rival_id").value)
        self.bearing_offset_deg = float(self.get_parameter("bearing_offset_deg").value)
        self.distance_m = float(self.get_parameter("distance_m").value)
        self.altitude_offset_m = float(self.get_parameter("altitude_offset_m").value)
        self.rival_speed_mps = float(self.get_parameter("rival_speed_mps").value)
        self.rival_course_offset_deg = float(self.get_parameter("rival_course_offset_deg").value)
        self.route_duration_sec = float(self.get_parameter("route_duration_sec").value)

        self.route_start_time: Optional[float] = None
        self.route_origin: Optional[tuple[float, float, float]] = None
        self.route_heading: Optional[float] = None
        self.publisher = self.create_publisher(PoseStamped, RIVAL_STATE_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.timer = self.create_timer(self.publish_period_sec, self._publish_rival)

        self.get_logger().info(
            f"scripted rival publisher listening on {OWNSHIP_STATE_TOPIC}; publishing moving rival {self.rival_id} on {RIVAL_STATE_TOPIC}"
        )

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        if self.route_start_time is not None:
            return

        own = msg.pose.position
        own_heading = yaw_from_quaternion(msg.pose.orientation.z, msg.pose.orientation.w)
        start_heading = own_heading + math.radians(self.bearing_offset_deg)
        route_heading = own_heading + math.radians(self.rival_course_offset_deg)

        start_x = own.x + self.distance_m * math.cos(start_heading)
        start_y = own.y + self.distance_m * math.sin(start_heading)
        start_z = own.z + self.altitude_offset_m

        self.route_origin = (start_x, start_y, start_z)
        self.route_heading = route_heading
        self.route_start_time = time.monotonic()

        self.get_logger().info(
            f"initialized scripted rival {self.rival_id} at ({start_x:.1f}, {start_y:.1f}, {start_z:.1f}) "
            f"with speed={self.rival_speed_mps:.1f} m/s course_offset={self.rival_course_offset_deg:.1f} deg"
        )

    def _publish_rival(self) -> None:
        if self.route_start_time is None or self.route_origin is None or self.route_heading is None:
            return

        elapsed = min(time.monotonic() - self.route_start_time, self.route_duration_sec)
        dx = self.rival_speed_mps * elapsed * math.cos(self.route_heading)
        dy = self.rival_speed_mps * elapsed * math.sin(self.route_heading)
        z_orient, w_orient = quaternion_from_yaw(self.route_heading)

        rival = PoseStamped()
        rival.header.stamp = self.get_clock().now().to_msg()
        rival.header.frame_id = self.rival_id
        rival.pose.position.x = self.route_origin[0] + dx
        rival.pose.position.y = self.route_origin[1] + dy
        rival.pose.position.z = self.route_origin[2]
        rival.pose.orientation.x = 0.0
        rival.pose.orientation.y = 0.0
        rival.pose.orientation.z = z_orient
        rival.pose.orientation.w = w_orient
        self.publisher.publish(rival)


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
