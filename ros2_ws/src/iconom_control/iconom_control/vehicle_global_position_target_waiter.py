#!/usr/bin/env python3
import math
import os
import sys
import time

import rclpy
from px4_msgs.msg import VehicleGlobalPosition
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class VehicleGlobalPositionTargetWaiter(Node):
    def __init__(self) -> None:
        super().__init__("iconom_vehicle_global_position_target_waiter")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.topic = os.environ.get(
            "PX4_GLOBAL_POSITION_TOPIC",
            f"/{namespace}/fmu/out/vehicle_global_position",
        )
        self.timeout_sec = float(
            os.environ.get("PX4_GLOBAL_POSITION_TIMEOUT_SEC", "60.0")
        )
        self.target_lat_deg = float(os.environ["PX4_TARGET_LAT_DEG"])
        self.target_lon_deg = float(os.environ["PX4_TARGET_LON_DEG"])
        self.target_alt_m = self._parse_optional_float(
            os.environ.get("PX4_TARGET_ALT_M")
        )
        self.horizontal_tolerance_m = float(
            os.environ.get("PX4_TARGET_HORIZONTAL_TOLERANCE_M", "80.0")
        )
        self.altitude_tolerance_m = float(
            os.environ.get("PX4_TARGET_ALT_TOLERANCE_M", "30.0")
        )
        self.start_time = time.monotonic()
        self.failed = False
        self.success = False
        self.last_summary = "no vehicle_global_position received"

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.subscription = self.create_subscription(
            VehicleGlobalPosition,
            self.topic,
            self._handle_global_position,
            qos_profile,
        )
        self.timer = self.create_timer(0.5, self._check_timeout)

        self.get_logger().info(
            f"waiting on {self.topic} with timeout {self.timeout_sec:.1f}s "
            f"for lat={self.target_lat_deg:.7f} lon={self.target_lon_deg:.7f} "
            f"alt={self.target_alt_m!r} horizontal_tolerance={self.horizontal_tolerance_m:.1f}m "
            f"altitude_tolerance={self.altitude_tolerance_m:.1f}m"
        )

    def _parse_optional_float(self, value: str | None) -> float | None:
        if value is None or value == "":
            return None
        return float(value)

    def _horizontal_distance_m(self, lat_deg: float, lon_deg: float) -> tuple[float, float, float]:
        meters_per_deg_lat = 111_111.0
        mean_lat_rad = math.radians((lat_deg + self.target_lat_deg) / 2.0)
        meters_per_deg_lon = max(1.0, meters_per_deg_lat * math.cos(mean_lat_rad))
        delta_north_m = (lat_deg - self.target_lat_deg) * meters_per_deg_lat
        delta_east_m = (lon_deg - self.target_lon_deg) * meters_per_deg_lon
        horizontal_distance_m = math.hypot(delta_north_m, delta_east_m)
        return delta_north_m, delta_east_m, horizontal_distance_m

    def _handle_global_position(self, message: VehicleGlobalPosition) -> None:
        if not message.lat_lon_valid or not message.alt_valid:
            self.last_summary = (
                f"lat_lon_valid={message.lat_lon_valid} alt_valid={message.alt_valid}"
            )
            return

        current_lat_deg = float(message.lat)
        current_lon_deg = float(message.lon)
        current_alt_m = float(message.alt)
        delta_north_m, delta_east_m, horizontal_distance_m = self._horizontal_distance_m(
            current_lat_deg, current_lon_deg
        )
        altitude_error_m = (
            0.0 if self.target_alt_m is None else current_alt_m - self.target_alt_m
        )
        self.last_summary = (
            f"lat={current_lat_deg:.7f} lon={current_lon_deg:.7f} alt={current_alt_m:.1f} "
            f"delta_north={delta_north_m:.1f} delta_east={delta_east_m:.1f} "
            f"horizontal_distance={horizontal_distance_m:.1f} altitude_error={altitude_error_m:.1f}"
        )

        horizontal_ok = horizontal_distance_m <= self.horizontal_tolerance_m
        altitude_ok = (
            self.target_alt_m is None
            or abs(altitude_error_m) <= self.altitude_tolerance_m
        )

        if horizontal_ok and altitude_ok:
            self.success = True
            self.get_logger().info(
                f"matched global position target {self.last_summary}"
            )

    def _check_timeout(self) -> None:
        if self.success or self.failed:
            return

        if time.monotonic() - self.start_time >= self.timeout_sec:
            self.failed = True
            self.get_logger().error(
                f"timed out waiting for global target on {self.topic}; "
                f"last seen: {self.last_summary}"
            )


def main() -> int:
    rclpy.init()
    try:
        node = VehicleGlobalPositionTargetWaiter()
    except (KeyError, ValueError) as exc:
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
