#!/usr/bin/env python3
import os
import math
from collections import deque
from typing import Dict, Optional, List

import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy

from geometry_msgs.msg import PoseStamped
from std_msgs.msg import Header


RIVAL_STATE_TOPIC = "/competition/rival/state"
PREDICTION_TOPIC = "/competition/prediction/rival_position"

DEFAULT_BUFFER_SIZE = 60
DEFAULT_PREDICTION_HORIZON = 2.0


class Predictor(Node):
    def __init__(self):
        super().__init__("predictor")
        
        buffer_size = int(os.environ.get("PREDICTOR_BUFFER_SIZE", DEFAULT_BUFFER_SIZE))
        prediction_horizon = float(os.environ.get("PREDICTION_HORIZON", DEFAULT_PREDICTION_HORIZON))
        
        self.declare_parameter("buffer_size", buffer_size)
        self.declare_parameter("prediction_horizon", prediction_horizon)
        
        self.buffer_size = self.get_parameter("buffer_size").value
        self.prediction_horizon = self.get_parameter("prediction_horizon").value
        
        self.history_buffer: Dict[str, deque] = {}
        
        self.get_logger().info(f"predictor starting, buffer_size: {self.buffer_size}, horizon: {self.prediction_horizon}s")
        
        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        
        self.rival_sub = self.create_subscription(
            PoseStamped,
            RIVAL_STATE_TOPIC,
            self._handle_rival_state,
            qos,
        )
        
        self.prediction_pub = self.create_publisher(
            PoseStamped,
            PREDICTION_TOPIC,
            10,
        )
        
        self.timer = self.create_timer(0.5, self._publish_predictions)
        
        self.get_logger().info(f"subscribed to {RIVAL_STATE_TOPIC}")
        self.get_logger().info(f"predictions published to {PREDICTION_TOPIC}")

    def _handle_rival_state(self, msg: PoseStamped):
        rival_id = msg.header.frame_id
        current_time = self.get_clock().now().nanoseconds / 1e9
        
        if rival_id not in self.history_buffer:
            self.history_buffer[rival_id] = deque(maxlen=self.buffer_size)
        
        entry = {
            "timestamp": current_time,
            "position": {
                "x": msg.pose.position.x,
                "y": msg.pose.position.y,
                "z": msg.pose.position.z,
            },
            "orientation": {
                "x": msg.pose.orientation.x,
                "y": msg.pose.orientation.y,
                "z": msg.pose.orientation.z,
                "w": msg.pose.orientation.w,
            },
        }
        
        self.history_buffer[rival_id].append(entry)
        
        self.get_logger().debug(
            f"stored rival {rival_id}, buffer size: {len(self.history_buffer[rival_id])}"
        )

    def _estimate_velocity(self, buffer: deque) -> Optional[Dict[str, float]]:
        if len(buffer) < 2:
            return None
        
        newest = buffer[-1]
        oldest = buffer[0]
        
        dt = newest["timestamp"] - oldest["timestamp"]
        if dt < 0.01:
            return None
        
        vx = (newest["position"]["x"] - oldest["position"]["x"]) / dt
        vy = (newest["position"]["y"] - oldest["position"]["y"]) / dt
        vz = (newest["position"]["z"] - oldest["position"]["z"]) / dt
        
        return {"x": vx, "y": vy, "z": vz}

    def _compute_prediction(self, buffer: deque, current_time: float) -> Optional[Dict]:
        if buffer is None or len(buffer) < 2:
            return None
        
        velocity = self._estimate_velocity(buffer)
        if velocity is None:
            return None
        
        newest = buffer[-1]
        
        predicted_time = current_time + self.prediction_horizon
        
        predicted_position = {
            "x": newest["position"]["x"] + velocity["x"] * self.prediction_horizon,
            "y": newest["position"]["y"] + velocity["y"] * self.prediction_horizon,
            "z": newest["position"]["z"] + velocity["z"] * self.prediction_horizon,
        }
        
        return {
            "timestamp": predicted_time,
            "position": predicted_position,
            "velocity": velocity,
            "history_samples": len(buffer),
        }

    def _publish_predictions(self):
        current_time = self.get_clock().now().nanoseconds / 1e9
        
        for rival_id, buffer in self.history_buffer.items():
            prediction = self._compute_prediction(buffer, current_time)
            
            if prediction is None:
                continue
            
            msg = PoseStamped()
            msg.header = Header()
            msg.header.stamp = self.get_clock().now().to_msg()
            msg.header.frame_id = rival_id
            
            msg.pose.position.x = prediction["position"]["x"]
            msg.pose.position.y = prediction["position"]["y"]
            msg.pose.position.z = prediction["position"]["z"]
            
            velocity = prediction["velocity"]
            heading = math.atan2(velocity["y"], velocity["x"])
            msg.pose.orientation.x = 0.0
            msg.pose.orientation.y = 0.0
            msg.pose.orientation.z = math.sin(heading / 2.0)
            msg.pose.orientation.w = math.cos(heading / 2.0)
            
            self.prediction_pub.publish(msg)
            
            self.get_logger().debug(
                f"predicted rival {rival_id} at t+{self.prediction_horizon}s: "
                f"({prediction['position']['x']:.1f}, {prediction['position']['y']:.1f}, {prediction['position']['z']:.1f})"
            )


def main(args=None):
    rclpy.init(args=args)
    node = Predictor()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
