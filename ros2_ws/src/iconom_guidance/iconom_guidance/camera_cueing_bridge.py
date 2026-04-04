#!/usr/bin/env python3
import math
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from px4_msgs.msg import OffboardControlMode, VehicleAttitudeSetpoint
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from std_msgs.msg import Float32, String

from .phase6_time import now_sec


OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
SELECTED_TARGET_TOPIC = "/guidance/selected_target"
PURSUIT_STATE_TOPIC = "/guidance/pursuit_state"
CAMERA_CUE_ERROR_TOPIC = "/guidance/camera_cue_error_deg"
LONGITUDINAL_PHASE_TOPIC = "/guidance/longitudinal_phase"
SPACING_MODE_TOPIC = "/guidance/spacing_mode"
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
        self.declare_parameter("range_damping_gain", 0.04)
        self.declare_parameter("range_integral_gain", 0.003)
        self.declare_parameter("range_integral_limit", 30.0)
        self.declare_parameter("closing_speed_filter_alpha", 0.35)
        self.declare_parameter("closing_speed_kp", 0.12)
        self.declare_parameter("closing_speed_ki", 0.0)
        self.declare_parameter("closing_speed_integral_limit", 0.5)
        self.declare_parameter("capture_closing_speed_max_mps", 6.0)
        self.declare_parameter("approach_closing_speed_max_mps", 2.5)
        self.declare_parameter("hold_closing_speed_max_mps", 0.8)
        self.declare_parameter("recovery_closing_speed_mps", 0.0)
        self.declare_parameter("longitudinal_outer_gain", 0.5)
        self.declare_parameter("hold_aft_error_band_m", 1.5)
        self.declare_parameter("approach_aft_error_band_m", 8.0)
        self.declare_parameter("recovery_aft_distance_min_m", 0.0)
        self.declare_parameter("target_chase_range_m", 5.0)
        self.declare_parameter("chase_range_tolerance_m", 3.0)
        self.declare_parameter("capture_chase_range_m", 18.0)
        self.declare_parameter("capture_tail_angle_max_deg", 45.0)
        self.declare_parameter("capture_heading_alignment_max_deg", 35.0)
        self.declare_parameter("follow_tail_angle_entry_max_deg", 30.0)
        self.declare_parameter("follow_tail_angle_exit_max_deg", 40.0)
        self.declare_parameter("follow_heading_alignment_entry_max_deg", 35.0)
        self.declare_parameter("follow_heading_alignment_exit_max_deg", 45.0)
        self.declare_parameter("follow_slot_range_entry_max_m", 12.0)
        self.declare_parameter("follow_hold_sec", 0.5)
        self.declare_parameter("follow_lock_squeeze_sec", 3.0)
        self.declare_parameter("settle_tail_angle_exit_max_deg", 55.0)
        self.declare_parameter("settle_heading_alignment_exit_max_deg", 55.0)
        self.declare_parameter("settle_range_entry_max_m", 30.0)
        self.declare_parameter("settle_hold_sec", 1.0)
        self.declare_parameter("settle_closing_speed_max_mps", 2.5)
        self.declare_parameter("settle_min_thrust_x", 0.5)
        self.declare_parameter("settle_closing_speed_decay_mps", 1.5)
        self.declare_parameter("settle_break_hold_sec", 1.0)
        self.declare_parameter("roll_angle_gain", 0.8)
        self.declare_parameter("max_roll_deg", 35.0)
        self.declare_parameter("pitch_angle_deg", 2.0)
        self.declare_parameter("pitch_angle_gain", 0.0)
        self.declare_parameter("max_pitch_deg", 12.0)
        self.declare_parameter("altitude_error_deadband_m", 2.0)
        self.declare_parameter("selected_timeout_sec", 6.0)
        self.declare_parameter("target_propagation_max_sec", 1.0)
        self.declare_parameter("capture_error_deg", 20.0)
        self.declare_parameter("near_roll_scale", 0.35)

        namespace = str(self.get_parameter("vehicle_namespace").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.max_thrust_x = float(self.get_parameter("thrust_x").value)
        self.min_thrust_x = float(self.get_parameter("min_thrust_x").value)
        self.range_thrust_gain = float(self.get_parameter("range_thrust_gain").value)
        self.range_damping_gain = float(self.get_parameter("range_damping_gain").value)
        self.range_integral_gain = float(self.get_parameter("range_integral_gain").value)
        self.range_integral_limit = float(self.get_parameter("range_integral_limit").value)
        self.closing_speed_filter_alpha = float(self.get_parameter("closing_speed_filter_alpha").value)
        self.closing_speed_kp = float(self.get_parameter("closing_speed_kp").value)
        self.closing_speed_ki = float(self.get_parameter("closing_speed_ki").value)
        self.closing_speed_integral_limit = float(self.get_parameter("closing_speed_integral_limit").value)
        self.capture_closing_speed_max_mps = float(self.get_parameter("capture_closing_speed_max_mps").value)
        self.approach_closing_speed_max_mps = float(self.get_parameter("approach_closing_speed_max_mps").value)
        self.hold_closing_speed_max_mps = float(self.get_parameter("hold_closing_speed_max_mps").value)
        self.recovery_closing_speed_mps = float(self.get_parameter("recovery_closing_speed_mps").value)
        self.longitudinal_outer_gain = float(self.get_parameter("longitudinal_outer_gain").value)
        self.hold_aft_error_band_m = float(self.get_parameter("hold_aft_error_band_m").value)
        self.approach_aft_error_band_m = float(self.get_parameter("approach_aft_error_band_m").value)
        self.recovery_aft_distance_min_m = float(self.get_parameter("recovery_aft_distance_min_m").value)
        self.target_chase_range_m = float(self.get_parameter("target_chase_range_m").value)
        self.chase_range_tolerance_m = float(self.get_parameter("chase_range_tolerance_m").value)
        self.capture_chase_range_m = float(self.get_parameter("capture_chase_range_m").value)
        self.capture_tail_angle_max_deg = float(self.get_parameter("capture_tail_angle_max_deg").value)
        self.capture_heading_alignment_max_deg = float(self.get_parameter("capture_heading_alignment_max_deg").value)
        self.follow_tail_angle_entry_max_deg = float(self.get_parameter("follow_tail_angle_entry_max_deg").value)
        self.follow_tail_angle_exit_max_deg = float(self.get_parameter("follow_tail_angle_exit_max_deg").value)
        self.follow_heading_alignment_entry_max_deg = float(self.get_parameter("follow_heading_alignment_entry_max_deg").value)
        self.follow_heading_alignment_exit_max_deg = float(self.get_parameter("follow_heading_alignment_exit_max_deg").value)
        self.follow_slot_range_entry_max_m = float(self.get_parameter("follow_slot_range_entry_max_m").value)
        self.follow_hold_sec = float(self.get_parameter("follow_hold_sec").value)
        self.follow_lock_squeeze_sec = float(self.get_parameter("follow_lock_squeeze_sec").value)
        self.settle_tail_angle_exit_max_deg = float(self.get_parameter("settle_tail_angle_exit_max_deg").value)
        self.settle_heading_alignment_exit_max_deg = float(self.get_parameter("settle_heading_alignment_exit_max_deg").value)
        self.settle_range_entry_max_m = float(self.get_parameter("settle_range_entry_max_m").value)
        self.settle_hold_sec = float(self.get_parameter("settle_hold_sec").value)
        self.settle_closing_speed_max_mps = float(self.get_parameter("settle_closing_speed_max_mps").value)
        self.settle_min_thrust_x = float(self.get_parameter("settle_min_thrust_x").value)
        self.settle_closing_speed_decay_mps = float(self.get_parameter("settle_closing_speed_decay_mps").value)
        self.settle_break_hold_sec = float(self.get_parameter("settle_break_hold_sec").value)
        self.roll_angle_gain = float(self.get_parameter("roll_angle_gain").value)
        self.max_roll_rad = math.radians(float(self.get_parameter("max_roll_deg").value))
        self.base_pitch_rad = math.radians(float(self.get_parameter("pitch_angle_deg").value))
        self.pitch_angle_gain = float(self.get_parameter("pitch_angle_gain").value)
        self.max_pitch_rad = math.radians(float(self.get_parameter("max_pitch_deg").value))
        self.altitude_error_deadband_m = float(self.get_parameter("altitude_error_deadband_m").value)
        self.selected_timeout_sec = float(self.get_parameter("selected_timeout_sec").value)
        self.target_propagation_max_sec = float(self.get_parameter("target_propagation_max_sec").value)
        self.capture_error_deg = float(self.get_parameter("capture_error_deg").value)
        self.near_roll_scale = float(self.get_parameter("near_roll_scale").value)

        self.offboard_topic = f"/{namespace}/fmu/in/offboard_control_mode"
        self.attitude_topic = f"/{namespace}/fmu/in/vehicle_attitude_setpoint"

        self.ownship_state: Optional[PoseStamped] = None
        self.selected_target: Optional[PoseStamped] = None
        self.selected_target_at: Optional[float] = None
        self.selected_target_heading_rad = 0.0
        self.target_velocity_x_mps = 0.0
        self.target_velocity_y_mps = 0.0
        self.target_velocity_z_mps = 0.0
        self.target_yaw_rate_radps = 0.0
        self.pursuit_state = "idle"
        self.last_log_at = 0.0
        self.previous_aft_distance_m: Optional[float] = None
        self.previous_longitudinal_sample_at: Optional[float] = None
        self.filtered_closing_speed_mps = 0.0
        self.integrated_speed_error = 0.0
        self.longitudinal_follow_latched = False
        self.longitudinal_phase = "capture"
        self.longitudinal_settle_ready_since: Optional[float] = None
        self.longitudinal_settle_broken_since: Optional[float] = None
        self.longitudinal_follow_ready_since: Optional[float] = None
        self.longitudinal_follow_hold_ready_since: Optional[float] = None
        self.longitudinal_follow_lock_broken_since: Optional[float] = None
        self.longitudinal_follow_lock_started_at: Optional[float] = None

        qos_profile = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.offboard_pub = self.create_publisher(OffboardControlMode, self.offboard_topic, qos_profile)
        self.attitude_pub = self.create_publisher(VehicleAttitudeSetpoint, self.attitude_topic, qos_profile)
        self.cue_error_pub = self.create_publisher(Float32, CAMERA_CUE_ERROR_TOPIC, 10)
        self.longitudinal_phase_pub = self.create_publisher(String, LONGITUDINAL_PHASE_TOPIC, 10)
        self.spacing_mode_pub = self.create_publisher(String, SPACING_MODE_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship_state, 10)
        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(String, PURSUIT_STATE_TOPIC, self._handle_pursuit_state, 10)
        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._tick)

        self.get_logger().info(
            f"camera cueing bridge listening on {OWNSHIP_STATE_TOPIC}, {SELECTED_TARGET_TOPIC}, and {PURSUIT_STATE_TOPIC}; "
            f"publishing cue error on {CAMERA_CUE_ERROR_TOPIC}, longitudinal phase on {LONGITUDINAL_PHASE_TOPIC}, spacing mode on {SPACING_MODE_TOPIC}, "
            f"and offboard setpoints on {self.offboard_topic} / {self.attitude_topic}"
        )

    def _now(self) -> float:
        return now_sec(self)

    def _reset_longitudinal_controller(self) -> None:
        self.previous_aft_distance_m = None
        self.previous_longitudinal_sample_at = None
        self.filtered_closing_speed_mps = 0.0
        self.integrated_speed_error = 0.0
        self.longitudinal_follow_latched = False
        self.longitudinal_phase = "capture"
        self.longitudinal_settle_ready_since = None
        self.longitudinal_settle_broken_since = None
        self.longitudinal_follow_hold_ready_since = None
        self.longitudinal_follow_lock_broken_since = None
        self.longitudinal_follow_lock_started_at = None
        self.longitudinal_follow_ready_since = None

    def _prime_longitudinal_observer(self, aft_distance_m: float) -> None:
        self.previous_aft_distance_m = aft_distance_m
        self.previous_longitudinal_sample_at = self._now()
        self.filtered_closing_speed_mps = 0.0
        self.integrated_speed_error = 0.0

    def _handle_ownship_state(self, msg: PoseStamped) -> None:
        self.ownship_state = msg

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        now = self._now()
        heading_rad = yaw_from_quaternion(msg.pose.orientation.z, msg.pose.orientation.w)
        if self.selected_target is not None and self.selected_target_at is not None:
            dt = now - self.selected_target_at
            if dt > 1e-3:
                previous_position = self.selected_target.pose.position
                current_position = msg.pose.position
                self.target_velocity_x_mps = float(current_position.x - previous_position.x) / dt
                self.target_velocity_y_mps = float(current_position.y - previous_position.y) / dt
                self.target_velocity_z_mps = float(current_position.z - previous_position.z) / dt
                self.target_yaw_rate_radps = wrap_angle(heading_rad - self.selected_target_heading_rad) / dt
        else:
            self.target_velocity_x_mps = 0.0
            self.target_velocity_y_mps = 0.0
            self.target_velocity_z_mps = 0.0
            self.target_yaw_rate_radps = 0.0
        self.selected_target = msg
        self.selected_target_at = now
        self.selected_target_heading_rad = heading_rad

    def _handle_pursuit_state(self, msg: String) -> None:
        self.pursuit_state = msg.data.strip().lower()
        if self.pursuit_state != STATE_PURSUE:
            self._reset_longitudinal_controller()

    def _target_fresh(self) -> bool:
        return (
            self.selected_target is not None
            and self.selected_target_at is not None
            and (self._now() - self.selected_target_at) <= self.selected_timeout_sec
        )

    def _target_heading_rad(self) -> Optional[float]:
        target_state = self._propagated_target_state()
        if target_state is None:
            return None
        return target_state[3]

    def _propagated_target_state(self) -> Optional[tuple[float, float, float, float]]:
        if not self._target_fresh() or self.selected_target is None or self.selected_target_at is None:
            return None

        propagation_dt = clamp(self._now() - self.selected_target_at, 0.0, self.target_propagation_max_sec)
        target = self.selected_target.pose.position
        propagated_heading_rad = wrap_angle(self.selected_target_heading_rad + self.target_yaw_rate_radps * propagation_dt)
        return (
            float(target.x) + self.target_velocity_x_mps * propagation_dt,
            float(target.y) + self.target_velocity_y_mps * propagation_dt,
            float(target.z) + self.target_velocity_z_mps * propagation_dt,
            propagated_heading_rad,
        )

    def _current_chase_geometry(self) -> tuple[Optional[float], Optional[float]]:
        if self.ownship_state is None:
            return None, None

        target_state = self._propagated_target_state()
        if target_state is None:
            return None, None

        target_x, target_y, _, target_heading = target_state
        own = self.ownship_state.pose.position
        own_heading = yaw_from_quaternion(
            self.ownship_state.pose.orientation.z,
            self.ownship_state.pose.orientation.w,
        )
        rival_to_own_heading = math.atan2(float(own.y) - target_y, float(own.x) - target_x)
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

    def _longitudinal_follow_ready(self, aft_distance_m: float, desired_aft_m: float, range_to_slot_m: Optional[float]) -> bool:
        tail_angle_deg, heading_alignment_error_deg = self._current_chase_geometry()
        aft_ready_threshold_m = max(
            self.recovery_aft_distance_min_m,
            desired_aft_m - self.approach_aft_error_band_m,
        )
        rear_aspect_good = (
            range_to_slot_m is not None
            and range_to_slot_m <= self.settle_range_entry_max_m
            and aft_distance_m >= aft_ready_threshold_m
            and tail_angle_deg is not None
            and heading_alignment_error_deg is not None
            and tail_angle_deg <= self.follow_tail_angle_entry_max_deg
            and heading_alignment_error_deg <= self.follow_heading_alignment_entry_max_deg
        )
        if not rear_aspect_good:
            self.longitudinal_settle_ready_since = None
            return False

        now = self._now()
        if self.longitudinal_settle_ready_since is None:
            self.longitudinal_settle_ready_since = now
            return False
        return (now - self.longitudinal_settle_ready_since) >= self.settle_hold_sec

    def _active_chase_range_m(self, range_to_target_m: Optional[float] = None, *, in_follow: bool = False) -> float:
        if not in_follow:
            return self.capture_chase_range_m
        expanded_follow_range_m = self.target_chase_range_m
        if range_to_target_m is not None and range_to_target_m > (self.target_chase_range_m + 2.0 * self.chase_range_tolerance_m):
            expanded_follow_range_m = max(self.target_chase_range_m + self.chase_range_tolerance_m, self.capture_chase_range_m * 0.5)
        if self.longitudinal_phase in ("follow_hold", "recovery"):
            return self.target_chase_range_m
        if self.longitudinal_phase != "follow_lock":
            return expanded_follow_range_m
        squeeze_enable_range_m = self.follow_slot_range_entry_max_m + self.chase_range_tolerance_m
        if self.longitudinal_follow_lock_started_at is None and (
            range_to_target_m is None or range_to_target_m > squeeze_enable_range_m
        ):
            return expanded_follow_range_m
        if self.longitudinal_follow_lock_started_at is None:
            self.longitudinal_follow_lock_started_at = self._now()
            return expanded_follow_range_m
        squeeze_progress = clamp((self._now() - self.longitudinal_follow_lock_started_at) / self.follow_lock_squeeze_sec, 0.0, 1.0)
        return expanded_follow_range_m + squeeze_progress * (self.target_chase_range_m - expanded_follow_range_m)

    def _trailing_slot_position(self) -> Optional[tuple[float, float, float]]:
        target_state = self._propagated_target_state()
        if target_state is None:
            return None

        target_x, target_y, target_z, target_heading = target_state
        active_range = self._active_chase_range_m(
            self._current_target_range_3d_m(),
            in_follow=self.longitudinal_phase in ("follow_lock", "follow_hold", "recovery"),
        )
        slot_x = target_x - math.cos(target_heading) * active_range
        slot_y = target_y - math.sin(target_heading) * active_range
        slot_z = target_z
        return float(slot_x), float(slot_y), float(slot_z)

    def _current_target_range_3d_m(self) -> Optional[float]:
        if self.ownship_state is None:
            return None
        target_state = self._propagated_target_state()
        if target_state is None:
            return None
        own = self.ownship_state.pose.position
        dx = float(target_state[0] - own.x)
        dy = float(target_state[1] - own.y)
        dz = float(target_state[2] - own.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def _current_slot_range_3d_m(self) -> Optional[float]:
        if self.ownship_state is None:
            return None
        slot = self._trailing_slot_position()
        if slot is None:
            return None
        own = self.ownship_state.pose.position
        dx = float(slot[0] - own.x)
        dy = float(slot[1] - own.y)
        dz = float(slot[2] - own.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def _current_aft_distance_m(self) -> Optional[float]:
        if self.ownship_state is None:
            return None

        target_state = self._propagated_target_state()
        if target_state is None:
            return None

        target_x, target_y, _, target_heading = target_state
        own = self.ownship_state.pose.position
        dx = float(own.x) - target_x
        dy = float(own.y) - target_y
        tx = math.cos(target_heading)
        ty = math.sin(target_heading)
        return -(dx * tx + dy * ty)

    def _estimate_closing_speed_mps(self, aft_distance_m: Optional[float]) -> tuple[float, float]:
        if aft_distance_m is None:
            self._reset_longitudinal_controller()
            return 0.0, 0.0

        now = self._now()
        if self.previous_aft_distance_m is None or self.previous_longitudinal_sample_at is None:
            self.previous_aft_distance_m = aft_distance_m
            self.previous_longitudinal_sample_at = now
            self.filtered_closing_speed_mps = 0.0
            return 0.0, 0.0

        dt = now - self.previous_longitudinal_sample_at
        if dt <= 0.0:
            self._reset_longitudinal_controller()
            return 0.0, 0.0

        raw_aft_rate_mps = (aft_distance_m - self.previous_aft_distance_m) / dt
        raw_closing_speed_mps = -raw_aft_rate_mps
        alpha = clamp(self.closing_speed_filter_alpha, 0.0, 1.0)
        self.filtered_closing_speed_mps = (
            (1.0 - alpha) * self.filtered_closing_speed_mps + alpha * raw_closing_speed_mps
        )
        self.previous_aft_distance_m = aft_distance_m
        self.previous_longitudinal_sample_at = now
        return self.filtered_closing_speed_mps, dt

    def _longitudinal_mode(self, aft_distance_m: float, desired_aft_m: float) -> str:
        aft_error_m = aft_distance_m - desired_aft_m
        near_recovery_band = abs(aft_error_m) <= self.approach_aft_error_band_m
        if (
            aft_distance_m < self.recovery_aft_distance_min_m
            and near_recovery_band
        ):
            return "recovery"
        if abs(aft_error_m) <= self.hold_aft_error_band_m:
            return "hold"
        if aft_error_m < -self.hold_aft_error_band_m:
            return "capture"
        if aft_error_m <= self.approach_aft_error_band_m:
            return "approach"
        return "capture"

    def _overshoot_risk(self, aft_distance_m: float, desired_aft_m: float, closing_speed_mps: float) -> bool:
        remaining_margin_m = aft_distance_m - desired_aft_m
        near_recovery_band = abs(remaining_margin_m) <= self.approach_aft_error_band_m
        return (
            (
                aft_distance_m < self.recovery_aft_distance_min_m
                and near_recovery_band
            )
            or (remaining_margin_m <= 0.0 and closing_speed_mps > 0.5)
        )

    def _desired_closing_speed_mps(self, aft_error_m: float, mode: str) -> float:
        if mode == "recovery":
            return self.recovery_closing_speed_mps
        if mode == "capture":
            return clamp(
                self.longitudinal_outer_gain * aft_error_m,
                0.0,
                self.capture_closing_speed_max_mps,
            )
        if mode == "approach":
            return clamp(
                self.longitudinal_outer_gain * aft_error_m,
                0.0,
                self.approach_closing_speed_max_mps,
            )
        return clamp(
            0.4 * self.longitudinal_outer_gain * aft_error_m,
            0.0,
            self.hold_closing_speed_max_mps,
        )

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

    def _compute_thrust_x(self, range_to_target_m: Optional[float]) -> tuple[float, float, float, float, str]:
        aft_distance_m = self._current_aft_distance_m()
        if aft_distance_m is None:
            self._reset_longitudinal_controller()
            return self.max_thrust_x, 0.0, 0.0, 0.0, "unavailable"

        closing_speed_mps, dt = self._estimate_closing_speed_mps(aft_distance_m)
        desired_capture_aft_m = self._active_chase_range_m(range_to_target_m, in_follow=False)
        desired_follow_aft_m = self._active_chase_range_m(range_to_target_m, in_follow=True)
        range_to_slot_m = self._current_slot_range_3d_m()
        if self.longitudinal_phase != "follow_lock":
            self.longitudinal_follow_lock_started_at = None

        if self.longitudinal_phase == "capture":
            if self._longitudinal_follow_ready(aft_distance_m, desired_capture_aft_m, range_to_slot_m):
                self.longitudinal_phase = "settle"
                self.longitudinal_settle_broken_since = None
                self.longitudinal_follow_ready_since = None
            else:
                self.longitudinal_follow_latched = False
                self.integrated_speed_error *= 0.5
                desired_closing_speed_mps = self.capture_closing_speed_max_mps
                return (
                    self.max_thrust_x,
                    aft_distance_m,
                    closing_speed_mps,
                    desired_closing_speed_mps,
                    "capture",
                )

        desired_aft_m = desired_capture_aft_m if self.longitudinal_phase in ("settle", "recovery") else desired_follow_aft_m
        aft_error_m = aft_distance_m - desired_aft_m
        overshoot_risk = self._overshoot_risk(aft_distance_m, desired_aft_m, closing_speed_mps)
        follow_hold_entry_aft_band_m = max(self.hold_aft_error_band_m, self.chase_range_tolerance_m)
        follow_hold_entry_closing_speed_max_mps = self.hold_closing_speed_max_mps + 0.5
        follow_hold_exit_aft_band_m = follow_hold_entry_aft_band_m + self.hold_aft_error_band_m
        follow_hold_exit_closing_speed_max_mps = follow_hold_entry_closing_speed_max_mps + 0.5
        tail_angle_deg, heading_alignment_error_deg = self._current_chase_geometry()
        settle_geometry_broken = (
            tail_angle_deg is None
            or heading_alignment_error_deg is None
            or tail_angle_deg > self.settle_tail_angle_exit_max_deg
            or heading_alignment_error_deg > self.settle_heading_alignment_exit_max_deg
        )
        follow_geometry_broken = (
            tail_angle_deg is None
            or heading_alignment_error_deg is None
            or tail_angle_deg > self.follow_tail_angle_exit_max_deg
            or heading_alignment_error_deg > self.follow_heading_alignment_exit_max_deg
        )

        if self.longitudinal_phase == "settle":
            self.longitudinal_follow_latched = True
            follow_entry_ready = (
                tail_angle_deg is not None
                and heading_alignment_error_deg is not None
                and tail_angle_deg <= self.follow_tail_angle_entry_max_deg
                and heading_alignment_error_deg <= self.follow_heading_alignment_entry_max_deg
                and aft_distance_m >= desired_follow_aft_m
                and range_to_slot_m is not None
                and range_to_slot_m <= self.follow_slot_range_entry_max_m
            )
            if settle_geometry_broken:
                now = self._now()
                if self.longitudinal_settle_broken_since is None:
                    self.longitudinal_settle_broken_since = now
                elif (now - self.longitudinal_settle_broken_since) >= self.settle_break_hold_sec:
                    self.longitudinal_phase = "capture"
                    self.longitudinal_follow_latched = False
                    self.longitudinal_settle_broken_since = None
                    self.longitudinal_follow_ready_since = None
                    self.integrated_speed_error *= 0.5
                    desired_closing_speed_mps = self.capture_closing_speed_max_mps
                    return (
                        self.max_thrust_x,
                        aft_distance_m,
                        closing_speed_mps,
                        desired_closing_speed_mps,
                        "capture",
                    )
            else:
                self.longitudinal_settle_broken_since = None
            if follow_entry_ready:
                now = self._now()
                if self.longitudinal_follow_ready_since is None:
                    self.longitudinal_follow_ready_since = now
                elif (now - self.longitudinal_follow_ready_since) >= self.follow_hold_sec:
                    self.longitudinal_phase = "follow_lock"
                    self.longitudinal_follow_hold_ready_since = None
                    self.longitudinal_follow_ready_since = None
                    self.longitudinal_follow_lock_started_at = None
                    self._prime_longitudinal_observer(aft_distance_m)
                    closing_speed_mps = 0.0
                    dt = 0.0
            else:
                self.longitudinal_follow_ready_since = None
                if overshoot_risk:
                    self.longitudinal_phase = "recovery"

        if self.longitudinal_phase == "recovery":
            self.longitudinal_follow_latched = True
            if aft_distance_m > (desired_aft_m + self.hold_aft_error_band_m) and closing_speed_mps <= 0.5 and not settle_geometry_broken:
                self.longitudinal_phase = "settle"
            else:
                self.integrated_speed_error *= 0.5
                return (
                    self.min_thrust_x,
                    aft_distance_m,
                    closing_speed_mps,
                    self.recovery_closing_speed_mps,
                    "recovery",
                )

        if self.longitudinal_phase == "settle":
            settle_target_from_aft_error_mps = max(0.0, self.longitudinal_outer_gain * aft_error_m)
            settle_target_from_current_closure_mps = max(
                self.settle_closing_speed_max_mps,
                closing_speed_mps - self.settle_closing_speed_decay_mps,
            )
            desired_closing_speed_mps = max(
                settle_target_from_aft_error_mps,
                settle_target_from_current_closure_mps,
            )
            mode = "settle"
        else:
            self.longitudinal_follow_latched = True
            if self.longitudinal_phase == "follow_lock":
                if follow_geometry_broken:
                    self.longitudinal_follow_hold_ready_since = None
                    now = self._now()
                    if self.longitudinal_follow_lock_broken_since is None:
                        self.longitudinal_follow_lock_broken_since = now
                    elif (now - self.longitudinal_follow_lock_broken_since) >= self.settle_break_hold_sec:
                        if not settle_geometry_broken:
                            self.longitudinal_phase = "settle"
                            self.longitudinal_follow_ready_since = None
                            self.longitudinal_follow_lock_broken_since = None
                            settle_target_from_aft_error_mps = max(0.0, self.longitudinal_outer_gain * aft_error_m)
                            settle_target_from_current_closure_mps = max(
                                self.settle_closing_speed_max_mps,
                                closing_speed_mps - self.settle_closing_speed_decay_mps,
                            )
                            desired_closing_speed_mps = max(
                                settle_target_from_aft_error_mps,
                                settle_target_from_current_closure_mps,
                            )
                            mode = "settle"
                        else:
                            self.longitudinal_phase = "capture"
                            self.longitudinal_follow_latched = False
                            self.longitudinal_follow_lock_broken_since = None
                            self.integrated_speed_error *= 0.5
                            desired_closing_speed_mps = self.capture_closing_speed_max_mps
                            return (
                                self.max_thrust_x,
                                aft_distance_m,
                                closing_speed_mps,
                                desired_closing_speed_mps,
                                "capture",
                            )
                else:
                    self.longitudinal_follow_lock_broken_since = None

                follow_lock_ready = (
                    not follow_geometry_broken
                    and range_to_target_m is not None
                    and range_to_target_m <= (self.target_chase_range_m + 2.0 * self.chase_range_tolerance_m)
                    and aft_distance_m >= self.target_chase_range_m
                    and abs(aft_distance_m - self.target_chase_range_m) <= follow_hold_entry_aft_band_m
                    and closing_speed_mps <= follow_hold_entry_closing_speed_max_mps
                )
                if follow_lock_ready:
                    now = self._now()
                    if self.longitudinal_follow_hold_ready_since is None:
                        self.longitudinal_follow_hold_ready_since = now
                    elif (now - self.longitudinal_follow_hold_ready_since) >= self.follow_hold_sec:
                        self.longitudinal_phase = "follow_hold"
                        self.longitudinal_follow_hold_ready_since = None
                else:
                    self.longitudinal_follow_hold_ready_since = None

                near_final_follow_lock = (
                    desired_aft_m <= (self.target_chase_range_m + 0.5)
                    and range_to_target_m is not None
                    and range_to_target_m <= self.follow_slot_range_entry_max_m
                )
                follow_target = clamp(
                    self.longitudinal_outer_gain * aft_error_m,
                    0.0,
                    self.approach_closing_speed_max_mps,
                )
                if near_final_follow_lock:
                    lock_floor = max(
                        self.hold_closing_speed_max_mps,
                        closing_speed_mps - self.settle_closing_speed_decay_mps,
                    )
                else:
                    lock_floor = max(
                        self.approach_closing_speed_max_mps,
                        closing_speed_mps - (0.5 * self.settle_closing_speed_decay_mps),
                    )
                desired_closing_speed_mps = max(follow_target, lock_floor)
                mode = "follow_lock"
            else:
                self.longitudinal_phase = "follow_hold"
                if follow_geometry_broken:
                    if not settle_geometry_broken:
                        self.longitudinal_phase = "settle"
                        self.longitudinal_follow_ready_since = None
                        self.longitudinal_follow_hold_ready_since = None
                        settle_target_from_aft_error_mps = max(0.0, self.longitudinal_outer_gain * aft_error_m)
                        settle_target_from_current_closure_mps = max(
                            self.settle_closing_speed_max_mps,
                            closing_speed_mps - self.settle_closing_speed_decay_mps,
                        )
                        desired_closing_speed_mps = max(
                            settle_target_from_aft_error_mps,
                            settle_target_from_current_closure_mps,
                        )
                        mode = "settle"
                    else:
                        self.longitudinal_phase = "capture"
                        self.longitudinal_follow_latched = False
                        self.longitudinal_follow_hold_ready_since = None
                        self.integrated_speed_error *= 0.5
                        desired_closing_speed_mps = self.capture_closing_speed_max_mps
                        return (
                            self.max_thrust_x,
                            aft_distance_m,
                            closing_speed_mps,
                            desired_closing_speed_mps,
                            "capture",
                        )
                else:
                    spacing_degraded = (
                        range_to_slot_m is not None
                        and range_to_slot_m > (self.target_chase_range_m + 1.5 * self.chase_range_tolerance_m)
                    ) or abs(aft_error_m) > follow_hold_exit_aft_band_m or (
                        closing_speed_mps > follow_hold_exit_closing_speed_max_mps
                    )
                    if spacing_degraded:
                        self.longitudinal_phase = "follow_lock"
                        self.longitudinal_follow_hold_ready_since = None
                        self.longitudinal_follow_lock_started_at = None
                        follow_target = clamp(
                            self.longitudinal_outer_gain * aft_error_m,
                            0.0,
                            self.approach_closing_speed_max_mps,
                        )
                        lock_floor = max(
                            self.approach_closing_speed_max_mps,
                            closing_speed_mps - (0.5 * self.settle_closing_speed_decay_mps),
                        )
                        desired_closing_speed_mps = max(follow_target, lock_floor)
                        mode = "follow_lock"
                    else:
                        mode = self._longitudinal_mode(aft_distance_m, desired_aft_m)
                        desired_closing_speed_mps = self._desired_closing_speed_mps(aft_error_m, mode)
                        if mode == "recovery" or overshoot_risk:
                            self.longitudinal_phase = "recovery"
                            self.integrated_speed_error *= 0.5
                            return (
                                self.min_thrust_x,
                                aft_distance_m,
                                closing_speed_mps,
                                desired_closing_speed_mps,
                                "recovery",
                            )

        speed_error = desired_closing_speed_mps - closing_speed_mps
        if dt > 0.0:
            self.integrated_speed_error = clamp(
                self.integrated_speed_error + speed_error * dt,
                -self.closing_speed_integral_limit,
                self.closing_speed_integral_limit,
            )

        proportional_term = self.closing_speed_kp * speed_error
        integral_term = self.closing_speed_ki * self.integrated_speed_error
        base_thrust_x = self.min_thrust_x
        if self.longitudinal_phase == "settle":
            base_thrust_x = clamp(self.settle_min_thrust_x, self.min_thrust_x, self.max_thrust_x)
        elif self.longitudinal_phase == "follow_lock":
            near_final_follow_lock = (
                desired_aft_m <= (self.target_chase_range_m + 0.5)
                and range_to_target_m is not None
                and range_to_target_m <= self.follow_slot_range_entry_max_m
            )
            if near_final_follow_lock:
                base_thrust_x = self.min_thrust_x
            else:
                base_thrust_x = clamp(self.settle_min_thrust_x, self.min_thrust_x, self.max_thrust_x)
        commanded = base_thrust_x + proportional_term + integral_term
        return (
            clamp(commanded, base_thrust_x, self.max_thrust_x),
            aft_distance_m,
            closing_speed_mps,
            desired_closing_speed_mps,
            mode,
        )

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
        range_to_slot_m = self._current_slot_range_3d_m()
        tail_angle_deg, heading_alignment_error_deg = self._current_chase_geometry()
        thrust_x, aft_distance_m, closing_speed_mps, desired_closing_speed_mps, longitudinal_mode = (
            self._compute_thrust_x(range_to_target_m)
        )
        phase_msg = String()
        phase_msg.data = self.longitudinal_phase
        self.longitudinal_phase_pub.publish(phase_msg)
        spacing_msg = String()
        spacing_msg.data = longitudinal_mode
        self.spacing_mode_pub.publish(spacing_msg)
        in_follow = self.longitudinal_phase in ("follow_lock", "follow_hold", "recovery")
        active_range = self._active_chase_range_m(range_to_target_m, in_follow=in_follow)
        near_hold_band = (
            in_follow
            and range_to_target_m is not None
            and range_to_target_m <= (self.target_chase_range_m + 2.0 * self.chase_range_tolerance_m)
        )

        if cue_error_deg <= self.capture_error_deg and near_hold_band:
            desired_roll = 0.0
        else:
            roll_scale = (0.5 * self.near_roll_scale) if near_hold_band else 1.0
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
            if in_follow and target_heading is not None:
                desired_yaw = target_heading
            else:
                desired_yaw = wrap_angle(own_heading + error_rad)

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
            range_text = ""
            if range_to_target_m is not None:
                range_text += f" target_range_m={range_to_target_m:.1f}"
            if range_to_slot_m is not None:
                range_text += f" slot_range_m={range_to_slot_m:.1f}"
            geometry_text = ""
            if tail_angle_deg is not None and heading_alignment_error_deg is not None:
                geometry_text = (
                    f" tail_angle_deg={tail_angle_deg:.1f}"
                    f" heading_alignment_deg={heading_alignment_error_deg:.1f}"
                    f" active_range_m={active_range:.1f}"
                    f" aft_distance_m={aft_distance_m:.1f}"
                    f" closing_speed_mps={closing_speed_mps:.2f}"
                    f" desired_closing_speed_mps={desired_closing_speed_mps:.2f}"
                    f" longitudinal_phase={self.longitudinal_phase}"
                    f" spacing_mode={longitudinal_mode}"
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
            self._reset_longitudinal_controller()
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
