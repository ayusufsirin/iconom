#!/usr/bin/env python3
"""
EKF Fusion Node for Rival State

Fuses slow (1 Hz) referee data with fast (20 Hz) live adapter data
to produce smooth high-rate rival state for cueing bridge.

State vector: [x, y, z, vx, vy, vz] (6-element)
Output: /fusion/rival/state (PoseStamped at 20 Hz)
"""
import math
from typing import Optional

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy


REFEREE_STATE_TOPIC = "/competition/rival/state/referee"
LIVE_STATE_TOPIC = "/competition/rival/state/live"
FUSED_STATE_TOPIC = "/fusion/rival/state"


class EKFFusion(Node):
    """Extended Kalman Filter for rival state fusion."""

    def __init__(self) -> None:
        super().__init__("ekf_fusion")

        self.declare_parameter("process_noise", 0.4)
        self.declare_parameter("observation_noise_referee", 0.01)
        self.declare_parameter("observation_noise_live", 0.1)
        self.declare_parameter("publish_rate_hz", 20.0)
        self.declare_parameter("initial_covariance", 1.0)
        self.declare_parameter("velocity_alpha", 0.3)

        self.process_noise = float(self.get_parameter("process_noise").value)
        self.obs_noise_referee = float(self.get_parameter("observation_noise_referee").value)
        self.obs_noise_live = float(self.get_parameter("observation_noise_live").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.initial_cov = float(self.get_parameter("initial_covariance").value)
        self.velocity_alpha = float(self.get_parameter("velocity_alpha").value)

        self.state = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        self.covariance = self._init_covariance()

        self.last_measurement_time: Optional[float] = None
        self.last_measurement_pos = [0.0, 0.0, 0.0]

        self.referee_received = False
        self.live_received = False

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.referee_sub = self.create_subscription(
            PoseStamped, REFEREE_STATE_TOPIC, self._handle_referee, qos)
        self.live_sub = self.create_subscription(
            PoseStamped, LIVE_STATE_TOPIC, self._handle_live, qos)

        self.fused_pub = self.create_publisher(PoseStamped, FUSED_STATE_TOPIC, 10)
        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._publish_fused)

        self.get_logger().info(
            f"EKF fusion: process_noise={self.process_noise}, "
            f"referee_noise={self.obs_noise_referee}, live_noise={self.obs_noise_live}"
        )

    def _init_covariance(self):
        cov = []
        for i in range(6):
            row = [0.0] * 6
            row[i] = self.initial_cov
            cov.extend(row)
        return cov

    def _handle_referee(self, msg: PoseStamped) -> None:
        self._update_from_measurement(msg, is_referee=True)

    def _handle_live(self, msg: PoseStamped) -> None:
        self._update_from_measurement(msg, is_referee=False)

    def _update_from_measurement(self, msg: PoseStamped, is_referee: bool) -> None:
        now = self.get_clock().now().nanoseconds / 1e9
        pos = [msg.pose.position.x, msg.pose.position.y, msg.pose.position.z]

        if not (self.referee_received or self.live_received):
            self.state[0], self.state[1], self.state[2] = pos
            self.last_measurement_time = now
            self.last_measurement_pos = pos[:]
            self.referee_received = is_referee
            self.live_received = not is_referee
            return

        if is_referee:
            self.referee_received = True
        else:
            self.live_received = True

        if self.last_measurement_time is not None:
            dt = now - self.last_measurement_time
            if dt > 0.001:
                self._predict(dt)

        obs_noise = self.obs_noise_referee if is_referee else self.obs_noise_live
        self._update(pos, obs_noise)

        if dt > 0.001 and dt < 1.0:
            vx = (pos[0] - self.last_measurement_pos[0]) / dt
            vy = (pos[1] - self.last_measurement_pos[1]) / dt
            vz = (pos[2] - self.last_measurement_pos[2]) / dt
            self.state[3] = self.state[3] * (1 - self.velocity_alpha) + vx * self.velocity_alpha
            self.state[4] = self.state[4] * (1 - self.velocity_alpha) + vy * self.velocity_alpha
            self.state[5] = self.state[5] * (1 - self.velocity_alpha) + vz * self.velocity_alpha

        self.last_measurement_time = now
        self.last_measurement_pos = pos[:]

    def _predict(self, dt: float) -> None:
        x, y, z, vx, vy, vz = self.state

        self.state[0] = x + vx * dt
        self.state[1] = y + vy * dt
        self.state[2] = z + vz * dt

        q = self.process_noise
        for i in range(3):
            self.covariance[i * 7] += q * dt
            self.covariance[(i + 3) * 7] += q * 0.1

    def _update(self, z: list, obs_noise: float) -> None:
        x, y, z = self.state[0], self.state[1], self.state[2]

        y_vec = [z[0] - x, z[1] - y, z[2] - z]

        s = [
            self.covariance[0] + obs_noise,
            self.covariance[7] + obs_noise,
            self.covariance[14] + obs_noise,
        ]

        k = [
            self.covariance[0] / s[0] if s[0] > 0 else 0,
            self.covariance[7] / s[1] if s[1] > 0 else 0,
            self.covariance[14] / s[2] if s[2] > 0 else 0,
        ]

        self.state[0] += k[0] * y_vec[0]
        self.state[1] += k[1] * y_vec[1]
        self.state[2] += k[2] * y_vec[2]

        for i in range(3):
            self.covariance[i * 7] *= (1.0 - k[i])

    def _publish_fused(self) -> None:
        if not (self.referee_received or self.live_received):
            return

        msg = PoseStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = "fusion"

        msg.pose.position.x = self.state[0]
        msg.pose.position.y = self.state[1]
        msg.pose.position.z = self.state[2]

        vx, vy = self.state[3], self.state[4]
        heading = math.atan2(vy, vx) if (abs(vx) > 0.1 or abs(vy) > 0.1) else 0.0

        msg.pose.orientation.z = math.sin(heading / 2.0)
        msg.pose.orientation.w = math.cos(heading / 2.0)

        self.fused_pub.publish(msg)


def main(args=None) -> None:
    rclpy.init(args=args)
    node = EKFFusion()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
