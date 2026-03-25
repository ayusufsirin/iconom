#!/usr/bin/env python3
import csv
import math
import time
from pathlib import Path
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from std_msgs.msg import Float32

OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
RIVAL_STATE_TOPIC = "/competition/rival/state"
CUE_ERROR_TOPIC = "/guidance/camera_cue_error_deg"
BEARING_ERROR_TOPIC = "/guidance/bearing_error_deg"


def yaw_from_quaternion(z: float, w: float) -> float:
    return math.atan2(2.0 * w * z, 1.0 - 2.0 * z * z)


def wrap_angle(angle_rad: float) -> float:
    return math.atan2(math.sin(angle_rad), math.cos(angle_rad))


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
        self.last_cue_error_deg: Optional[float] = None
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
                "range_xy_m",
                "range_3d_m",
                "los_heading_deg",
                "bearing_error_deg",
                "camera_cue_error_deg",
                "in_forward_cone",
            ]
        )
        self.csv_file.flush()

        self.bearing_error_pub = self.create_publisher(Float32, BEARING_ERROR_TOPIC, 10)
        self.create_subscription(PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship, 10)
        self.create_subscription(PoseStamped, RIVAL_STATE_TOPIC, self._handle_rival, 10)
        self.create_subscription(Float32, CUE_ERROR_TOPIC, self._handle_cue_error, 10)
        self.timer = self.create_timer(self.publish_period_sec, self._tick)

        self.get_logger().info(
            f"cue geometry monitor listening on {OWNSHIP_STATE_TOPIC}, {RIVAL_STATE_TOPIC}, and {CUE_ERROR_TOPIC}; "
            f"publishing bearing error on {BEARING_ERROR_TOPIC} and writing CSV to {self.output_csv}"
        )

    def _handle_ownship(self, msg: PoseStamped) -> None:
        self.ownship_state = msg

    def _handle_rival(self, msg: PoseStamped) -> None:
        self.rival_state = msg

    def _handle_cue_error(self, msg: Float32) -> None:
        self.last_cue_error_deg = float(msg.data)

    def _tick(self) -> None:
        if self.ownship_state is None or self.rival_state is None:
            return

        now = time.monotonic()
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
        los_heading = math.atan2(dy, dx) if range_xy > 1e-6 else own_yaw
        bearing_error_deg = abs(math.degrees(wrap_angle(los_heading - own_yaw)))
        cue_error_deg = self.last_cue_error_deg if self.last_cue_error_deg is not None else float("nan")
        in_forward_cone = int(not math.isnan(cue_error_deg) and cue_error_deg <= self.forward_cone_deg)

        bearing_msg = Float32()
        bearing_msg.data = float(bearing_error_deg)
        self.bearing_error_pub.publish(bearing_msg)

        self.writer.writerow(
            [
                f"{t_sec:.3f}",
                f"{own_pos.x:.3f}",
                f"{own_pos.y:.3f}",
                f"{own_pos.z:.3f}",
                f"{math.degrees(own_yaw):.3f}",
                f"{rival_pos.x:.3f}",
                f"{rival_pos.y:.3f}",
                f"{rival_pos.z:.3f}",
                f"{range_xy:.3f}",
                f"{range_3d:.3f}",
                f"{math.degrees(los_heading):.3f}",
                f"{bearing_error_deg:.3f}",
                "nan" if math.isnan(cue_error_deg) else f"{cue_error_deg:.3f}",
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
