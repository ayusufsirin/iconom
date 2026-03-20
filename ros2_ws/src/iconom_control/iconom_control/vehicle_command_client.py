#!/usr/bin/env python3
import os
import sys
import time

import rclpy
from px4_msgs.msg import VehicleCommand, VehicleCommandAck, VehicleStatus
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class VehicleCommandClient(Node):
    def __init__(self) -> None:
        super().__init__("iconom_vehicle_command_client")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.command_topic = os.environ.get(
            "PX4_COMMAND_TOPIC",
            f"/{namespace}/fmu/in/vehicle_command",
        )
        self.ack_topic = os.environ.get(
            "PX4_COMMAND_ACK_TOPIC",
            f"/{namespace}/fmu/out/vehicle_command_ack",
        )
        self.timeout_sec = float(os.environ.get("PX4_COMMAND_TIMEOUT_SEC", "15"))
        self.republish_interval_sec = float(
            os.environ.get("PX4_COMMAND_REPUBLISH_INTERVAL_SEC", "1.0")
        )
        self.command_name = os.environ.get("PX4_COMMAND_NAME", "disarm").strip().lower()
        self.target_system = int(os.environ.get("PX4_TARGET_SYSTEM", "1"))
        self.target_component = int(os.environ.get("PX4_TARGET_COMPONENT", "1"))
        self.source_system = int(os.environ.get("PX4_SOURCE_SYSTEM", "1"))
        self.source_component = int(os.environ.get("PX4_SOURCE_COMPONENT", "1"))
        self.command_id, self.param1 = self._resolve_command(self.command_name)
        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.publisher = self.create_publisher(
            VehicleCommand,
            self.command_topic,
            qos_profile,
        )
        self.subscription = self.create_subscription(
            VehicleCommandAck,
            self.ack_topic,
            self._handle_ack,
            qos_profile,
        )
        self.timer = self.create_timer(self.republish_interval_sec, self._republish_if_needed)
        self.deadline = time.monotonic() + self.timeout_sec
        self.attempt_count = 0
        self.accepted = False
        self.failed = False
        self.failure_reason = ""
        self.result_label = ""

        self.get_logger().info(
            f"sending {self.command_name} command {self.command_id} on {self.command_topic} "
            f"and waiting for ack on {self.ack_topic} with timeout {self.timeout_sec:.1f}s"
        )
        self._publish_command()

    def _resolve_command(self, command_name: str) -> tuple[int, float]:
        if command_name == "disarm":
            return (
                VehicleCommand.VEHICLE_CMD_COMPONENT_ARM_DISARM,
                float(VehicleCommand.ARMING_ACTION_DISARM),
            )
        if command_name == "arm":
            return (
                VehicleCommand.VEHICLE_CMD_COMPONENT_ARM_DISARM,
                float(VehicleCommand.ARMING_ACTION_ARM),
            )
        if command_name == "mode_stabilized":
            return (
                VehicleCommand.VEHICLE_CMD_SET_NAV_STATE,
                float(VehicleStatus.NAVIGATION_STATE_STAB),
            )
        if command_name == "mode_loiter":
            return (
                VehicleCommand.VEHICLE_CMD_SET_NAV_STATE,
                float(VehicleStatus.NAVIGATION_STATE_AUTO_LOITER),
            )
        raise ValueError(f"unsupported PX4_COMMAND_NAME={command_name!r}")

    def _result_label(self, result: int) -> str:
        labels = {
            VehicleCommandAck.VEHICLE_CMD_RESULT_ACCEPTED: "accepted",
            VehicleCommandAck.VEHICLE_CMD_RESULT_TEMPORARILY_REJECTED: "temporarily_rejected",
            VehicleCommandAck.VEHICLE_CMD_RESULT_DENIED: "denied",
            VehicleCommandAck.VEHICLE_CMD_RESULT_UNSUPPORTED: "unsupported",
            VehicleCommandAck.VEHICLE_CMD_RESULT_FAILED: "failed",
            VehicleCommandAck.VEHICLE_CMD_RESULT_IN_PROGRESS: "in_progress",
            VehicleCommandAck.VEHICLE_CMD_RESULT_CANCELLED: "cancelled",
        }
        return labels.get(result, f"unknown_{result}")

    def _build_command(self) -> VehicleCommand:
        message = VehicleCommand()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.command = self.command_id
        message.param1 = self.param1
        message.target_system = self.target_system
        message.target_component = self.target_component
        message.source_system = self.source_system
        message.source_component = self.source_component
        message.confirmation = 0
        message.from_external = True
        return message

    def _publish_command(self) -> None:
        if self.accepted or self.failed:
            return
        self.attempt_count += 1
        self.publisher.publish(self._build_command())
        self.get_logger().info(
            f"published {self.command_name} attempt {self.attempt_count}"
        )

    def _republish_if_needed(self) -> None:
        if self.accepted or self.failed:
            return

        if time.monotonic() >= self.deadline:
            self.failed = True
            self.failure_reason = (
                f"timed out waiting for ack for command {self.command_id} "
                f"on {self.ack_topic}"
            )
            self.get_logger().error(self.failure_reason)
            return

        self._publish_command()

    def _handle_ack(self, message: VehicleCommandAck) -> None:
        if message.command != self.command_id:
            return

        self.result_label = self._result_label(message.result)
        self.get_logger().info(
            f"received ack for command {message.command} result={self.result_label} "
            f"target_system={message.target_system}"
        )

        if message.result == VehicleCommandAck.VEHICLE_CMD_RESULT_ACCEPTED:
            self.accepted = True
            return

        if message.result == VehicleCommandAck.VEHICLE_CMD_RESULT_IN_PROGRESS:
            return

        self.failed = True
        self.failure_reason = (
            f"command {message.command} was acknowledged with result={self.result_label} "
            f"result_param1={message.result_param1} result_param2={message.result_param2}"
        )
        self.get_logger().error(self.failure_reason)


def main() -> int:
    rclpy.init()
    try:
        node = VehicleCommandClient()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        rclpy.shutdown()
        return 2

    try:
        while rclpy.ok() and not node.accepted and not node.failed:
            rclpy.spin_once(node, timeout_sec=0.5)
    finally:
        exit_code = 0 if node.accepted and not node.failed else 1
        node.destroy_node()
        rclpy.shutdown()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
