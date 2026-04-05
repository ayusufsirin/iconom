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


# Topic names for separate sources
REFEREE_STATE_TOPIC = "/competition/rival/state/referee"
LIVE_STATE_TOPIC = "/competition/rival/state/live"
FUSED_STATE_TOPIC = "/fusion/rival/state"


class EKFFusion(Node):
    """Extended Kalman Filter for rival state fusion."""

    def __init__(self) -> None:
        super().__init__("ekf_fusion")

        # EKF parameters
        self.declare_parameter("process_noise", 0.1)
        self.declare_parameter("observation_noise_referee", 0.05)
        self.declare_parameter("observation_noise_live", 0.3)
        self.declare_parameter("publish_rate_hz", 20.0)
        self.declare_parameter("initial_covariance", 1.0)

        self.process_noise = float(self.get_parameter("process_noise").value)
        self.obs_noise_referee = float(self.get_parameter("observation_noise_referee").value)
        self.obs_noise_live = float(self.get_parameter("observation_noise_live").value)
        self.publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        self.initial_cov = float(self.get_parameter("initial_covariance").value)

        # State vector: [x, y, z, vx, vy, vz]
        self.state = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        self.covariance = [
            self.initial_cov, 0, 0, 0, 0, 0,
            0, self.initial_cov, 0, 0, 0, 0,
            0, 0, self.initial_cov, 0, 0, 0,
            0, 0, 0, self.initial_cov, 0, 0,
            0, 0, 0, 0, self.initial_cov, 0,
            0, 0, 0, 0, 0, self.initial_cov,
        ]

        self.last_referee_update: Optional[float] = None
        self.last_live_update: Optional[float] = None
        self.last_predict_time: Optional[float] = None

        # Track which sources we've received
        self.referee_received = False
        self.live_received = False

        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        # Subscriptions
        self.referee_sub = self.create_subscription(
            PoseStamped,
            "/competition/rival/state",
            self._handle_referee,
            qos,
        )
        self.live_sub = self.create_subscription(
            PoseStamped,
            LIVE_STATE_TOPIC,
            self._handle_live,
            qos,
        )

        # Publisher
        self.fused_pub = self.create_publisher(PoseStamped, FUSED_STATE_TOPIC, 10)

        self.timer = self.create_timer(1.0 / self.publish_rate_hz, self._publish_fused)

        self.get_logger().info(
            f"EKF fusion started: process_noise={self.process_noise}, "
            f"referee_noise={self.obs_noise_referee}, live_noise={self.obs_noise_live}"
        )

    def _handle_referee(self, msg: PoseStamped) -> None:
        """Handle referee update (1 Hz, accurate)."""
        self._update_from_measurement(msg, is_referee=True)

    def _handle_live(self, msg: PoseStamped) -> None:
        """Handle live adapter update (20 Hz, mock camera)."""
        self._update_from_measurement(msg, is_referee=False)

    def _update_from_measurement(self, msg: PoseStamped, is_referee: bool) -> None:
        """Process measurement update for EKF."""
        now = self.get_clock().now().nanoseconds / 1e9

        # Initialize state on first measurement
        if not self.referee_received and not self.live_received:
            self.state[0] = msg.pose.position.x
            self.state[1] = msg.pose.position.y
            self.state[2] = msg.pose.position.z
            self.last_predict_time = now

        # Update timestamps
        if is_referee:
            self.last_referee_update = now
            self.referee_received = True
        else:
            self.last_live_update = now
            self.live_received = True

        # Run prediction first if needed
        if self.last_predict_time is not None:
            dt = now - self.last_predict_time
            if dt > 0.001:
                self._predict(dt)

        # Measurement update
        z = [
            msg.pose.position.x,
            msg.pose.position.y,
            msg.pose.position.z,
        ]
        obs_noise = self.obs_noise_referee if is_referee else self.obs_noise_live
        self._update(z, obs_noise)

        self.last_predict_time = now

    def _predict(self, dt: float) -> None:
        """Prediction step: constant velocity model."""
        # State transition matrix F for constant velocity
        # x_new = x + vx * dt
        # vx_new = vx (no acceleration model)

        x, y, z, vx, vy, vz = self.state

        # Predict state
        self.state[0] = x + vx * dt
        self.state[1] = y + vy * dt
        self.state[2] = z + vz * dt
        # velocities unchanged in CV model

        # Covariance prediction: P = F * P * F' + Q
        # For CV model, F = [[I_3x3, dt*I_3x3], [0, I_3x3]]
        q = self.process_noise

        # Update covariance (simplified)
        for i in range(3):
            self.covariance[i * 7] += q * dt  # position variance grows
            self.covariance[(i + 3) * 7] += q * 0.01  # velocity variance

    def _update(self, z: list, obs_noise: float) -> None:
        """Update step: incorporate measurement."""
        # Measurement matrix H (we measure position only)
        # z = H * x + noise, where H = [I_3x3, 0_3x3]

        x, y, z = self.state[0], self.state[1], self.state[2]

        # Innovation (measurement residual)
        y_vec = [
            z[0] - x,
            z[1] - y,
            z[2] - z,
        ]

        # Innovation covariance: S = H * P * H' + R
        s = [
            self.covariance[0] + obs_noise,  # Pxx + R
            self.covariance[7] + obs_noise,   # Pyy + R
            self.covariance[14] + obs_noise,  # Pzz + R
        ]

        # Kalman gain: K = P * H' * S^(-1)
        # Only updating position states
        k = [
            self.covariance[0] / s[0] if s[0] > 0 else 0,
            self.covariance[7] / s[1] if s[1] > 0 else 0,
            self.covariance[14] / s[2] if s[2] > 0 else 0,
        ]

        # Update state: x = x + K * y
        self.state[0] += k[0] * y_vec[0]
        self.state[1] += k[1] * y_vec[1]
        self.state[2] += k[2] * y_vec[2]

        # Update covariance: P = (I - K*H) * P
        for i in range(3):
            self.covariance[i * 7] *= (1.0 - k[i])

    def _publish_fused(self) -> None:
        """Publish fused state."""
        if not (self.referee_received or self.live_received):
            return

        msg = PoseStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = "fusion"

        msg.pose.position.x = self.state[0]
        msg.pose.position.y = self.state[1]
        msg.pose.position.z = self.state[2]

        # Compute heading from velocity
        vx, vy = self.state[3], self.state[4]
        heading = math.atan2(vy, vx) if (abs(vx) > 0.1 or abs(vy) > 0.1) else 0.0

        # Convert heading to quaternion
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
