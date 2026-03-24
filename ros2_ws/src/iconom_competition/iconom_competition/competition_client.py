#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
import requests
import json
import threading
import time

from geometry_msgs.msg import PoseStamped, TwistStamped
from std_msgs.msg import Header


REF_HOST = "localhost"
REF_PORT = 45678
REF_BASE_URL = f"http://{REF_HOST}:{REF_PORT}"

FIXTURE_CREDENTIALS = {"username": "test_pilot", "password": "test_pass_123"}
FIXTURE_TELEMETRY = {
    "aircraft_id": "plane_01",
    "position": {"x": 0.0, "y": 0.0, "z": 10.0},
    "velocity": {"x": 5.0, "y": 0.0, "z": 0.0},
    "heading": 0.0
}


class CompetitionClient(Node):
    def __init__(self):
        super().__init__("competition_client")
        
        self.declare_parameter("ref_host", REF_HOST)
        self.declare_parameter("ref_port", REF_PORT)
        
        self.ref_host = self.get_parameter("ref_host").value
        self.ref_port = self.get_parameter("ref_port").value
        self.ref_base_url = f"http://{self.ref_host}:{self.ref_port}"
        
        self.rival_state_pub = self.create_publisher(
            PoseStamped, "/competition/rival/state", 10)
        self.ownship_state_pub = self.create_publisher(
            PoseStamped, "/competition/ownship/state", 10)
        
        self.session_token = None
        self.server_time = None
        
        self.get_logger().info(f"competition client starting, referee at {self.ref_base_url}")
        
        self.authenticate()
        self.fetch_server_time()
        self.start_telemetry_loop()

    def authenticate(self):
        url = f"{self.ref_base_url}/login"
        try:
            response = requests.post(url, json=FIXTURE_CREDENTIALS, timeout=5)
            if response.status_code == 200:
                data = response.json()
                self.session_token = data.get("token")
                self.get_logger().info(f"authenticated, token: {self.session_token}")
            else:
                self.get_logger().error(f"auth failed: {response.status_code}")
        except Exception as e:
            self.get_logger().error(f"auth error: {e}")

    def fetch_server_time(self):
        url = f"{self.ref_base_url}/time"
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                self.server_time = data.get("server_time")
                self.get_logger().info(f"server time: {self.server_time}")
            else:
                self.get_logger().error(f"time fetch failed: {response.status_code}")
        except Exception as e:
            self.get_logger().error(f"time error: {e}")

    def send_telemetry(self):
        if not self.session_token:
            self.get_logger().warn("no session token, skipping telemetry")
            return None
            
        url = f"{self.ref_base_url}/telemetry"
        try:
            response = requests.post(url, json=FIXTURE_TELEMETRY, timeout=5)
            if response.status_code == 200:
                data = response.json()
                rival_state = data.get("rival_state", {})
                self.get_logger().info(f"telemetry sent, rival: {rival_state.get('aircraft_id')}")
                return rival_state
            else:
                self.get_logger().error(f"telemetry failed: {response.status_code}")
                return None
        except Exception as e:
            self.get_logger().error(f"telemetry error: {e}")
            return None

    def publish_rival_state(self, rival_state):
        if not rival_state:
            return
            
        msg = PoseStamped()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = rival_state.get("aircraft_id", "rival")
        
        pos = rival_state.get("position", {})
        msg.pose.position.x = pos.get("x", 0.0)
        msg.pose.position.y = pos.get("y", 0.0)
        msg.pose.position.z = pos.get("z", 0.0)
        
        heading = rival_state.get("heading", 0.0)
        import math
        msg.pose.orientation.x = 0.0
        msg.pose.orientation.y = 0.0
        msg.pose.orientation.z = math.sin(heading / 2.0)
        msg.pose.orientation.w = math.cos(heading / 2.0)
        
        self.rival_state_pub.publish(msg)

    def publish_ownship_state(self):
        msg = PoseStamped()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = "plane_01"
        
        msg.pose.position.x = FIXTURE_TELEMETRY["position"]["x"]
        msg.pose.position.y = FIXTURE_TELEMETRY["position"]["y"]
        msg.pose.position.z = FIXTURE_TELEMETRY["position"]["z"]
        
        heading = FIXTURE_TELEMETRY["heading"]
        import math
        msg.pose.orientation.x = 0.0
        msg.pose.orientation.y = 0.0
        msg.pose.orientation.z = math.sin(heading / 2.0)
        msg.pose.orientation.w = math.cos(heading / 2.0)
        
        self.ownship_state_pub.publish(msg)

    def start_telemetry_loop(self):
        def loop():
            while rclpy.ok():
                rival_state = self.send_telemetry()
                if rival_state:
                    self.publish_rival_state(rival_state)
                self.publish_ownship_state()
                time.sleep(1.0)
        
        thread = threading.Thread(target=loop, daemon=True)
        thread.start()


def main(args=None):
    rclpy.init(args=args)
    node = CompetitionClient()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
