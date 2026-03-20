#!/usr/bin/env python3
import os
import sys
import time

import rclpy
from px4_msgs.msg import OffboardControlMode, VehicleRatesSetpoint
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class OffboardRateThrustPublisher(Node):
    def __init__(self) -> None:
        super().__init__("iconom_offboard_rate_thrust_publisher")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.offboard_topic = os.environ.get(
            "PX4_OFFBOARD_CONTROL_MODE_TOPIC",
            f"/{namespace}/fmu/in/offboard_control_mode",
        )
        self.rates_topic = os.environ.get(
            "PX4_VEHICLE_RATES_SETPOINT_TOPIC",
            f"/{namespace}/fmu/in/vehicle_rates_setpoint",
        )
        self.publish_rate_hz = float(os.environ.get("PX4_OFFBOARD_RATE_HZ", "20.0"))
        self.run_duration_sec = float(
            os.environ.get("PX4_OFFBOARD_RUN_DURATION_SEC", "20.0")
        )
        self.roll_rate = float(os.environ.get("PX4_OFFBOARD_ROLL_RATE", "0.0"))
        self.pitch_rate = float(os.environ.get("PX4_OFFBOARD_PITCH_RATE", "0.0"))
        self.yaw_rate = float(os.environ.get("PX4_OFFBOARD_YAW_RATE", "0.0"))
        self.thrust_x = float(os.environ.get("PX4_OFFBOARD_THRUST_X", "0.7"))

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.offboard_publisher = self.create_publisher(
            OffboardControlMode,
            self.offboard_topic,
            qos_profile,
        )
        self.rates_publisher = self.create_publisher(
            VehicleRatesSetpoint,
            self.rates_topic,
            qos_profile,
        )

        self.start_time = time.monotonic()
        self.publish_count = 0
        self.finished = False
        self.failed = False

        publish_period_sec = 1.0 / self.publish_rate_hz
        self.timer = self.create_timer(publish_period_sec, self._publish_setpoints)

        self.get_logger().info(
            f"publishing body-rate offboard control to {self.offboard_topic} and "
            f"{self.rates_topic} at {self.publish_rate_hz:.1f}Hz for "
            f"{self.run_duration_sec:.1f}s with thrust_x={self.thrust_x:.2f}"
        )

    def _publish_setpoints(self) -> None:
        if self.finished or self.failed:
            return

        elapsed_sec = time.monotonic() - self.start_time
        self.offboard_publisher.publish(self._build_offboard_mode())
        self.rates_publisher.publish(self._build_rates_setpoint())
        self.publish_count += 1

        if elapsed_sec >= self.run_duration_sec:
            self.finished = True
            self.get_logger().info(
                f"published {self.publish_count} body-rate offboard setpoints before exiting"
            )

    def _build_offboard_mode(self) -> OffboardControlMode:
        message = OffboardControlMode()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.position = False
        message.velocity = False
        message.acceleration = False
        message.attitude = False
        message.body_rate = True
        message.thrust_and_torque = False
        message.direct_actuator = False
        return message

    def _build_rates_setpoint(self) -> VehicleRatesSetpoint:
        message = VehicleRatesSetpoint()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.roll = self.roll_rate
        message.pitch = self.pitch_rate
        message.yaw = self.yaw_rate
        message.thrust_body = [self.thrust_x, 0.0, 0.0]
        message.reset_integral = False
        return message


def main() -> int:
    rclpy.init()
    node = OffboardRateThrustPublisher()

    try:
        while rclpy.ok() and not node.finished and not node.failed:
            rclpy.spin_once(node, timeout_sec=0.5)
    finally:
        exit_code = 0 if node.finished and not node.failed else 1
        node.destroy_node()
        rclpy.shutdown()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
