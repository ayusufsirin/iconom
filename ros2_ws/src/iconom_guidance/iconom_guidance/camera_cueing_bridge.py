#!/usr/bin/env python3
import math
import time
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from px4_msgs.msg import OffboardControlMode, VehicleAttitudeSetpoint
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


def quaternion_from_euler(roll: float, pitch: float, yaw: float) -> list[float]:
    cr = math.cos(roll * 0.5)
    sr = math.sin(roll * 0.5)
    cp = math.cos(pitch * 0.5)
    sp = math.sin(pitch * 0.5)
    cy = math.cos(yaw * 0.5)
    sy = math.sin(yaw * 0.5)

    w = cr * cp * cy + sr * sp * sy
    x = sr * cp * cy - cr * sp * sy
    y = cr * sp * cy + sr * cp * sy
    z = cr * cp * sy - sr * sp * cy
    return [w, x, y, z]


class CameraCueingBridge(Node):
    def __init__(self) -> None:
        super().__init__("camera_cueing_bridge")

        self.declare_parameter("vehicle_namespace", "plane_01")
        self.declare_parameter("publish_rate_hz", 20.0)
        self.declare_parameter("thrust_x", 0.72)
        self.declare_parameter("roll_angle_gain", 0.8)
        self.declare_parameter("max_roll_deg", 35.0)
        self.declare_parameter("pitch_angle_deg", 2.0)
        self.declare_parameter("pitch_angle_gain", 0.0)
        self.declare_parameter("max_pitch_deg", 12.0)
        self.declare_parameter("altitude_error_deadband_m", 2.0)
        self.declare_parameter("selected_timeout_sec", 6.0)
        self.declare_parameter("capture_error_deg", 20.0)

        namespace = str(self.get_parameter("vehicle_namespace").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.thrust_x = float(self.get_parameter("thrust_x").value)
        self.roll_angle_gain = float(self.get_parameter("roll_angle_gain").value)
        self.max_roll_rad = math.radians(float(self.get_parameter("max_roll_deg").value))
        self.base_pitch_rad = math.radians(float(self.get_parameter("pitch_angle_deg").value))
        self.pitch_angle_gain = float(self.get_parameter("pitch_angle_gain").value)
        self.max_pitch_rad = math.radians(float(self.get_parameter("max_pitch_deg").value))
        self.altitude_error_deadband_m = float(self.get_parameter("altitude_error_deadband_m").value)
        self.selected_timeout_sec = float(self.get_parameter("selected_timeout_sec").value)
        self.capture_error_deg = float(self.get_parameter("capture_error_deg").value)

        self.offboard_topic = f"/{namespace}/fmu/in/offboard_control_mode"
        self.attitude_topic = f"/{namespace}/fmu/in/vehicle_attitude_setpoint"

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
        self.attitude_pub = self.create_publisher(VehicleAttitudeSetpoint, self.attitude_topic, qos_profile)
        self.cue_error_pub = self.create_publisher(Float32, CAMERA_CUE_ERROR_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(String, PURSUIT_STATE_TOPIC, self._handle_pursuit_state, 10)
        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._tick)

        self.get_logger().info(
            f"camera cueing bridge listening on {OWNSHIP_STATE_TOPIC}, {SELECTED_TARGET_TOPIC}, and {PURSUIT_STATE_TOPIC}; "
            f"publishing cue error on {CAMERA_CUE_ERROR_TOPIC} and offboard setpoints on {self.offboard_topic} / {self.attitude_topic}"
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

    def _compute_pitch_angle(self) -> float:
        if self.ownship_state is None or not self._target_fresh() or self.selected_target is None:
            return self.base_pitch_rad

        own_z = float(self.ownship_state.pose.position.z)
        target_z = float(self.selected_target.pose.position.z)
        # PX4 local z is NED: more negative means higher altitude.
        altitude_error = own_z - target_z
        if abs(altitude_error) <= self.altitude_error_deadband_m:
            return self.base_pitch_rad

        commanded_pitch = self.base_pitch_rad + self.pitch_angle_gain * altitude_error
        return clamp(commanded_pitch, -self.max_pitch_rad, self.max_pitch_rad)

    def _publish_offboard_setpoint(self, error_rad: float) -> None:
        if self.pursuit_state != STATE_PURSUE:
            return

        offboard = OffboardControlMode()
        offboard.timestamp = self.get_clock().now().nanoseconds // 1000
        offboard.position = False
        offboard.velocity = False
        offboard.acceleration = False
        offboard.attitude = True
        offboard.body_rate = False
        offboard.thrust_and_torque = False
        offboard.direct_actuator = False
        self.offboard_pub.publish(offboard)

        cue_error_deg = abs(math.degrees(error_rad))
        if cue_error_deg <= self.capture_error_deg:
            desired_roll = 0.0
        else:
            desired_roll = clamp(
                self.roll_angle_gain * error_rad,
                -self.max_roll_rad,
                self.max_roll_rad,
            )

        desired_pitch = self._compute_pitch_angle()
        desired_yaw = 0.0
        if self.ownship_state is not None:
            own_heading = yaw_from_quaternion(
                self.ownship_state.pose.orientation.z,
                self.ownship_state.pose.orientation.w,
            )
            desired_yaw = wrap_angle(own_heading + error_rad)

        attitude = VehicleAttitudeSetpoint()
        attitude.timestamp = self.get_clock().now().nanoseconds // 1000
        attitude.q_d = quaternion_from_euler(desired_roll, desired_pitch, desired_yaw)
        attitude.yaw_sp_move_rate = 0.0
        attitude.thrust_body = [self.thrust_x, 0.0, 0.0]
        attitude.reset_integral = False
        attitude.fw_control_yaw_wheel = False
        self.attitude_pub.publish(attitude)

        now = self._now()
        if (now - self.last_log_at) >= 2.0:
            self.last_log_at = now
            self.get_logger().info(
                f"published cueing offboard setpoint with cue_error_deg={cue_error_deg:.1f} "
                f"roll_deg={math.degrees(desired_roll):.1f} pitch_deg={math.degrees(desired_pitch):.1f} "
                f"yaw_deg={math.degrees(desired_yaw):.1f} thrust_x={self.thrust_x:.2f}"
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
