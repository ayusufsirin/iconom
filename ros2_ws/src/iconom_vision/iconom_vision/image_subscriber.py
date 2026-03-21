#!/usr/bin/env python3
import os
import sys
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image


class ImageSubscriber(Node):
    def __init__(self) -> None:
        super().__init__("iconom_image_subscriber")
        self.topic = os.environ.get("CAMERA_TOPIC", "/plane_01/camera/image_raw")
        self.timeout_sec = float(os.environ.get("IMAGE_SUBSCRIBER_TIMEOUT_SEC", "20"))
        self.start_time = time.monotonic()
        self.received = False
        self.failed = False

        self.subscription = self.create_subscription(
            Image,
            self.topic,
            self._handle_image,
            qos_profile_sensor_data,
        )
        self.timer = self.create_timer(0.5, self._check_timeout)

        self.get_logger().info(
            f"waiting for first image on {self.topic} with timeout {self.timeout_sec:.1f}s"
        )

    def _handle_image(self, message: Image) -> None:
        if self.received:
            return

        self.received = True
        self.get_logger().info(
            "received image "
            f"{message.width}x{message.height} "
            f"encoding={message.encoding or 'unknown'} "
            f"frame_id={message.header.frame_id or 'unset'}"
        )

    def _check_timeout(self) -> None:
        if self.received or self.failed:
            return

        if time.monotonic() - self.start_time >= self.timeout_sec:
            self.failed = True
            self.get_logger().error(f"timed out waiting for image on {self.topic}")


def main() -> int:
    rclpy.init()
    node = ImageSubscriber()

    try:
        while rclpy.ok() and not node.received and not node.failed:
            rclpy.spin_once(node, timeout_sec=0.5)
    finally:
        exit_code = 0 if node.received and not node.failed else 1
        node.destroy_node()
        rclpy.shutdown()

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
