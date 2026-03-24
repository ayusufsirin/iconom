#!/usr/bin/env python3
import os
import time
from collections import deque
from typing import Dict

import rclpy
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy

from geometry_msgs.msg import PoseStamped, PoseArray
from std_msgs.msg import Header, Float64MultiArray


RIVAL_STATE_TOPIC = "/competition/rival/state"
HISTORY_PUBLISH_TOPIC = "/rival_buffer/history"

DEFAULT_BUFFER_SIZE = 60


class RivalHistoryBuffer(Node):
    def __init__(self):
        super().__init__("rival_history_buffer")
        
        buffer_size = int(os.environ.get("RIVAL_BUFFER_SIZE", DEFAULT_BUFFER_SIZE))
        
        self.declare_parameter("buffer_size", buffer_size)
        self.buffer_size = self.get_parameter("buffer_size").value
        
        self.history_buffer: Dict[str, deque] = {}
        
        self.get_logger().info(f"rival history buffer starting, buffer_size: {self.buffer_size}")
        
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
        
        self.history_pub = self.create_publisher(
            PoseArray,
            HISTORY_PUBLISH_TOPIC,
            10,
        )
        
        self.timer = self.create_timer(1.0, self._publish_history)
        
        self.get_logger().info(f"subscribed to {RIVAL_STATE_TOPIC}")
        self.get_logger().info(f"history published to {HISTORY_PUBLISH_TOPIC}")

    def _handle_rival_state(self, msg: PoseStamped):
        rival_id = msg.header.frame_id
        
        if rival_id not in self.history_buffer:
            self.history_buffer[rival_id] = deque(maxlen=self.buffer_size)
        
        entry = {
            "timestamp": self.get_clock().now().nanoseconds / 1e9,
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
            f"stored rival {rival_id} snapshot, buffer size: {len(self.history_buffer[rival_id])}"
        )

    def _publish_history(self):
        for rival_id, buffer in self.history_buffer.items():
            if buffer is None or len(buffer) == 0:
                continue
            
            msg = PoseArray()
            msg.header = Header()
            msg.header.stamp = self.get_clock().now().to_msg()
            msg.header.frame_id = rival_id
            
            for entry in buffer:
                from geometry_msgs.msg import Pose
                pose = Pose()
                pose.position.x = entry["position"]["x"]
                pose.position.y = entry["position"]["y"]
                pose.position.z = entry["position"]["z"]
                pose.orientation.x = entry["orientation"]["x"]
                pose.orientation.y = entry["orientation"]["y"]
                pose.orientation.z = entry["orientation"]["z"]
                pose.orientation.w = entry["orientation"]["w"]
                msg.poses.append(pose)
            
            self.history_pub.publish(msg)
            
            self.get_logger().debug(
                f"published {len(buffer)} history samples for {rival_id}"
            )

    def get_history_summary(self, rival_id: str) -> Dict:
        if rival_id not in self.history_buffer or len(self.history_buffer[rival_id]) == 0:
            return {
                "success": False,
                "sample_count": 0,
                "oldest_timestamp": 0.0,
                "newest_timestamp": 0.0,
            }
        
        buffer = self.history_buffer[rival_id]
        return {
            "success": True,
            "sample_count": len(buffer),
            "oldest_timestamp": buffer[0]["timestamp"],
            "newest_timestamp": buffer[-1]["timestamp"],
            "time_span": buffer[-1]["timestamp"] - buffer[0]["timestamp"],
        }


def main(args=None):
    rclpy.init(args=args)
    node = RivalHistoryBuffer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
