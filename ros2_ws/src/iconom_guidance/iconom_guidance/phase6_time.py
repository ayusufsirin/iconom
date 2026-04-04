#!/usr/bin/env python3
from rclpy.node import Node


def now_sec(node: Node) -> float:
    return node.get_clock().now().nanoseconds * 1e-9
