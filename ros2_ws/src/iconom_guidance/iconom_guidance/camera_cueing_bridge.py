#!/usr/bin/env python3
import math
import time
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from px4_msgs.msg import OffboardControlMode, VehicleRatesSetpoint
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import Float32, String


OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
SELECTED_TARGET_TOPIC = "/guidance/selected_target"
PURSUIT_STATE_TOPIC = "/guidance/pursuit_state"
CAMERA_CUE_ERROR_TOPIC = "/guidance/camera_cue_error_deg"
STATE_PURSUE = "pursue"


def yaw_from_quaternion(z: float, w: float) -> float:
    return math.atan2(2.0 * w * z, 1.0 - 2.0 * z * z)


def wrap_angle(angle_rad: float) -> float:
    return math.atan2(math.sin(angle_rad), math.cos(angle_rad))


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


class CameraCueingBridge(Node):
    def __init__(self) -> None:
        super().__init__("camera_cueing_bridge")

        self.declare_parameter("vehicle_namespace", "plane_01")
        self.declare_parameter("publish_rate_hz", 20.0)
        self.declare_parameter("thrust_x", 0.72)
        self.declare_parameter("roll_rate_gain", 1.2)
        self.declare_parameter("max_roll_rate", 1.0)
        self.declare_parameter("yaw_rate_gain", 0.35)
        self.declare_parameter("max_yaw_rate", 0.4)
        self.declare_parameter("pitch_rate", 0.0)
        self.declare_parameter("selected_timeout_sec", 6.0)

        namespace = str(self.get_parameter("vehicle_namespace").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.thrust_x = float(self.get_parameter("thrust_x").value)
        self.roll_rate_gain = float(self.get_parameter("roll_rate_gain").value)
        self.max_roll_rate = float(self.get_parameter("max_roll_rate").value)
        self.yaw_rate_gain = float(self.get_parameter("yaw_rate_gain").value)
        self.max_yaw_rate = float(self.get_parameter("max_yaw_rate").value)
        self.pitch_rate = float(self.get_parameter("pitch_rate").value)
        self.selected_timeout_sec = float(self.get_parameter("selected_timeout_sec").value)

        self.offboard_topic = f"/{namespace}/fmu/in/offboard_control_mode"
        self.rates_topic = f"/{namespace}/fmu/in/vehicle_rates_setpoint"

        self.ownship_state: Optional[PoseStamped] = None
        self.selected_target: Optional[PoseStamped] = None
        self.selected_target_at: Optional[float] = None
        self.pursuit_state = "idle"
        self.last_log_at = 0.0

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.offboard_pub = self.create_publisher(OffboardControlMode, self.offboard_topic, qos_profile)
        self.rates_pub = self.create_publisher(VehicleRatesSetpoint, self.rates_topic, qos_profile)
        self.cue_error_pub = self.create_publisher(Float32, CAMERA_CUE_ERROR_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(String, PURSUIT_STATE_TOPIC, self._handle_pursuit_state, 10)
        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._tick)

        self.get_logger().info(
            f"camera cueing bridge listening on {OWNSHIP_STATE_TOPIC}, {SELECTED_TARGET_TOPIC}, and {PURSUIT_STATE_TOPIC}; "
            f"publishing cue error on {CAMERA_CUE_ERROR_TOPIC} and offboard setpoints on {self.offboard_topic} / {self.rates_topic}"
        )

    def _now(self) -> float:
        return time.monotonic()

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        self.ownship_state = msg

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        self.selected_target = msg
        self.selected_target_at = self._now()

    def _handle_pursuit_state(self, msg: String) -> None:
        self.pursuit_state = msg.data.strip().lower()

    def _target_fresh(self) -> bool:
        return (
            self.selected_target is not None
            and self.selected_target_at is not None
            and (self._now() - self.selected_target_at) <= self.selected_timeout_sec
        )

    def _signed_heading_error_rad(self) -> Optional[float]:
        if self.ownship_state is None or not self._target_fresh() or self.selected_target is None:
            return None

        own = self.ownship_state.pose.position
        target = self.selected_target.pose.position
        dx = target.x - own.x
        dy = target.y - own.y
        if abs(dx) < 1e-6 and abs(dy) < 1e-6:
            return 0.0

        own_heading = yaw_from_quaternion(
            self.ownship_state.pose.orientation.z,
            self.ownship_state.pose.orientation.w,
        )
        los_heading = math.atan2(dy, dx)
        return wrap_angle(los_heading - own_heading)

    def _publish_cue_error(self, error_rad: Optional[float]) -> None:
        if error_rad is None:
            return
        msg = Float32()
        msg.data = float(abs(math.degrees(error_rad)))
        self.cue_error_pub.publish(msg)

    def _publish_offboard_setpoint(self, error_rad: float) -> None:
        if self.pursuit_state != STATE_PURSUE:
            return

        offboard = OffboardControlMode()
        offboard.timestamp = self.get_clock().now().nanoseconds // 1000
        offboard.position = False
        offboard.velocity = False
        offboard.acceleration = False
        offboard.attitude = False
        offboard.body_rate = True
        offboard.thrust_and_torque = False
        offboard.direct_actuator = False
        self.offboard_pub.publish(offboard)

        rates = VehicleRatesSetpoint()
        rates.timestamp = self.get_clock().now().nanoseconds // 1000
        rates.roll = clamp(self.roll_rate_gain * error_rad, -self.max_roll_rate, self.max_roll_rate)
        rates.pitch = self.pitch_rate
        rates.yaw = clamp(self.yaw_rate_gain * error_rad, -self.max_yaw_rate, self.max_yaw_rate)
        rates.thrust_body = [self.thrust_x, 0.0, 0.0]
        rates.reset_integral = False
        self.rates_pub.publish(rates)

        now = self._now()
        if (now - self.last_log_at) >= 2.0:
            self.last_log_at = now
            self.get_logger().info(
                f"published cueing offboard setpoint with cue_error_deg={abs(math.degrees(error_rad)):.1f} "
                f"roll_rate={rates.roll:.2f} yaw_rate={rates.yaw:.2f} thrust_x={self.thrust_x:.2f}"
            )

    def _tick(self) -> None:
        error_rad = self._signed_heading_error_rad()
        self._publish_cue_error(error_rad)
        if error_rad is not None:
            self._publish_offboard_setpoint(error_rad)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = CameraCueingBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
