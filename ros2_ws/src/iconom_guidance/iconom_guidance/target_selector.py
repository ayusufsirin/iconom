#!/usr/bin/env python3
import math
from typing import Dict, Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node


OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
RIVAL_STATE_TOPIC = "/competition/rival/state"
SELECTED_TARGET_TOPIC = "/guidance/selected_target"


class TargetSelector(Node):
    def __init__(self):
        super().__init__("target_selector")

        self.declare_parameter("publish_period_sec", 1.0)
        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)

        self.ownship_state: Optional[PoseStamped] = None
        self.rival_states: Dict[str, PoseStamped] = {}
        self.current_target_id: Optional[str] = None
        self.current_target_msg: Optional[PoseStamped] = None

        self.selected_target_pub = self.create_publisher(PoseStamped, SELECTED_TARGET_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.create_subscription(PoseStamped, RIVAL_STATE_TOPIC, self._handle_rival_state, 10)
        self.publish_timer = self.create_timer(self.publish_period_sec, self._publish_selection)

        self.get_logger().info(
            f"target selector listening on {OWNSHIP_STATE_TOPIC} and {RIVAL_STATE_TOPIC}, publishing {SELECTED_TARGET_TOPIC}"
        )

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        self.ownship_state = msg
        self._select_target()

    def _handle_rival_state(self, msg: PoseStamped) -> None:
        rival_id = msg.header.frame_id or "unknown_rival"
        self.rival_states[rival_id] = msg
        self._select_target()

    def _distance_to_ownship(self, rival_msg: PoseStamped) -> float:
        assert self.ownship_state is not None
        dx = rival_msg.pose.position.x - self.ownship_state.pose.position.x
        dy = rival_msg.pose.position.y - self.ownship_state.pose.position.y
        dz = rival_msg.pose.position.z - self.ownship_state.pose.position.z
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def _select_target(self) -> None:
        if self.ownship_state is None or not self.rival_states:
            return

        selected_id, selected_msg = min(
            self.rival_states.items(),
            key=lambda item: (self._distance_to_ownship(item[1]), item[0]),
        )

        self.current_target_id = selected_id
        self.current_target_msg = selected_msg
        self.get_logger().info(
            f"selected target {selected_id} at distance {self._distance_to_ownship(selected_msg):.2f}"
        )

    def _publish_selection(self) -> None:
        if self.current_target_msg is None or self.current_target_id is None:
            return

        msg = PoseStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.current_target_id
        msg.pose = self.current_target_msg.pose
        self.selected_target_pub.publish(msg)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = TargetSelector()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
