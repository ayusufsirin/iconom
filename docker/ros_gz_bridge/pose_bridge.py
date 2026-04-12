#!/usr/bin/env python3
import subprocess
import re
import sys
import rclpy
from rclpy.node import Node
from geometry_msgs.msg import PoseStamped

class GzWorldStateBridge(Node):
    def __init__(self):
        super().__init__('gz_world_state_bridge')
        self.ownship_pub = self.create_publisher(PoseStamped, '/competition/ownship/state', 10)
        self.rival_pub = self.create_publisher(PoseStamped, '/fusion/rival/state', 10)
        self.get_logger().info('GZ world state bridge started')
    
    def run(self):
        cmd = ['gz', 'topic', '-e', '-t', '/world/default/pose/info']
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=1)
        
        msg_count = 0
        published = 0
        buffer = []
        
        while True:
            line = proc.stdout.readline()
            if not line:
                if buffer:
                    data = ''.join(buffer)
                    self.parse_and_publish(data)
                self.get_logger().info('Subprocess ended')
                break
            if line.strip() == '':
                if buffer:
                    msg_count += 1
                    data = ''.join(buffer)
                    count = self.parse_and_publish(data)
                    published += count
                    if msg_count % 10 == 0:
                        self.get_logger().info(f'Processed {msg_count} msgs, published {published} poses')
                    buffer = []
            else:
                buffer.append(line.decode('utf-8'))
        
        self.get_logger().info(f'GZ topic reader exiting, processed {msg_count} messages, {published} poses')
        proc.terminate()
    
    def parse_and_publish(self, data):
        count = 0
        
        name_pattern = re.compile(r'name:\s*"([^"]+)"')
        num_pattern = re.compile(r'position\s*\{([^}]+)\}')
        coord_pattern = re.compile(r'([xyz]):\s*([-\d.e]+)')
        
        blocks = data.split('pose {')
        for block in blocks[1:]:
            name_match = name_pattern.search(block)
            if not name_match:
                continue
            name = name_match.group(1)
            if name not in ('rc_cessna_0', 'rc_cessna_1'):
                continue
            
            pos_match = num_pattern.search(block)
            if not pos_match:
                continue
            
            x = y = z = 0.0
            for coord_match in coord_pattern.finditer(pos_match.group(1)):
                val = float(coord_match.group(2))
                if coord_match.group(1) == 'x':
                    x = val
                elif coord_match.group(1) == 'y':
                    y = val
                elif coord_match.group(1) == 'z':
                    z = val
            
            self.publish_pose(name, x, y, z)
            count += 1
        
        return count
    
    def publish_pose(self, model_name, x, y, z):
        pose = PoseStamped()
        pose.header.stamp = self.get_clock().now().to_msg()
        pose.header.frame_id = 'world'
        pose.pose.position.x = x
        pose.pose.position.y = y
        pose.pose.position.z = z
        pose.pose.orientation.w = 1.0
        
        if model_name == 'rc_cessna_0':
            self.ownship_pub.publish(pose)
        elif model_name == 'rc_cessna_1':
            self.rival_pub.publish(pose)

def main():
    print('Starting GZ world state bridge...', file=sys.stderr)
    rclpy.init(args=sys.argv)
    node = GzWorldStateBridge()
    node.run()
    node.destroy_node()

if __name__ == '__main__':
    main()
