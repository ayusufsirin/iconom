#!/usr/bin/env python3
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from std_msgs.msg import String

from .phase6_time import now_sec


SELECTED_TARGET_TOPIC = "/guidance/selected_target"
INTERCEPT_TARGET_TOPIC = "/guidance/intercept_target"
PURSUIT_STATE_TOPIC = "/guidance/pursuit_state"
PURSUIT_GOAL_TOPIC = "/guidance/pursuit_goal"

STATE_IDLE = "idle"
STATE_SEARCH = "search"
STATE_PURSUE = "pursue"
STATE_REACQUIRE = "reacquire"


class PursuitStateMachine(Node):
    def __init__(self) -> None:
        super().__init__("pursuit_state_machine")

        self.declare_parameter("publish_period_sec", 1.0)
        self.declare_parameter("selected_timeout_sec", 4.0)
        self.declare_parameter("intercept_timeout_sec", 2.5)

        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self.selected_timeout_sec = float(self.get_parameter("selected_timeout_sec").value)
        self.intercept_timeout_sec = float(self.get_parameter("intercept_timeout_sec").value)

        self.selected_target: Optional[PoseStamped] = None
        self.selected_target_at: Optional[float] = None
        self.intercept_target: Optional[PoseStamped] = None
        self.intercept_target_at: Optional[float] = None
        self.state = STATE_IDLE
        self.state_pub = self.create_publisher(String, PURSUIT_STATE_TOPIC, 10)
        self.goal_pub = self.create_publisher(PoseStamped, PURSUIT_GOAL_TOPIC, 10)

        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(PoseStamped, INTERCEPT_TARGET_TOPIC, self._handle_intercept_target, 10)
        self.publish_timer = self.create_timer(self.publish_period_sec, self._tick)

        self.get_logger().info(
            f"pursuit state machine listening on {SELECTED_TARGET_TOPIC} and {INTERCEPT_TARGET_TOPIC}; publishing {PURSUIT_STATE_TOPIC} and {PURSUIT_GOAL_TOPIC}"
        )

    def _now(self) -> float:
        return now_sec(self)

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        self.selected_target = msg
        self.selected_target_at = self._now()
        self._evaluate_state()

    def _handle_intercept_target(self, msg: PoseStamped) -> None:
        self.intercept_target = msg
        self.intercept_target_at = self._now()
        self._evaluate_state()

    def _is_selected_fresh(self) -> bool:
        return self.selected_target is not None and self.selected_target_at is not None and (self._now() - self.selected_target_at) <= self.selected_timeout_sec

    def _is_intercept_fresh(self) -> bool:
        return self.intercept_target is not None and self.intercept_target_at is not None and (self._now() - self.intercept_target_at) <= self.intercept_timeout_sec

    def _matching_target_ids(self) -> bool:
        return (
            self.selected_target is not None
            and self.intercept_target is not None
            and self.selected_target.header.frame_id == self.intercept_target.header.frame_id
        )

    def _set_state(self, new_state: str) -> None:
        if new_state != self.state:
            self.state = new_state
            self.get_logger().info(f"state -> {new_state}")

    def _evaluate_state(self) -> None:
        selected_fresh = self._is_selected_fresh()
        intercept_fresh = self._is_intercept_fresh()
        matching = self._matching_target_ids()

        if not selected_fresh:
            self._set_state(STATE_IDLE)
            return

        if intercept_fresh and matching:
            self._set_state(STATE_PURSUE)
            return

        if self.state == STATE_PURSUE and (not intercept_fresh or not matching):
            self._set_state(STATE_REACQUIRE)
            return

        if self.state == STATE_REACQUIRE and selected_fresh:
            self._set_state(STATE_REACQUIRE)
            return

        self._set_state(STATE_SEARCH)

    def _publish_state(self) -> None:
        msg = String()
        msg.data = self.state
        self.state_pub.publish(msg)

    def _publish_goal(self) -> None:
        if self.state != STATE_PURSUE or self.intercept_target is None or not self._matching_target_ids() or not self._is_intercept_fresh():
            return
        goal = PoseStamped()
        goal.header.stamp = self.get_clock().now().to_msg()
        goal.header.frame_id = self.intercept_target.header.frame_id
        goal.pose = self.intercept_target.pose
        self.goal_pub.publish(goal)

    def _tick(self) -> None:
        self._evaluate_state()
        self._publish_state()
        self._publish_goal()


def main(args=None) -> None:
    rclpy.init(args=args)
    node = PursuitStateMachine()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
