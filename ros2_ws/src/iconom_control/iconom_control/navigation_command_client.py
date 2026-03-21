#!/usr/bin/env python3
import math
import os
import sys
import time

import rclpy
from px4_msgs.msg import VehicleCommand, VehicleCommandAck, VehicleGlobalPosition
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


class NavigationCommandClient(Node):
    def __init__(self) -> None:
        super().__init__("iconom_navigation_command_client")
        namespace = os.environ.get("ICONOM_VEHICLE_NAMESPACE", "plane_01")
        self.command_topic = os.environ.get(
            "PX4_COMMAND_TOPIC",
            f"/{namespace}/fmu/in/vehicle_command",
        )
        self.ack_topic = os.environ.get(
            "PX4_COMMAND_ACK_TOPIC",
            f"/{namespace}/fmu/out/vehicle_command_ack",
        )
        self.global_position_topic = os.environ.get(
            "PX4_GLOBAL_POSITION_TOPIC",
            f"/{namespace}/fmu/out/vehicle_global_position",
        )
        self.timeout_sec = float(os.environ.get("PX4_COMMAND_TIMEOUT_SEC", "20"))
        self.republish_interval_sec = float(
            os.environ.get("PX4_COMMAND_REPUBLISH_INTERVAL_SEC", "1.0")
        )
        self.position_ready_timeout_sec = float(
            os.environ.get("PX4_GLOBAL_POSITION_TIMEOUT_SEC", "20.0")
        )
        self.command_name = os.environ.get(
            "PX4_NAV_COMMAND_NAME", "nav_takeoff"
        ).strip().lower()
        self.target_system = int(os.environ.get("PX4_TARGET_SYSTEM", "1"))
        self.target_component = int(os.environ.get("PX4_TARGET_COMPONENT", "1"))
        self.source_system = int(os.environ.get("PX4_SOURCE_SYSTEM", "1"))
        self.source_component = int(os.environ.get("PX4_SOURCE_COMPONENT", "1"))
        self.offset_north_m = float(os.environ.get("PX4_TARGET_OFFSET_NORTH_M", "0.0"))
        self.offset_east_m = float(os.environ.get("PX4_TARGET_OFFSET_EAST_M", "0.0"))
        self.offset_alt_m = float(os.environ.get("PX4_TARGET_OFFSET_ALT_M", "30.0"))
        self.loiter_radius_m = float(os.environ.get("PX4_LOITER_RADIUS_M", "60.0"))
        self.groundspeed_m_s = float(os.environ.get("PX4_GROUNDSPEED_M_S", "20.0"))
        self.target_yaw_deg = self._parse_optional_float(
            os.environ.get("PX4_TARGET_YAW_DEG")
        )

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
        self.ack_subscription = self.create_subscription(
            VehicleCommandAck,
            self.ack_topic,
            self._handle_ack,
            qos_profile,
        )
        self.global_position_subscription = self.create_subscription(
            VehicleGlobalPosition,
            self.global_position_topic,
            self._handle_global_position,
            qos_profile,
        )
        self.timer = self.create_timer(
            self.republish_interval_sec, self._republish_if_needed
        )

        self.start_time = time.monotonic()
        self.deadline = self.start_time + self.timeout_sec
        self.position_deadline = self.start_time + self.position_ready_timeout_sec
        self.position_ready = False
        self.base_lat_deg = math.nan
        self.base_lon_deg = math.nan
        self.base_alt_m = math.nan
        self.command_id = 0
        self.params: dict[str, float] | None = None
        self.attempt_count = 0
        self.accepted = False
        self.failed = False
        self.failure_reason = ""

        self.get_logger().info(
            f"waiting on {self.global_position_topic} to seed {self.command_name}; "
            f"publishing on {self.command_topic} and waiting for ack on {self.ack_topic}"
        )

    def _parse_optional_float(self, value: str | None) -> float:
        if value is None or value.strip() == "":
            return math.nan
        return float(value)

    def _handle_global_position(self, message: VehicleGlobalPosition) -> None:
        if self.position_ready:
            return

        if not message.lat_lon_valid or not message.alt_valid:
            return

        self.base_lat_deg = float(message.lat)
        self.base_lon_deg = float(message.lon)
        self.base_alt_m = float(message.alt)
        self.command_id, self.params = self._resolve_command()
        self.position_ready = True
        self.get_logger().info(
            f"seeded global position lat={self.base_lat_deg:.7f} lon={self.base_lon_deg:.7f} "
            f"alt={self.base_alt_m:.1f} and built {self.command_name} command {self.command_id}"
        )
        self._publish_command()

    def _offset_target(self) -> tuple[float, float, float]:
        meters_per_deg_lat = 111_111.0
        lat_rad = math.radians(self.base_lat_deg)
        meters_per_deg_lon = max(1.0, meters_per_deg_lat * math.cos(lat_rad))
        target_lat = self.base_lat_deg + (self.offset_north_m / meters_per_deg_lat)
        target_lon = self.base_lon_deg + (self.offset_east_m / meters_per_deg_lon)
        target_alt = self.base_alt_m + self.offset_alt_m
        return target_lat, target_lon, target_alt

    def _resolve_command(self) -> tuple[int, dict[str, float]]:
        target_lat, target_lon, target_alt = self._offset_target()
        yaw = self.target_yaw_deg

        if self.command_name == "nav_takeoff":
            return (
                VehicleCommand.VEHICLE_CMD_NAV_TAKEOFF,
                {
                    "param1": 0.0,
                    "param2": 0.0,
                    "param3": 0.0,
                    "param4": yaw,
                    "param5": target_lat,
                    "param6": target_lon,
                    "param7": target_alt,
                },
            )

        if self.command_name == "nav_loiter_unlim":
            return (
                VehicleCommand.VEHICLE_CMD_NAV_LOITER_UNLIM,
                {
                    "param1": 0.0,
                    "param2": 0.0,
                    "param3": self.loiter_radius_m,
                    "param4": yaw,
                    "param5": target_lat,
                    "param6": target_lon,
                    "param7": target_alt,
                },
            )

        if self.command_name == "do_reposition":
            return (
                VehicleCommand.VEHICLE_CMD_DO_REPOSITION,
                {
                    "param1": self.groundspeed_m_s,
                    "param2": 1.0,
                    "param3": self.loiter_radius_m,
                    "param4": yaw,
                    "param5": target_lat,
                    "param6": target_lon,
                    "param7": target_alt,
                },
            )

        raise ValueError(f"unsupported PX4_NAV_COMMAND_NAME={self.command_name!r}")

    def _build_command(self) -> VehicleCommand:
        assert self.params is not None
        message = VehicleCommand()
        message.timestamp = self.get_clock().now().nanoseconds // 1000
        message.command = self.command_id
        message.param1 = self.params["param1"]
        message.param2 = self.params["param2"]
        message.param3 = self.params["param3"]
        message.param4 = self.params["param4"]
        message.param5 = self.params["param5"]
        message.param6 = self.params["param6"]
        message.param7 = self.params["param7"]
        message.target_system = self.target_system
        message.target_component = self.target_component
        message.source_system = self.source_system
        message.source_component = self.source_component
        message.confirmation = 0
        message.from_external = True
        return message

    def _publish_command(self) -> None:
        if not self.position_ready or self.accepted or self.failed:
            return
        self.attempt_count += 1
        self.publisher.publish(self._build_command())
        self.get_logger().info(
            f"published {self.command_name} attempt {self.attempt_count} "
            f"toward lat={self.params['param5']:.7f} lon={self.params['param6']:.7f} "
            f"alt={self.params['param7']:.1f}"
        )

    def _republish_if_needed(self) -> None:
        if self.accepted or self.failed:
            return

        now = time.monotonic()
        if not self.position_ready:
            if now >= self.position_deadline:
                self.failed = True
                self.failure_reason = (
                    f"timed out waiting for valid global position on {self.global_position_topic}"
                )
                self.get_logger().error(self.failure_reason)
            return

        if now >= self.deadline:
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

        if message.result == VehicleCommandAck.VEHICLE_CMD_RESULT_ACCEPTED:
            self.accepted = True
            self.get_logger().info(
                f"received accepted ack for {self.command_name} command {message.command}"
            )
            return

        if message.result == VehicleCommandAck.VEHICLE_CMD_RESULT_IN_PROGRESS:
            self.get_logger().info(
                f"{self.command_name} command {message.command} is still in progress"
            )
            return

        self.failed = True
        self.failure_reason = (
            f"{self.command_name} command {message.command} was acknowledged with result="
            f"{message.result} result_param1={message.result_param1} "
            f"result_param2={message.result_param2}"
        )
        self.get_logger().error(self.failure_reason)


def main() -> int:
    rclpy.init()
    try:
        node = NavigationCommandClient()
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
