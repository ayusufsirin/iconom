#!/usr/bin/env python3
import os
import sys
import time

import rclpy
from px4_msgs.msg import VehicleStatus
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class VehicleStatusWaiter(Node):
    def __init__(self) -> None:
        super().__init__("iconom_vehicle_status_waiter")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.topic = os.environ.get(
            "PX4_VEHICLE_STATUS_TOPIC",
            f"/{namespace}/fmu/out/vehicle_status_v1",
        )
        self.timeout_sec = float(os.environ.get("PX4_STATUS_TIMEOUT_SEC", "20"))
        self.expected_arming_state = self._parse_optional_int(
            os.environ.get("PX4_EXPECTED_ARMING_STATE")
        )
        self.expected_nav_state = self._parse_optional_int(
            os.environ.get("PX4_EXPECTED_NAV_STATE")
        )
        self.expected_pre_flight_checks_pass = self._parse_optional_bool(
            os.environ.get("PX4_EXPECTED_PREFLIGHT_CHECKS_PASS")
        )
        self.start_time = time.monotonic()
        self.failed = False
        self.success = False
        self.last_summary = "no vehicle_status received"

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.subscription = self.create_subscription(
            VehicleStatus,
            self.topic,
            self._handle_status,
            qos_profile,
        )
        self.timer = self.create_timer(0.5, self._check_timeout)

        self.get_logger().info(
            f"waiting on {self.topic} "
            f"for arming_state={self.expected_arming_state!r} "
            f"nav_state={self.expected_nav_state!r} "
            f"pre_flight_checks_pass={self.expected_pre_flight_checks_pass!r} "
            f"with timeout {self.timeout_sec:.1f}s"
        )

    def _parse_optional_int(self, value: str | None) -> int | None:
        if value is None or value == "":
            return None
        return int(value)

    def _parse_optional_bool(self, value: str | None) -> bool | None:
        if value is None or value == "":
            return None
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
        raise ValueError(
            "PX4_EXPECTED_PREFLIGHT_CHECKS_PASS must be a boolean string"
        )

    def _handle_status(self, message: VehicleStatus) -> None:
        self.last_summary = (
            f"arming_state={message.arming_state} "
            f"nav_state={message.nav_state} "
            f"user_intention={message.nav_state_user_intention} "
            f"pre_flight_checks_pass={message.pre_flight_checks_pass}"
        )

        arming_ok = (
            self.expected_arming_state is None
            or message.arming_state == self.expected_arming_state
        )
        nav_ok = (
            self.expected_nav_state is None
            or message.nav_state == self.expected_nav_state
        )
        preflight_ok = (
            self.expected_pre_flight_checks_pass is None
            or bool(message.pre_flight_checks_pass)
            == self.expected_pre_flight_checks_pass
        )

        if arming_ok and nav_ok and preflight_ok:
            self.success = True
            self.get_logger().info(f"matched vehicle status {self.last_summary}")

    def _check_timeout(self) -> None:
        if self.success or self.failed:
            return

        if time.monotonic() - self.start_time >= self.timeout_sec:
            self.failed = True
            self.get_logger().error(
                f"timed out waiting for vehicle status match on {self.topic}; "
                f"last seen: {self.last_summary}"
            )


def main() -> int:
    rclpy.init()
    node = VehicleStatusWaiter()

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
