#!/usr/bin/env python3
import math
import os
import sys
import time

import rclpy
from px4_msgs.msg import OffboardControlMode, TrajectorySetpoint, VehicleLocalPosition
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class OffboardHoldPublisher(Node):
    def __init__(self) -> None:
        super().__init__("iconom_offboard_hold_publisher")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.offboard_topic = os.environ.get(
            "PX4_OFFBOARD_CONTROL_MODE_TOPIC",
            f"/{namespace}/fmu/in/offboard_control_mode",
        )
        self.trajectory_topic = os.environ.get(
            "PX4_TRAJECTORY_SETPOINT_TOPIC",
            f"/{namespace}/fmu/in/trajectory_setpoint",
        )
        self.local_position_topic = os.environ.get(
            "PX4_LOCAL_POSITION_TOPIC",
            f"/{namespace}/fmu/out/vehicle_local_position",
        )
        self.publish_rate_hz = float(os.environ.get("PX4_OFFBOARD_RATE_HZ", "10.0"))
        self.ready_timeout_sec = float(
            os.environ.get("PX4_OFFBOARD_READY_TIMEOUT_SEC", "20.0")
        )
        self.run_duration_sec = float(
            os.environ.get("PX4_OFFBOARD_RUN_DURATION_SEC", "30.0")
        )

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
        self.trajectory_publisher = self.create_publisher(
            TrajectorySetpoint,
            self.trajectory_topic,
            qos_profile,
        )
        self.local_position_subscription = self.create_subscription(
            VehicleLocalPosition,
            self.local_position_topic,
            self._handle_local_position,
            qos_profile,
        )

        self.start_time = time.monotonic()
        self.setpoint_initialized = False
        self.last_local_position_summary = "no vehicle_local_position received"
        self.setpoint_position = [math.nan, math.nan, math.nan]
        self.setpoint_yaw = math.nan
        self.publish_count = 0
        self.finished = False
        self.failed = False
        self.failure_reason = ""

        publish_period_sec = 1.0 / self.publish_rate_hz
        self.timer = self.create_timer(publish_period_sec, self._publish_if_ready)

        self.get_logger().info(
            f"waiting on {self.local_position_topic} to seed offboard hold setpoints; "
            f"publishing to {self.offboard_topic} and {self.trajectory_topic} at "
            f"{self.publish_rate_hz:.1f}Hz for {self.run_duration_sec:.1f}s"
        )

    def _handle_local_position(self, message: VehicleLocalPosition) -> None:
        self.last_local_position_summary = (
            f"xy_valid={message.xy_valid} z_valid={message.z_valid} "
            f"x={message.x:.2f} y={message.y:.2f} z={message.z:.2f} "
            f"heading={message.heading:.2f}"
        )

        if not message.xy_valid or not message.z_valid:
            return

        if not self.setpoint_initialized:
            self.setpoint_position = [float(message.x), float(message.y), float(message.z)]
            self.setpoint_yaw = float(message.heading)
            self.setpoint_initialized = True
            self.get_logger().info(
                "seeded offboard hold setpoint from local position "
                f"{self.last_local_position_summary}"
            )

    def _publish_if_ready(self) -> None:
        if self.finished or self.failed:
            return

        elapsed_sec = time.monotonic() - self.start_time
        if not self.setpoint_initialized:
            if elapsed_sec >= self.ready_timeout_sec:
                self.failed = True
                self.failure_reason = (
                    "timed out waiting for valid vehicle_local_position; "
                    f"last seen: {self.last_local_position_summary}"
                )
                self.get_logger().error(self.failure_reason)
            return

        self.offboard_publisher.publish(self._build_offboard_mode())
        self.trajectory_publisher.publish(self._build_trajectory_setpoint())
        self.publish_count += 1

        if elapsed_sec >= self.run_duration_sec:
            self.finished = True
            self.get_logger().info(
                f"published {self.publish_count} offboard hold setpoints before exiting"
            )

    def _build_offboard_mode(self) -> OffboardControlMode:
        message = OffboardControlMode()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.position = True
        message.velocity = False
        message.acceleration = False
        message.attitude = False
        message.body_rate = False
        message.thrust_and_torque = False
        message.direct_actuator = False
        return message

    def _build_trajectory_setpoint(self) -> TrajectorySetpoint:
        message = TrajectorySetpoint()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.position = self.setpoint_position
        message.velocity = [math.nan, math.nan, math.nan]
        message.acceleration = [math.nan, math.nan, math.nan]
        message.jerk = [math.nan, math.nan, math.nan]
        message.yaw = self.setpoint_yaw
        message.yawspeed = math.nan
        return message


def main() -> int:
    rclpy.init()
    node = OffboardHoldPublisher()

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
