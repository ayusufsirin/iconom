#!/usr/bin/env python3
import os
import math
import rclpy
from rclpy.node import Node
import requests
import threading
import time

from px4_msgs.msg import VehicleLocalPosition
from geometry_msgs.msg import PoseStamped
from std_msgs.msg import Header


REF_HOST = os.environ.get("REF_HOST", "localhost")
REF_PORT = int(os.environ.get("REF_PORT", "45678"))
REF_BASE_URL = f"http://{REF_HOST}:{REF_PORT}"

AIRCRAFT_ID = os.environ.get("AIRCRAFT_ID", "plane_01")
TELEMETRY_INTERVAL = 1.0


class OwnshipTelemetryAdapter(Node):
    def __init__(self):
        super().__init__("ownship_telemetry_adapter")
        
        self.declare_parameter("ref_host", REF_HOST)
        self.declare_parameter("ref_port", REF_PORT)
        self.declare_parameter("aircraft_id", AIRCRAFT_ID)
        
        self.ref_host = self.get_parameter("ref_host").value
        self.ref_port = self.get_parameter("ref_port").value
        self.ref_base_url = f"http://{self.ref_host}:{self.ref_port}"
        self.aircraft_id = self.get_parameter("aircraft_id").value
        
        self.local_position_topic = f"/{self.aircraft_id}/fmu/out/vehicle_local_position"

        self.ownship_state_pub = self.create_publisher(
            PoseStamped, "/competition/ownship/state", 10)
        
        self.latest_position = None
        self.latest_velocity = None
        self.session_token = None
        
        self.get_logger().info(f"ownship telemetry adapter starting, aircraft: {self.aircraft_id}")
        self.get_logger().info(f"subscribing to {self.local_position_topic}, referee at {self.ref_base_url}")
        
        from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )
        self.position_sub = self.create_subscription(
            VehicleLocalPosition,
            self.local_position_topic,
            self._handle_position,
            qos,
        )
        
        self._authenticate()
        self._start_telemetry_loop()

    def _authenticate(self):
        url = f"{self.ref_base_url}/login"
        credentials = {"username": "test_pilot", "password": "test_pass_123"}
        try:
            response = requests.post(url, json=credentials, timeout=5)
            if response.status_code == 200:
                data = response.json()
                self.session_token = data.get("token")
                self.get_logger().info(f"authenticated with referee, token: {self.session_token}")
            else:
                self.get_logger().error(f"auth failed: {response.status_code}")
        except Exception as e:
            self.get_logger().error(f"auth error: {e}")

    def _handle_position(self, msg: VehicleLocalPosition):
        self.latest_position = {
            "x": float(msg.x),
            "y": float(msg.y),
            "z": float(msg.z),
        }
        self.latest_velocity = {
            "x": float(msg.vx),
            "y": float(msg.vy),
            "z": float(msg.vz),
        }
        # Guidance needs fresh ownship state; keep this on the PX4 local-position cadence
        # even though server telemetry remains deliberately slower.
        self._publish_ownship_state()

    def _compute_heading(self):
        if self.latest_velocity:
            vx = self.latest_velocity.get("x", 0.0)
            vy = self.latest_velocity.get("y", 0.0)
            if abs(vx) > 0.1 or abs(vy) > 0.1:
                return math.atan2(vy, vx)
        return 0.0

    def _build_telemetry_payload(self):
        if not self.latest_position:
            return None
        
        heading = self._compute_heading()
        
        return {
            "aircraft_id": self.aircraft_id,
            "position": self.latest_position,
            "velocity": self.latest_velocity or {"x": 0.0, "y": 0.0, "z": 0.0},
            "heading": heading,
        }

    def _publish_ownship_state(self):
        if not self.latest_position:
            return
        
        msg = PoseStamped()
        msg.header = Header()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = self.aircraft_id
        
        msg.pose.position.x = self.latest_position["x"]
        msg.pose.position.y = self.latest_position["y"]
        msg.pose.position.z = self.latest_position["z"]
        
        heading = self._compute_heading()
        msg.pose.orientation.x = 0.0
        msg.pose.orientation.y = 0.0
        msg.pose.orientation.z = math.sin(heading / 2.0)
        msg.pose.orientation.w = math.cos(heading / 2.0)
        
        self.ownship_state_pub.publish(msg)

    def _send_telemetry(self):
        if not self.session_token:
            self.get_logger().warn("no session token, skipping telemetry")
            return None
        
        payload = self._build_telemetry_payload()
        if not payload:
            return None
        
        url = f"{self.ref_base_url}/telemetry"
        try:
            response = requests.post(url, json=payload, timeout=5)
            if response.status_code == 200:
                data = response.json()
                rival_state = data.get("rival_state", {})
                self.get_logger().info(f"telemetry sent, received rival: {rival_state.get('aircraft_id')}")
                return rival_state
            else:
                self.get_logger().error(f"telemetry failed: {response.status_code}")
                return None
        except Exception as e:
            self.get_logger().error(f"telemetry error: {e}")
            return None

    def _start_telemetry_loop(self):
        def loop():
            while rclpy.ok():
                self._send_telemetry()
                time.sleep(TELEMETRY_INTERVAL)
        
        thread = threading.Thread(target=loop, daemon=True)
        thread.start()


def main(args=None):
    rclpy.init(args=args)
    node = OwnshipTelemetryAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
