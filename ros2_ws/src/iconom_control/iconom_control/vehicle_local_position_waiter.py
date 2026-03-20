#!/usr/bin/env python3
import os
import math
import sys
import time

import rclpy
from px4_msgs.msg import VehicleLocalPosition
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class VehicleLocalPositionWaiter(Node):
    def __init__(self) -> None:
        super().__init__("iconom_vehicle_local_position_waiter")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.topic = os.environ.get(
            "PX4_LOCAL_POSITION_TOPIC",
            f"/{namespace}/fmu/out/vehicle_local_position",
        )
        self.timeout_sec = float(
            os.environ.get("PX4_LOCAL_POSITION_TIMEOUT_SEC", "30.0")
        )
        self.min_delta_x = self._parse_optional_float(
            os.environ.get("PX4_MIN_DELTA_X")
        )
        self.max_delta_x = self._parse_optional_float(
            os.environ.get("PX4_MAX_DELTA_X")
        )
        self.min_delta_y = self._parse_optional_float(
            os.environ.get("PX4_MIN_DELTA_Y")
        )
        self.max_delta_y = self._parse_optional_float(
            os.environ.get("PX4_MAX_DELTA_Y")
        )
        self.min_delta_z = self._parse_optional_float(
            os.environ.get("PX4_MIN_DELTA_Z")
        )
        self.max_delta_z = self._parse_optional_float(
            os.environ.get("PX4_MAX_DELTA_Z")
        )
        self.min_delta_xy_norm = self._parse_optional_float(
            os.environ.get("PX4_MIN_DELTA_XY_NORM")
        )
        self.start_time = time.monotonic()
        self.failed = False
        self.success = False
        self.last_summary = "no vehicle_local_position received"
        self.initial_position: tuple[float, float, float] | None = None

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.subscription = self.create_subscription(
            VehicleLocalPosition,
            self.topic,
            self._handle_local_position,
            qos_profile,
        )
        self.timer = self.create_timer(0.5, self._check_timeout)

        self.get_logger().info(
            f"waiting on {self.topic} with timeout {self.timeout_sec:.1f}s "
            f"for deltas x=[{self.min_delta_x!r}, {self.max_delta_x!r}] "
            f"y=[{self.min_delta_y!r}, {self.max_delta_y!r}] "
            f"z=[{self.min_delta_z!r}, {self.max_delta_z!r}] "
            f"xy_norm>={self.min_delta_xy_norm!r}"
        )

    def _parse_optional_float(self, value: str | None) -> float | None:
        if value is None or value == "":
            return None
        return float(value)

    def _within_bounds(
        self, value: float, minimum: float | None, maximum: float | None
    ) -> bool:
        if minimum is not None and value < minimum:
            return False
        if maximum is not None and value > maximum:
            return False
        return True

    def _handle_local_position(self, message: VehicleLocalPosition) -> None:
        if not message.xy_valid or not message.z_valid:
            self.last_summary = (
                f"xy_valid={message.xy_valid} z_valid={message.z_valid}"
            )
            return

        if self.initial_position is None:
            self.initial_position = (float(message.x), float(message.y), float(message.z))
            self.get_logger().info(
                "seeded local position baseline "
                f"x={self.initial_position[0]:.2f} "
                f"y={self.initial_position[1]:.2f} "
                f"z={self.initial_position[2]:.2f}"
            )
            return

        delta_x = float(message.x) - self.initial_position[0]
        delta_y = float(message.y) - self.initial_position[1]
        delta_z = float(message.z) - self.initial_position[2]
        delta_xy_norm = math.hypot(delta_x, delta_y)
        self.last_summary = (
            f"x={message.x:.2f} y={message.y:.2f} z={message.z:.2f} "
            f"delta_x={delta_x:.2f} delta_y={delta_y:.2f} "
            f"delta_z={delta_z:.2f} delta_xy_norm={delta_xy_norm:.2f}"
        )

        if (
            self._within_bounds(delta_x, self.min_delta_x, self.max_delta_x)
            and self._within_bounds(delta_y, self.min_delta_y, self.max_delta_y)
            and self._within_bounds(delta_z, self.min_delta_z, self.max_delta_z)
            and (
                self.min_delta_xy_norm is None
                or delta_xy_norm >= self.min_delta_xy_norm
            )
        ):
            self.success = True
            self.get_logger().info(f"matched local position {self.last_summary}")

    def _check_timeout(self) -> None:
        if self.success or self.failed:
            return

        if time.monotonic() - self.start_time >= self.timeout_sec:
            self.failed = True
            self.get_logger().error(
                f"timed out waiting for vehicle local position match on {self.topic}; "
                f"last seen: {self.last_summary}"
            )


def main() -> int:
    rclpy.init()
    node = VehicleLocalPositionWaiter()

    try:
        while rclpy.ok() and not node.success and not node.failed:
            rclpy.spin_once(node, timeout_sec=0.5)
    finally:
        exit_code = 0 if node.success and not node.failed else 1
        node.destroy_node()
        rclpy.shutdown()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
