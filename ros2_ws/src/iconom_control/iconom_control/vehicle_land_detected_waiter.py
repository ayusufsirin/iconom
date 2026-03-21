#!/usr/bin/env python3
import os
import sys
import time

import rclpy
from px4_msgs.msg import VehicleLandDetected
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class VehicleLandDetectedWaiter(Node):
    def __init__(self) -> None:
        super().__init__("iconom_vehicle_land_detected_waiter")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.topic = os.environ.get(
            "PX4_LAND_DETECTED_TOPIC",
            f"/{namespace}/fmu/out/vehicle_land_detected",
        )
        self.timeout_sec = float(
            os.environ.get("PX4_LAND_DETECTED_TIMEOUT_SEC", "90.0")
        )
        self.expected_landed = self._parse_optional_bool(
            os.environ.get("PX4_EXPECTED_LANDED")
        )
        self.expected_ground_contact = self._parse_optional_bool(
            os.environ.get("PX4_EXPECTED_GROUND_CONTACT")
        )
        self.expected_maybe_landed = self._parse_optional_bool(
            os.environ.get("PX4_EXPECTED_MAYBE_LANDED")
        )
        self.start_time = time.monotonic()
        self.failed = False
        self.success = False
        self.last_summary = "no vehicle_land_detected received"

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.subscription = self.create_subscription(
            VehicleLandDetected,
            self.topic,
            self._handle_message,
            qos_profile,
        )
        self.timer = self.create_timer(0.5, self._check_timeout)

        self.get_logger().info(
            f"waiting on {self.topic} "
            f"for landed={self.expected_landed!r} "
            f"ground_contact={self.expected_ground_contact!r} "
            f"maybe_landed={self.expected_maybe_landed!r} "
            f"with timeout {self.timeout_sec:.1f}s"
        )

    def _parse_optional_bool(self, value: str | None) -> bool | None:
        if value is None or value == "":
            return None
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
        raise ValueError("landing expectations must be boolean strings")

    def _handle_message(self, message: VehicleLandDetected) -> None:
        self.last_summary = (
            f"landed={message.landed} "
            f"ground_contact={message.ground_contact} "
            f"maybe_landed={message.maybe_landed} "
            f"in_descend={message.in_descend}"
        )

        landed_ok = (
            self.expected_landed is None or bool(message.landed) == self.expected_landed
        )
        ground_contact_ok = (
            self.expected_ground_contact is None
            or bool(message.ground_contact) == self.expected_ground_contact
        )
        maybe_landed_ok = (
            self.expected_maybe_landed is None
            or bool(message.maybe_landed) == self.expected_maybe_landed
        )

        if landed_ok and ground_contact_ok and maybe_landed_ok:
            self.success = True
            self.get_logger().info(f"matched land detection {self.last_summary}")

    def _check_timeout(self) -> None:
        if self.success or self.failed:
            return

        if time.monotonic() - self.start_time >= self.timeout_sec:
            self.failed = True
            self.get_logger().error(
                f"timed out waiting for land detection match on {self.topic}; "
                f"last seen: {self.last_summary}"
            )


def main() -> int:
    rclpy.init()
    try:
        node = VehicleLandDetectedWaiter()
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        rclpy.shutdown()
        return 2

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
