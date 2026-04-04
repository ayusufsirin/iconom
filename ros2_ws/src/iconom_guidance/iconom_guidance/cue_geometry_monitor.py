#!/usr/bin/env python3
import csv
import math
from pathlib import Path
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from std_msgs.msg import Float32, String

from .phase6_time import now_sec

OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
RIVAL_STATE_TOPIC = "/competition/rival/state"
SELECTED_TARGET_TOPIC = "/guidance/selected_target"
INTERCEPT_TARGET_TOPIC = "/guidance/intercept_target"
CUE_ERROR_TOPIC = "/guidance/camera_cue_error_deg"
BEARING_ERROR_TOPIC = "/guidance/bearing_error_deg"
LONGITUDINAL_PHASE_TOPIC = "/guidance/longitudinal_phase"
SPACING_MODE_TOPIC = "/guidance/spacing_mode"


def yaw_from_quaternion(z: float, w: float) -> float:
    return math.atan2(2.0 * w * z, 1.0 - 2.0 * z * z)


def wrap_angle(angle_rad: float) -> float:
    return math.atan2(math.sin(angle_rad), math.cos(angle_rad))


def format_float(value: float) -> str:
    if math.isnan(value):
        return "nan"
    return f"{value:.3f}"


class CueGeometryMonitor(Node):
    def __init__(self) -> None:
        super().__init__("cue_geometry_monitor")

        self.declare_parameter("publish_period_sec", 0.2)
        self.declare_parameter("forward_cone_deg", 25.0)
        self.declare_parameter("output_csv", "/tmp/iconom-phase6-scripted-cue-geometry.csv")

        self.publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self.forward_cone_deg = float(self.get_parameter("forward_cone_deg").value)
        self.output_csv = str(self.get_parameter("output_csv").value)

        self.ownship_state: Optional[PoseStamped] = None
        self.rival_state: Optional[PoseStamped] = None
        self.selected_target: Optional[PoseStamped] = None
        self.intercept_target: Optional[PoseStamped] = None
        self.selected_target_at: Optional[float] = None
        self.intercept_target_at: Optional[float] = None
        self.last_cue_error_deg: Optional[float] = None
        self.longitudinal_phase = "unavailable"
        self.spacing_mode = "unavailable"
        self.start_time: Optional[float] = None

        output_path = Path(self.output_csv)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        self.csv_file = output_path.open("w", newline="", encoding="utf-8")
        self.writer = csv.writer(self.csv_file)
        self.writer.writerow(
            [
                "t_sec",
                "own_x",
                "own_y",
                "own_z",
                "own_yaw_deg",
                "rival_x",
                "rival_y",
                "rival_z",
                "rival_yaw_deg",
                "selected_x",
                "selected_y",
                "selected_z",
                "selected_yaw_deg",
                "selected_age_sec",
                "intercept_x",
                "intercept_y",
                "intercept_z",
                "intercept_yaw_deg",
                "intercept_age_sec",
                "rival_selected_gap_m",
                "rival_intercept_gap_m",
                "range_xy_m",
                "range_3d_m",
                "los_heading_deg",
                "bearing_error_deg",
                "camera_cue_error_deg",
                "longitudinal_phase",
                "spacing_mode",
                "in_forward_cone",
            ]
        )
        self.csv_file.flush()

        self.bearing_error_pub = self.create_publisher(Float32, BEARING_ERROR_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship, 10)
        self.create_subscription(PoseStamped, RIVAL_STATE_TOPIC, self._handle_rival, 10)
        self.create_subscription(PoseStamped, SELECTED_TARGET_TOPIC, self._handle_selected_target, 10)
        self.create_subscription(PoseStamped, INTERCEPT_TARGET_TOPIC, self._handle_intercept_target, 10)
        self.create_subscription(Float32, CUE_ERROR_TOPIC, self._handle_cue_error, 10)
        self.create_subscription(String, LONGITUDINAL_PHASE_TOPIC, self._handle_longitudinal_phase, 10)
        self.create_subscription(String, SPACING_MODE_TOPIC, self._handle_spacing_mode, 10)
        self.timer = self.create_timer(self.publish_period_sec, self._tick)

        self.get_logger().info(
            f"cue geometry monitor listening on {OWNSHIP_STATE_TOPIC}, {RIVAL_STATE_TOPIC}, {SELECTED_TARGET_TOPIC}, {INTERCEPT_TARGET_TOPIC}, {CUE_ERROR_TOPIC}, {LONGITUDINAL_PHASE_TOPIC}, and {SPACING_MODE_TOPIC}; "
            f"publishing bearing error on {BEARING_ERROR_TOPIC} and writing CSV to {self.output_csv}"
        )

    def _handle_ownship(self, msg: PoseStamped) -> None:
        self.ownship_state = msg

    def _handle_rival(self, msg: PoseStamped) -> None:
        self.rival_state = msg

    def _handle_selected_target(self, msg: PoseStamped) -> None:
        self.selected_target = msg
        self.selected_target_at = now_sec(self)

    def _handle_intercept_target(self, msg: PoseStamped) -> None:
        self.intercept_target = msg
        self.intercept_target_at = now_sec(self)

    def _handle_cue_error(self, msg: Float32) -> None:
        self.last_cue_error_deg = float(msg.data)

    def _handle_longitudinal_phase(self, msg: String) -> None:
        self.longitudinal_phase = msg.data.strip() or "unavailable"

    def _handle_spacing_mode(self, msg: String) -> None:
        self.spacing_mode = msg.data.strip() or "unavailable"

    def _pose_fields(
        self, msg: Optional[PoseStamped], observed_at: Optional[float], now: float
    ) -> tuple[float, float, float, float, float]:
        if msg is None or observed_at is None:
            nan = float("nan")
            return nan, nan, nan, nan, nan
        yaw_deg = math.degrees(yaw_from_quaternion(msg.pose.orientation.z, msg.pose.orientation.w))
        age_sec = max(0.0, now - observed_at)
        return (
            float(msg.pose.position.x),
            float(msg.pose.position.y),
            float(msg.pose.position.z),
            yaw_deg,
            age_sec,
        )

    def _gap_to_rival_m(self, msg: Optional[PoseStamped]) -> float:
        if self.rival_state is None or msg is None:
            return float("nan")
        dx = float(self.rival_state.pose.position.x - msg.pose.position.x)
        dy = float(self.rival_state.pose.position.y - msg.pose.position.y)
        dz = float(self.rival_state.pose.position.z - msg.pose.position.z)
        return math.sqrt(dx * dx + dy * dy + dz * dz)

    def _tick(self) -> None:
        if self.ownship_state is None or self.rival_state is None:
            return

        now = now_sec(self)
        if self.start_time is None:
            self.start_time = now
        t_sec = now - self.start_time

        own_pos = self.ownship_state.pose.position
        rival_pos = self.rival_state.pose.position
        dx = float(rival_pos.x - own_pos.x)
        dy = float(rival_pos.y - own_pos.y)
        dz = float(rival_pos.z - own_pos.z)

        range_xy = math.hypot(dx, dy)
        range_3d = math.sqrt(dx * dx + dy * dy + dz * dz)
        own_yaw = yaw_from_quaternion(
            self.ownship_state.pose.orientation.z,
            self.ownship_state.pose.orientation.w,
        )
        rival_yaw = yaw_from_quaternion(
            self.rival_state.pose.orientation.z,
            self.rival_state.pose.orientation.w,
        )
        los_heading = math.atan2(dy, dx) if range_xy > 1e-6 else own_yaw
        bearing_error_deg = abs(math.degrees(wrap_angle(los_heading - own_yaw)))
        cue_error_deg = self.last_cue_error_deg if self.last_cue_error_deg is not None else float("nan")
        in_forward_cone = int(not math.isnan(cue_error_deg) and cue_error_deg <= self.forward_cone_deg)

        selected_x, selected_y, selected_z, selected_yaw_deg, selected_age_sec = self._pose_fields(
            self.selected_target, self.selected_target_at, now
        )
        intercept_x, intercept_y, intercept_z, intercept_yaw_deg, intercept_age_sec = self._pose_fields(
            self.intercept_target, self.intercept_target_at, now
        )
        rival_selected_gap_m = self._gap_to_rival_m(self.selected_target)
        rival_intercept_gap_m = self._gap_to_rival_m(self.intercept_target)

        bearing_msg = Float32()
        bearing_msg.data = float(bearing_error_deg)
        self.bearing_error_pub.publish(bearing_msg)

        self.writer.writerow(
            [
                format_float(t_sec),
                format_float(float(own_pos.x)),
                format_float(float(own_pos.y)),
                format_float(float(own_pos.z)),
                format_float(math.degrees(own_yaw)),
                format_float(float(rival_pos.x)),
                format_float(float(rival_pos.y)),
                format_float(float(rival_pos.z)),
                format_float(math.degrees(rival_yaw)),
                format_float(selected_x),
                format_float(selected_y),
                format_float(selected_z),
                format_float(selected_yaw_deg),
                format_float(selected_age_sec),
                format_float(intercept_x),
                format_float(intercept_y),
                format_float(intercept_z),
                format_float(intercept_yaw_deg),
                format_float(intercept_age_sec),
                format_float(rival_selected_gap_m),
                format_float(rival_intercept_gap_m),
                format_float(range_xy),
                format_float(range_3d),
                format_float(math.degrees(los_heading)),
                format_float(bearing_error_deg),
                format_float(cue_error_deg),
                self.longitudinal_phase,
                self.spacing_mode,
                str(in_forward_cone),
            ]
        )
        self.csv_file.flush()

    def destroy_node(self) -> bool:
        try:
            self.csv_file.close()
        except Exception:
            pass
        return super().destroy_node()


def main(args=None) -> None:
    rclpy.init(args=args)
    node = CueGeometryMonitor()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
