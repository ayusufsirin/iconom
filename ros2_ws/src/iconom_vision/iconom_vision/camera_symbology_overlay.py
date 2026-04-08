#!/usr/bin/env python3
"""
Camera Symbology Overlay Node

Subscribes to camera image, camera info, ownship pose, and rival pose.
Projects rival 3D position to 2D image coordinates and overlays a marker.
Publishes the augmented image to /plane_01/camera/image_overlay.
"""
import cv2
import numpy as np

import rclpy
from cv_bridge import CvBridge
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from sensor_msgs.msg import CameraInfo, Image


IMAGE_TOPIC = "/plane_01/camera/image_raw"
CAMERA_INFO_TOPIC = "/plane_01/camera/camera_info"
RIVAL_STATE_TOPIC = "/fusion/rival/state"
OWNSHIP_STATE_TOPIC = "/competition/ownship/state"
OVERLAY_TOPIC = "/plane_01/camera/image_overlay"


class CameraSymbologyOverlay(Node):
    def __init__(self) -> None:
        super().__init__("camera_symbology_overlay")

        self.bridge = CvBridge()

        self.camera_info_msg: CameraInfo | None = None
        self.ownship_pose: PoseStamped | None = None
        self.rival_pose: PoseStamped | None = None

        self._log_counter = 0
        self._log_interval = 30

        self.image_sub = self.create_subscription(
            Image, IMAGE_TOPIC, self._handle_image, 10
        )
        self.camera_info_sub = self.create_subscription(
            CameraInfo, CAMERA_INFO_TOPIC, self._handle_camera_info, 10
        )
        self.rival_sub = self.create_subscription(
            PoseStamped, RIVAL_STATE_TOPIC, self._handle_rival, 10
        )
        self.ownship_sub = self.create_subscription(
            PoseStamped, OWNSHIP_STATE_TOPIC, self._handle_ownship, 10
        )

        self.overlay_pub = self.create_publisher(Image, OVERLAY_TOPIC, 10)

        self.get_logger().info(
            f"camera_symbology_overlay started: subscribing to {IMAGE_TOPIC}, "
            f"{CAMERA_INFO_TOPIC}, {RIVAL_STATE_TOPIC}, {OWNSHIP_STATE_TOPIC}; "
            f"publishing to {OVERLAY_TOPIC}"
        )

    def _handle_camera_info(self, msg: CameraInfo) -> None:
        if self.camera_info_msg is None:
            self.get_logger().info(f"received first camera_info: {msg.width}x{msg.height}")
        self.camera_info_msg = msg

    def _handle_ownship(self, msg: PoseStamped) -> None:
        if self.ownship_pose is None:
            self.get_logger().info(
                f"received first ownship_pose: "
                f"({msg.pose.position.x:.1f}, {msg.pose.position.y:.1f}, {msg.pose.position.z:.1f})"
            )
        self.ownship_pose = msg

    def _handle_rival(self, msg: PoseStamped) -> None:
        if self.rival_pose is None:
            self.get_logger().info(
                f"received first rival_pose: "
                f"({msg.pose.position.x:.1f}, {msg.pose.position.y:.1f}, {msg.pose.position.z:.1f})"
            )
        self.rival_pose = msg

    def _project_3d_to_2d(
        self, rival_pose: PoseStamped, ownship_pose: PoseStamped
    ) -> tuple[float, float] | None:
        if self.camera_info_msg is None:
            return None

        # K matrix from camera_info: [fx, 0, cx, 0, fy, cy, 0, 0, 1]
        k = self.camera_info_msg.k
        if len(k) < 9:
            return None

        fx, fy, cx, cy = k[0], k[4], k[2], k[5]

        # Relative position in world frame (NED: X=North, Y=East, Z=Down)
        dx = rival_pose.pose.position.x - ownship_pose.pose.position.x
        dy = rival_pose.pose.position.y - ownship_pose.pose.position.y
        dz = rival_pose.pose.position.z - ownship_pose.pose.position.z

        # Ownship orientation
        q = ownship_pose.pose.orientation
        qx, qy, qz, qw = q.x, q.y, q.z, q.w

        # Rotation matrix from body to world
        r11 = 1 - 2*(qy**2 + qz**2)
        r12 = 2*(qx*qy - qw*qz)
        r13 = 2*(qx*qz + qw*qy)
        
        r21 = 2*(qx*qy + qw*qz)
        r22 = 1 - 2*(qx**2 + qz**2)
        r23 = 2*(qy*qz - qw*qx)
        
        r31 = 2*(qx*qz - qw*qy)
        r32 = 2*(qy*qz + qw*qx)
        r33 = 1 - 2*(qx**2 + qy**2)

        # Transform relative position to body frame (FRD) using transpose of R
        v_body_x = r11*dx + r21*dy + r31*dz
        v_body_y = r12*dx + r22*dy + r32*dz
        v_body_z = r13*dx + r23*dy + r33*dz

        # Map FRD to camera optical frame (Z=Forward, X=Right, Y=Down)
        z_c = v_body_x  # Forward
        x_c = v_body_y  # Right
        y_c = v_body_z  # Down

        if z_c <= 0.1:
            return None

        u = fx * x_c / z_c + cx
        v = fy * y_c / z_c + cy

        return (u, v)

    def _handle_image(self, msg: Image) -> None:
        if self.camera_info_msg is None:
            self.get_logger().warn("dropping image: no camera_info yet")
            return

        try:
            cv_image = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        except Exception as e:
            self.get_logger().warn(f"cv_bridge conversion failed: {e}")
            return

        if cv_image is None:
            return
        overlay = cv_image.copy()
        h, w = overlay.shape[:2]

        if self.rival_pose is None or self.ownship_pose is None:
            self._log_counter += 1
            if self._log_counter % self._log_interval == 0:
                missing = []
                if self.rival_pose is None:
                    missing.append(f"rival_pose (subscribed to {RIVAL_STATE_TOPIC})")
                if self.ownship_pose is None:
                    missing.append(f"ownship_pose (subscribed to {OWNSHIP_STATE_TOPIC})")
                self.get_logger().warn(f"no marker: missing {', '.join(missing)}")
        else:
            projected = self._project_3d_to_2d(self.rival_pose, self.ownship_pose)
            if projected is None:
                self._log_counter += 1
                if self._log_counter % self._log_interval == 0:
                    if self.camera_info_msg is None:
                        self.get_logger().warn("no marker: no camera_info")
                    else:
                        dx = self.rival_pose.pose.position.x - self.ownship_pose.pose.position.x
                        dy = self.rival_pose.pose.position.y - self.ownship_pose.pose.position.y
                        dz = self.rival_pose.pose.position.z - self.ownship_pose.pose.position.z
                        q = self.ownship_pose.pose.orientation
                        qx, qy, qz, qw = q.x, q.y, q.z, q.w
                        r11, r21, r31 = 1 - 2*(qy**2 + qz**2), 2*(qx*qy + qw*qz), 2*(qx*qz - qw*qy)
                        z_c = r11*dx + r21*dy + r31*dz
                        
                        self.get_logger().warn(
                            f"no marker: projection failed (z_c={z_c:.2f} <= 0.1, rival behind or too close)"
                        )
            else:
                u, v = projected
                if 0 <= u <= w and 0 <= v <= h:
                    self._draw_rival_marker(overlay, int(u), int(v))
                    self._log_counter += 1
                    if self._log_counter % self._log_interval == 0:
                        self.get_logger().info(
                            f"drawing marker at ({int(u)}, {int(v)}) - "
                            f"rival delta: ({self.rival_pose.pose.position.x - self.ownship_pose.pose.position.x:.1f}, "
                            f"{self.rival_pose.pose.position.y - self.ownship_pose.pose.position.y:.1f}, "
                            f"{self.rival_pose.pose.position.z - self.ownship_pose.pose.position.z:.1f})"
                        )
                else:
                    self._log_counter += 1
                    if self._log_counter % self._log_interval == 0:
                        self.get_logger().warn(
                            f"no marker: projected ({u:.0f}, {v:.0f}) outside image bounds (0-{w}, 0-{h})"
                        )

        try:
            overlay_msg = self.bridge.cv2_to_imgmsg(overlay, encoding="bgr8")
            overlay_msg.header.stamp = msg.header.stamp
            overlay_msg.header.frame_id = msg.header.frame_id
            self.overlay_pub.publish(overlay_msg)
        except Exception as e:
            self.get_logger().warn(f"failed to publish overlay: {e}")

    def _draw_rival_marker(self, overlay: np.ndarray, u: int, v: int) -> None:
        color = (0, 255, 0)
        thickness = 2
        radius = 20

        cv2.circle(overlay, (u, v), radius, color, thickness)
        cv2.line(overlay, (u - 30, v), (u + 30, v), color, thickness)
        cv2.line(overlay, (u, v - 30), (u, v + 30), color, thickness)
        cv2.putText(
            overlay,
            "RIVAL",
            (u + 25, v - 25),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            color,
            2,
        )


def main() -> int:
    rclpy.init()
    node = CameraSymbologyOverlay()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())