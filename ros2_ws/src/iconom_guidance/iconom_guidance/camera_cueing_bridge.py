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


def angle_error_deg(a_deg: float, b_deg: float) -> float:
    return abs(math.degrees(wrap_angle(math.radians(a_deg - b_deg))))


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
        self.declare_parameter("min_thrust_x", 0.36)
        self.declare_parameter("range_thrust_gain", 0.02)
        self.declare_parameter("range_damping_gain", 0.06)
        self.declare_parameter("closing_speed_filter_alpha", 0.35)
        self.declare_parameter("target_chase_range_m", 5.0)
        self.declare_parameter("chase_range_tolerance_m", 5.0)
        self.declare_parameter("capture_chase_range_m", 20.0)
        self.declare_parameter("capture_tail_angle_max_deg", 45.0)
        self.declare_parameter("capture_heading_alignment_max_deg", 35.0)
        self.declare_parameter("roll_angle_gain", 0.8)
        self.declare_parameter("max_roll_deg", 35.0)
        self.declare_parameter("pitch_angle_deg", 2.0)
        self.declare_parameter("pitch_angle_gain", 0.0)
        self.declare_parameter("max_pitch_deg", 12.0)
        self.declare_parameter("altitude_error_deadband_m", 2.0)
        self.declare_parameter("selected_timeout_sec", 6.0)
        self.declare_parameter("capture_error_deg", 20.0)
        self.declare_parameter("near_roll_scale", 0.35)

        namespace = str(self.get_parameter("vehicle_namespace").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.max_thrust_x = float(self.get_parameter("thrust_x").value)
        self.min_thrust_x = float(self.get_parameter("min_thrust_x").value)
        self.range_thrust_gain = float(self.get_parameter("range_thrust_gain").value)
        self.range_damping_gain = float(self.get_parameter("range_damping_gain").value)
        self.closing_speed_filter_alpha = float(self.get_parameter("closing_speed_filter_alpha").value)
        self.target_chase_range_m = float(self.get_parameter("target_chase_range_m").value)
        self.chase_range_tolerance_m = float(self.get_parameter("chase_range_tolerance_m").value)
        self.capture_chase_range_m = float(self.get_parameter("capture_chase_range_m").value)
        self.capture_tail_angle_max_deg = float(self.get_parameter("capture_tail_angle_max_deg").value)
        self.capture_heading_alignment_max_deg = float(self.get_parameter("capture_heading_alignment_max_deg").value)
        self.roll_angle_gain = float(self.get_parameter("roll_angle_gain").value)
        self.max_roll_rad = math.radians(float(self.get_parameter("max_roll_deg").value))
        self.base_pitch_rad = math.radians(float(self.get_parameter("pitch_angle_deg").value))
        self.pitch_angle_gain = float(self.get_parameter("pitch_angle_gain").value)
        self.max_pitch_rad = math.radians(float(self.get_parameter("max_pitch_deg").value))
        self.altitude_error_deadband_m = float(self.get_parameter("altitude_error_deadband_m").value)
        self.selected_timeout_sec = float(self.get_parameter("selected_timeout_sec").value)
        self.capture_error_deg = float(self.get_parameter("capture_error_deg").value)
        self.near_roll_scale = float(self.get_parameter("near_roll_scale").value)

        self.offboard_topic = f"/{namespace}/fmu/in/offboard_control_mode"
        self.attitude_topic = f"/{namespace}/fmu/in/vehicle_attitude_setpoint"

        self.ownship_state: Optional[PoseStamped] = None
        self.selected_target: Optional[PoseStamped] = None
        self.selected_target_at: Optional[float] = None
        self.pursuit_state = "idle"
        self.last_log_at = 0.0
        self.previous_range_to_target_m: Optional[float] = None
        self.previous_range_sample_at: Optional[float] = None
        self.filtered_closing_speed_mps = 0.0

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

    def _reset_range_controller(self) -> None:
        self.previous_range_to_target_m = None
        self.previous_range_sample_at = None
        self.filtered_closing_speed_mps = 0.0

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        self.ownship_state = msg

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        self.selected_target = msg
        self.selected_target_at = self._now()

    def _handle_pursuit_state(self, msg: String) -> None:
        self.pursuit_state = msg.data.strip().lower()
        if self.pursuit_state != STATE_PURSUE:
            self._reset_range_controller()

    def _target_fresh(self) -> bool:
        return (
            self.selected_target is not None
            and self.selected_target_at is not None
            and (self._now() - self.selected_target_at) <= self.selected_timeout_sec
        )

    def _target_heading_rad(self) -> Optional[float]:
        if not self._target_fresh() or self.selected_target is None:
            return None
        return yaw_from_quaternion(
            self.selected_target.pose.orientation.z,
            self.selected_target.pose.orientation.w,
        )

    def _current_chase_geometry(self) -> tuple[Optional[float], Optional[float]]:
        if self.ownship_state is None or not self._target_fresh() or self.selected_target is None:
            return None, None

        target_heading = self._target_heading_rad()
        if target_heading is None:
            return None, None

        own = self.ownship_state.pose.position
        target = self.selected_target.pose.position
        own_heading = yaw_from_quaternion(
            self.ownship_state.pose.orientation.z,
            self.ownship_state.pose.orientation.w,
        )
        rival_to_own_heading = math.atan2(float(own.y - target.y), float(own.x - target.x))
        rival_rear_heading = wrap_angle(target_heading + math.pi)

        tail_angle_deg = angle_error_deg(math.degrees(rival_to_own_heading), math.degrees(rival_rear_heading))
        heading_alignment_error_deg = angle_error_deg(math.degrees(own_heading), math.degrees(target_heading))
        return tail_angle_deg, heading_alignment_error_deg

    def _tail_chase_ready(self) -> bool:
        tail_angle_deg, heading_alignment_error_deg = self._current_chase_geometry()
        return (
            tail_angle_deg is not None
            and heading_alignment_error_deg is not None
            and tail_angle_deg <= self.capture_tail_angle_max_deg
            and heading_alignment_error_deg <= self.capture_heading_alignment_max_deg
        )

    def _active_chase_range_m(self, range_to_target_m: Optional[float] = None) -> float:
        if not self._tail_chase_ready():
            return self.capture_chase_range_m
        if range_to_target_m is not None and range_to_target_m > (self.target_chase_range_m + self.chase_range_tolerance_m):
            return max(self.target_chase_range_m + self.chase_range_tolerance_m, self.capture_chase_range_m * 0.5)
        return self.target_chase_range_m

    def _trailing_slot_position(self) -> Optional[tuple[float, float, float]]:
        if not self._target_fresh() or self.selected_target is None:
            return None
        target = self.selected_target.pose.position
        target_heading = self._target_heading_rad()
        if target_heading is None:
            return None

        active_range = self._active_chase_range_m(self._current_target_range_3d_m())
        slot_x = target.x - math.cos(target_heading) * active_range
        slot_y = target.y - math.sin(target_heading) * active_range
        slot_z = target.z
        return float(slot_x), float(slot_y), float(slot_z)

    def _current_target_range_3d_m(self) -> Optional[float]:
        if self.ownship_state is None or not self._target_fresh() or self.selected_target is None:
            return None
        own = self.ownship_state.pose.position
        target = self.selected_target.pose.position
        dx = float(target.x - own.x)
        dy = float(target.y - own.y)
        dz = float(target.z - own.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def _estimate_closing_speed_mps(self, range_to_target_m: Optional[float]) -> float:
        if range_to_target_m is None:
            self._reset_range_controller()
            return 0.0

        now = self._now()
        if self.previous_range_to_target_m is None or self.previous_range_sample_at is None:
            self.previous_range_to_target_m = range_to_target_m
            self.previous_range_sample_at = now
            self.filtered_closing_speed_mps = 0.0
            return 0.0

        dt = max(1e-3, now - self.previous_range_sample_at)
        raw_closing_speed_mps = max(0.0, (self.previous_range_to_target_m - range_to_target_m) / dt)
        alpha = clamp(self.closing_speed_filter_alpha, 0.0, 1.0)
        self.filtered_closing_speed_mps = (
            (1.0 - alpha) * self.filtered_closing_speed_mps + alpha * raw_closing_speed_mps
        )
        self.previous_range_to_target_m = range_to_target_m
        self.previous_range_sample_at = now
        return self.filtered_closing_speed_mps

    def _signed_heading_error_rad(self) -> Optional[float]:
        if self.ownship_state is None:
            return None

        slot = self._trailing_slot_position()
        if slot is None:
            return None

        own = self.ownship_state.pose.position
        dx = slot[0] - float(own.x)
        dy = slot[1] - float(own.y)
        if abs(dx) < 1e-6 and abs(dy) < 1e-6:
            return 0.0

        own_heading = yaw_from_quaternion(
            self.ownship_state.pose.orientation.z,
            self.ownship_state.pose.orientation.w,
        )
        slot_heading = math.atan2(dy, dx)
        return wrap_angle(slot_heading - own_heading)

    def _publish_cue_error(self, error_rad: Optional[float]) -> None:
        if error_rad is None:
            return
        msg = Float32()
        msg.data = float(abs(math.degrees(error_rad)))
        self.cue_error_pub.publish(msg)

    def _compute_pitch_angle(self) -> float:
        slot = self._trailing_slot_position()
        if self.ownship_state is None or slot is None:
            return self.base_pitch_rad

        own_z = float(self.ownship_state.pose.position.z)
        slot_z = float(slot[2])
        altitude_error = own_z - slot_z
        if abs(altitude_error) <= self.altitude_error_deadband_m:
            return self.base_pitch_rad

        commanded_pitch = self.base_pitch_rad + self.pitch_angle_gain * altitude_error
        return clamp(commanded_pitch, -self.max_pitch_rad, self.max_pitch_rad)

    def _compute_thrust_x(self, range_to_target_m: Optional[float]) -> tuple[float, float]:
        if range_to_target_m is None:
            self._reset_range_controller()
            return self.max_thrust_x, 0.0

        in_tail_chase = self._tail_chase_ready()
        active_range = self._active_chase_range_m(range_to_target_m)
        closing_speed_mps = self._estimate_closing_speed_mps(range_to_target_m)

        if in_tail_chase and range_to_target_m <= (self.target_chase_range_m + self.chase_range_tolerance_m):
            return self.min_thrust_x, closing_speed_mps

        range_error = range_to_target_m - active_range
        if in_tail_chase and range_to_target_m <= (self.target_chase_range_m + 2.0 * self.chase_range_tolerance_m):
            proportional_term = 0.5 * self.range_thrust_gain * range_error
        else:
            proportional_term = self.range_thrust_gain * range_error

        commanded = self.min_thrust_x + proportional_term - self.range_damping_gain * closing_speed_mps
        return clamp(commanded, self.min_thrust_x, self.max_thrust_x), closing_speed_mps

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
        range_to_target_m = self._current_target_range_3d_m()
        tail_angle_deg, heading_alignment_error_deg = self._current_chase_geometry()
        in_tail_chase = self._tail_chase_ready()
        active_range = self._active_chase_range_m(range_to_target_m)
        near_hold_band = (
            in_tail_chase
            and range_to_target_m is not None
            and range_to_target_m <= (self.target_chase_range_m + self.chase_range_tolerance_m)
        )

        if cue_error_deg <= self.capture_error_deg and near_hold_band:
            desired_roll = 0.0
        else:
            roll_scale = self.near_roll_scale if near_hold_band else 1.0
            desired_roll = clamp(
                self.roll_angle_gain * roll_scale * error_rad,
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
            target_heading = self._target_heading_rad()
            if in_tail_chase and target_heading is not None:
                desired_yaw = target_heading
            else:
                desired_yaw = wrap_angle(own_heading + error_rad)

        thrust_x, closing_speed_mps = self._compute_thrust_x(range_to_target_m)

        attitude = VehicleAttitudeSetpoint()
        attitude.timestamp = self.get_clock().now().nanoseconds // 1000
        attitude.q_d = quaternion_from_euler(desired_roll, desired_pitch, desired_yaw)
        attitude.yaw_sp_move_rate = 0.0
        attitude.thrust_body = [thrust_x, 0.0, 0.0]
        attitude.reset_integral = False
        attitude.fw_control_yaw_wheel = False
        self.attitude_pub.publish(attitude)

        now = self._now()
        if (now - self.last_log_at) >= 2.0:
            self.last_log_at = now
            range_text = f" range_m={range_to_target_m:.1f}" if range_to_target_m is not None else ""
            geometry_text = ""
            if tail_angle_deg is not None and heading_alignment_error_deg is not None:
                geometry_text = (
                    f" tail_angle_deg={tail_angle_deg:.1f}"
                    f" heading_alignment_deg={heading_alignment_error_deg:.1f}"
                    f" active_range_m={active_range:.1f}"
                    f" closing_speed_mps={closing_speed_mps:.2f}"
                )
            self.get_logger().info(
                f"published trailing-slot cueing setpoint with cue_error_deg={cue_error_deg:.1f}"
                f" roll_deg={math.degrees(desired_roll):.1f} pitch_deg={math.degrees(desired_pitch):.1f}"
                f" yaw_deg={math.degrees(desired_yaw):.1f} thrust_x={thrust_x:.2f}{range_text}{geometry_text}"
            )

    def _tick(self) -> None:
        error_rad = self._signed_heading_error_rad()
        self._publish_cue_error(error_rad)
        if error_rad is None:
            self._reset_range_controller()
            return
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
