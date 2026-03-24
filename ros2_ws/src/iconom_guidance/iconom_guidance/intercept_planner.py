#!/usr/bin/env python3
import math
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node


OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
SELECTED_TARGET_TOPIC = "/guidance/selected_target"
PREDICTED_RIVAL_TOPIC = "/competition/prediction/rival_position"
INTERCEPT_TARGET_TOPIC = "/guidance/intercept_target"


class InterceptPlanner(Node):
    def __init__(self) -> None:
        super().__init__("intercept_planner")

        self.declare_parameter("publish_period_sec", 1.0)
        self.declare_parameter("max_intercept_distance", 25.0)

        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self.max_intercept_distance = float(self.get_parameter("max_intercept_distance").value)

        self.ownship_state: Optional[PoseStamped] = None
        self.selected_target: Optional[PoseStamped] = None
        self.predicted_target: Optional[PoseStamped] = None
        self.current_intercept_target: Optional[PoseStamped] = None

        self.intercept_target_pub = self.create_publisher(PoseStamped, INTERCEPT_TARGET_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(PoseStamped, PREDICTED_RIVAL_TOPIC, self._handle_predicted_target, 10)
        self.publish_timer = self.create_timer(self.publish_period_sec, self._publish_intercept_target)

        self.get_logger().info(
            f"intercept planner listening on {OWNSHIP_STATE_TOPIC}, {SELECTED_TARGET_TOPIC}, and {PREDICTED_RIVAL_TOPIC}; publishing {INTERCEPT_TARGET_TOPIC}"
        )

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        self.ownship_state = msg
        self._plan_intercept()

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        self.selected_target = msg
        self._plan_intercept()

    def _handle_predicted_target(self, msg: PoseStamped) -> None:
        self.predicted_target = msg
        self._plan_intercept()

    def _choose_target_pose(self) -> Optional[PoseStamped]:
        if self.selected_target is None:
            return None
        if self.predicted_target is not None and self.predicted_target.header.frame_id == self.selected_target.header.frame_id:
            return self.predicted_target
        return self.selected_target

    def _plan_intercept(self) -> None:
        if self.ownship_state is None:
            return

        target_pose = self._choose_target_pose()
        if target_pose is None:
            return

        own = self.ownship_state.pose.position
        tgt = target_pose.pose.position

        dx = tgt.x - own.x
        dy = tgt.y - own.y
        dz = tgt.z - own.z
        distance = math.sqrt(dx * dx + dy * dy + dz * dz)

        intercept = PoseStamped()
        intercept.header.stamp = self.get_clock().now().to_msg()
        intercept.header.frame_id = target_pose.header.frame_id
        intercept.pose.orientation = target_pose.pose.orientation

        if distance <= self.max_intercept_distance or distance == 0.0:
            intercept.pose.position.x = tgt.x
            intercept.pose.position.y = tgt.y
            intercept.pose.position.z = tgt.z
        else:
            scale = self.max_intercept_distance / distance
            intercept.pose.position.x = own.x + dx * scale
            intercept.pose.position.y = own.y + dy * scale
            intercept.pose.position.z = own.z + dz * scale

        self.current_intercept_target = intercept
        self.get_logger().info(
            f"planned intercept target for {intercept.header.frame_id} at ({intercept.pose.position.x:.2f}, {intercept.pose.position.y:.2f}, {intercept.pose.position.z:.2f})"
        )

    def _publish_intercept_target(self) -> None:
        if self.current_intercept_target is None:
            return
        self.current_intercept_target.header.stamp = self.get_clock().now().to_msg()
        self.intercept_target_pub.publish(self.current_intercept_target)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = InterceptPlanner()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
