#!/usr/bin/env python3
from __future__ import annotations

# pyright: reportAny=false, reportExplicitAny=false, reportMissingImports=false, reportMissingTypeStubs=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false, reportUnknownParameterType=false, reportMissingParameterType=false, reportUnusedFunction=false, reportUnannotatedClassAttribute=false, reportPossiblyUnboundVariable=false, reportMissingTypeArgument=false, reportUnusedImport=false, reportGeneralTypeIssues=false, reportIndexIssue=false, reportAttributeAccessIssue=false, reportImplicitStringConcatenation=false, reportUntypedBaseClass=false, reportUnusedCallResult=false, reportUnusedParameter=false

import rclpy
from geometry_msgs.msg import PoseStamped
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo
from visualization_msgs.msg import Marker, MarkerArray
import tf2_ros
from tf2_geometry_msgs import do_transform_pose

from .position_estimator_constants import RIVAL_HEIGHT_M, RIVAL_WINGSPAN_M


class PositionEstimator(Node):
    def __init__(self) -> None:
        super().__init__("position_estimator")

        self.declare_parameter("detections_topic", "/vision/detections")
        self.declare_parameter("camera_info_topic", "/plane_01/camera/camera_info")
        self.declare_parameter("ownship_topic", "/competition/ownship/state")
        self.declare_parameter("rival_pose_topic", "/vision/rival_pose")
        self.declare_parameter("max_staleness_s", 1.0)

        self.detections_topic = str(self.get_parameter("detections_topic").value)
        self.camera_info_topic = str(self.get_parameter("camera_info_topic").value)
        self.ownship_topic = str(self.get_parameter("ownship_topic").value)
        self.rival_pose_topic = str(self.get_parameter("rival_pose_topic").value)
        self.max_staleness_s = float(self.get_parameter("max_staleness_s").value)

        self.camera_info_msg: CameraInfo | None = None
        self.ownship_pose_msg: PoseStamped | None = None
        self.tf_buffer = tf2_ros.Buffer()
        self.tf_listener = tf2_ros.TransformListener(self.tf_buffer, self)

        self._warning_count = 0
        self._warn_interval = 30

        self.detections_sub = self.create_subscription(
            MarkerArray,
            self.detections_topic,
            self._handle_detections,
            qos_profile_sensor_data,
        )
        self.camera_info_sub = self.create_subscription(
            CameraInfo,
            self.camera_info_topic,
            self._handle_camera_info,
            qos_profile_sensor_data,
        )
        self.ownship_sub = self.create_subscription(
            PoseStamped,
            self.ownship_topic,
            self._handle_ownship,
            qos_profile_sensor_data,
        )

        self.rival_pose_pub = self.create_publisher(PoseStamped, self.rival_pose_topic, 10)

        self.get_logger().info(
            f"position_estimator started: subscribing to {self.detections_topic}, "
            f"{self.camera_info_topic}, {self.ownship_topic}; "
            f"publishing to {self.rival_pose_topic}; max_staleness_s={self.max_staleness_s:.2f}"
        )

    def _handle_camera_info(self, msg: CameraInfo) -> None:
        if self.camera_info_msg is None:
            self.get_logger().info(f"received first camera_info: {msg.width}x{msg.height}")
        self.camera_info_msg = msg

    def _handle_ownship(self, msg: PoseStamped) -> None:
        if self.ownship_pose_msg is None:
            self.get_logger().info(
                f"received first ownship_pose: "
                f"({msg.pose.position.x:.1f}, {msg.pose.position.y:.1f}, {msg.pose.position.z:.1f})"
            )
        self.ownship_pose_msg = msg

    def _handle_detections(self, msg: MarkerArray) -> None:
        if not msg.markers:
            return

        if self.camera_info_msg is None:
            self._warn_bounded("dropping detections: no camera_info yet")
            return
        if self.ownship_pose_msg is None:
            self._warn_bounded("dropping detections: no ownship pose yet")
            return
        if not self.tf_buffer.can_transform(
            "world",
            self.camera_info_msg.header.frame_id,
            rclpy.time.Time(),
            timeout=rclpy.duration.Duration(seconds=0.5),
        ):
            self._warn_bounded("dropping detections: TF world frame not available yet")
            return

        measurement = self._extract_bbox_measurement(msg)
        if measurement is None:
            return

        center_u, center_v, bbox_width_px, bbox_height_px, detection_stamp = measurement
        reference_time_s = self._stamp_seconds(detection_stamp)
        if reference_time_s is None:
            reference_time_s = self._now_seconds()

        if self._is_stale(self.camera_info_msg, reference_time_s):
            self._warn_bounded("dropping detections: camera_info is stale")
            return
        if self._is_stale(self.ownship_pose_msg, reference_time_s):
            self._warn_bounded("dropping detections: ownship pose is stale")
            return

        depth_m = self._estimate_depth_m(
            bbox_width_px=bbox_width_px,
            bbox_height_px=bbox_height_px,
            camera_info=self.camera_info_msg,
        )
        if depth_m is None:
            self._warn_bounded("dropping detections: invalid camera intrinsics or bbox dimensions")
            return

        estimated_pose = self._project_measurement_to_world_pose(
            center_u=center_u,
            center_v=center_v,
            depth_m=depth_m,
            camera_info=self.camera_info_msg,
            ownship_pose=self.ownship_pose_msg,
            out_stamp=detection_stamp,
        )
        if estimated_pose is None:
            self._warn_bounded("dropping detections: failed to project measurement")
            return

        self.rival_pose_pub.publish(estimated_pose)

    def _estimate_depth_m(
        self,
        *,
        bbox_width_px: float,
        bbox_height_px: float,
        camera_info: CameraInfo,
    ) -> float | None:
        if bbox_width_px <= 0.0 or bbox_height_px <= 0.0:
            return None
        if len(camera_info.k) < 9:
            return None

        fx = float(camera_info.k[0])
        fy = float(camera_info.k[4])
        if fx <= 0.0 or fy <= 0.0:
            return None

        depth_from_width = fx * RIVAL_WINGSPAN_M / bbox_width_px
        depth_from_height = fy * RIVAL_HEIGHT_M / bbox_height_px
        return (depth_from_width + depth_from_height) / 2.0

    def _project_measurement_to_world_pose(
        self,
        *,
        center_u: float,
        center_v: float,
        depth_m: float,
        camera_info: CameraInfo,
        ownship_pose: PoseStamped,
        out_stamp,
    ) -> PoseStamped | None:
        if depth_m <= 0.0:
            return None
        if len(camera_info.k) < 9:
            return None

        fx = float(camera_info.k[0])
        fy = float(camera_info.k[4])
        cx = float(camera_info.k[2])
        cy = float(camera_info.k[5])
        if fx <= 0.0 or fy <= 0.0:
            return None

        lateral_m = (center_u - cx) * depth_m / fx
        vertical_m = (center_v - cy) * depth_m / fy

        camera_pose = PoseStamped()
        camera_pose.header.frame_id = camera_info.header.frame_id
        camera_pose.header.stamp = out_stamp if self._stamp_is_set(out_stamp) else self.get_clock().now().to_msg()
        camera_pose.pose.position.x = depth_m
        camera_pose.pose.position.y = lateral_m
        camera_pose.pose.position.z = vertical_m
        camera_pose.pose.orientation.w = 1.0

        try:
            transform = self.tf_buffer.lookup_transform(
                "world",
                camera_info.header.frame_id,
                rclpy.time.Time()
            )
            world_pose = do_transform_pose(camera_pose, transform)
            return world_pose
        except (tf2_ros.LookupException, tf2_ros.ConnectivityException, tf2_ros.ExtrapolationException) as e:
            self._warn_bounded(f"TF lookup failed: {e}")
            return None

    def _extract_bbox_measurement(
        self, marker_array: MarkerArray
    ) -> tuple[float, float, float, float, object] | None:
        markers = marker_array.markers or []
        for marker in markers:
            if marker.action != Marker.ADD:
                continue
            return (
                float(marker.pose.position.x),
                float(marker.pose.position.y),
                float(marker.scale.x),
                float(marker.scale.y),
                marker.header.stamp,
            )
        return None

    def _is_stale(self, msg, now_s: float) -> bool:
        stamp = msg.header.stamp
        stamp_s = float(stamp.sec) + float(stamp.nanosec) * 1e-9
        return (now_s - stamp_s) > self.max_staleness_s

    def _stamp_is_set(self, stamp) -> bool:
        return bool(stamp is not None and (int(stamp.sec) != 0 or int(stamp.nanosec) != 0))

    def _stamp_seconds(self, stamp) -> float | None:
        if not self._stamp_is_set(stamp):
            return None
        return float(stamp.sec) + float(stamp.nanosec) * 1e-9

    def _now_seconds(self) -> float:
        now = self.get_clock().now().to_msg()
        return float(now.sec) + float(now.nanosec) * 1e-9

    def _warn_bounded(self, message: str) -> None:
        self._warning_count += 1
        if self._warning_count % self._warn_interval == 0:
            self.get_logger().warn(message)


def main() -> int:
    rclpy.init()
    node = PositionEstimator()
    try:
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 0
