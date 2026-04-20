#!/usr/bin/env python3
"""
Bridge Gazebo world state to individual ROS pose topics.

Subscribes to /world/default/pose/info which publishes gz.msgs.Pose_V containing
all model poses in the world. Extracts poses for specific models and publishes
them to individual ROS topics.
"""

import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseStamped
from gz.msgs9 import Pose_V


class WorldStateBridge(Node):
    def __init__(self):
        super().__init__('world_state_bridge')
        
        # Declare parameters for model names
        self.declare_parameter('ownship_model_name', 'rc_cessna_0')
        self.declare_parameter('rival_model_name', 'rc_cessna_1')
        self.declare_parameter('world_state_topic', '/world/default/pose/info')
        
        ownship_model = self.get_parameter('ownship_model_name').get_parameter_value().string_value
        rival_model = self.get_parameter('rival_model_name').get_parameter_value().string_value
        world_state_topic = self.get_parameter('world_state_topic').get_parameter_value().string_value
        
        self.get_logger().info(f'World state bridge starting')
        self.get_logger().info(f'  Ownship model: {ownship_model}')
        self.get_logger().info(f'  Rival model: {rival_model}')
        self.get_logger().info(f'  World state topic: {world_state_topic}')
        
        # Create publishers for individual model poses
        self.ownship_pub = self.create_publisher(PoseStamped, '/competition/ownship/state', 10)
        self.rival_pub = self.create_publisher(PoseStamped, '/truth/rival/state', 10)
        
        # Subscribe to world state topic
        self.sub = self.create_subscription(
            Pose_V,
            world_state_topic,
            self.pose_v_callback,
            10
        )
        
        self.get_logger().info('World state bridge ready')
    
    def pose_v_callback(self, msg: Pose_V):
        """Extract poses for specific models and publish to individual topics."""
        for pose in msg.pose:
            model_name = pose.name
            
            # Create PoseStamped message
            pose_stamped = PoseStamped()
            pose_stamped.header.stamp = self.get_clock().now().to_msg()
            pose_stamped.header.frame_id = 'world'
            pose_stamped.pose.position.x = pose.position.x
            pose_stamped.pose.position.y = pose.position.y
            pose_stamped.pose.position.z = pose.position.z
            pose_stamped.pose.orientation.x = pose.orientation.x
            pose_stamped.pose.orientation.y = pose.orientation.y
            pose_stamped.pose.orientation.z = pose.orientation.z
            pose_stamped.pose.orientation.w = pose.orientation.w
            
            # Publish to appropriate topic
            if model_name == 'rc_cessna_0':
                self.ownship_pub.publish(pose_stamped)
            elif model_name == 'rc_cessna_1':
                self.rival_pub.publish(pose_stamped)


def main(args=None):
    rclpy.init(args=args)
    node = WorldStateBridge()
    
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
