#!/usr/bin/env python3
from __future__ import annotations

# pyright: reportMissingImports=false, reportMissingTypeStubs=false, reportUnknownMemberType=false, reportUnknownVariableType=false, reportUnknownArgumentType=false, reportUnknownParameterType=false, reportUnknownLambdaType=false, reportAny=false, reportOptionalMemberAccess=false, reportAttributeAccessIssue=false, reportIndexIssue=false, reportMissingTypeArgument=false, reportUntypedBaseClass=false, reportUnannotatedClassAttribute=false, reportUnusedImport=false, reportImplicitStringConcatenation=false, reportUnusedCallResult=false

from . import __init__ as iconom_vision  # noqa: F401
import rclpy
from cv_bridge import CvBridge, CvBridgeError
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image
from ultralytics import YOLO
from visualization_msgs.msg import Marker, MarkerArray


IMAGE_TOPIC = "/plane_01/camera/image_raw"
DETECTIONS_TOPIC = "/vision/detections"
MODEL_PATH = "/workspaces/yolov8n.pt"


class AircraftDetector(Node):
    def __init__(self) -> None:
        super().__init__("aircraft_detector")

        self.bridge = CvBridge()
        self.model = YOLO(MODEL_PATH)
        self.model.to("cpu")
        self._predict_kwargs = {"device": "cpu", "verbose": False}

        self._frame_count = 0
        self._empty_count = 0
        self._log_interval = 30

        self._allowed_labels = self._resolve_allowed_labels()

        self.image_sub = self.create_subscription(
            Image,
            IMAGE_TOPIC,
            self._handle_image,
            qos_profile_sensor_data,
        )
        self.marker_pub = self.create_publisher(MarkerArray, DETECTIONS_TOPIC, 10)

        self.get_logger().info(
            f"aircraft_detector started: subscribing to {IMAGE_TOPIC}; "
            f"publishing to {DETECTIONS_TOPIC}; model={MODEL_PATH}; "
            f"allowed_classes={sorted(self._allowed_labels)}"
        )

    def _resolve_allowed_labels(self) -> set[str]:
        allowed = {"person"}
        model_labels = self._model_label_names()
        if "airplane" in model_labels:
            allowed.add("airplane")
        return allowed

    def _model_label_names(self) -> set[str]:
        names = getattr(self.model, "names", {})
        if isinstance(names, dict):
            return {str(label) for label in names.values()}
        if isinstance(names, list):
            return {str(label) for label in names}
        return set()

    def _label_for_class(self, class_id: int) -> str:
        names = getattr(self.model, "names", {})
        if isinstance(names, dict):
            return str(names.get(class_id, class_id))
        if isinstance(names, list) and 0 <= class_id < len(names):
            return str(names[class_id])
        return str(class_id)

    def _handle_image(self, msg: Image) -> None:
        try:
            frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")
        except CvBridgeError as exc:
            self.get_logger().warn(f"cv_bridge conversion failed: {exc}")
            return

        self._frame_count += 1

        try:
            results = list(self.model(frame, **self._predict_kwargs))
        except Exception as exc:
            self.get_logger().error(f"YOLO inference failed: {exc}")
            return

        marker_array = self._build_marker_array(results, msg)
        self.marker_pub.publish(marker_array)

    def _build_marker_array(self, results: list[object], msg: Image) -> MarkerArray:
        marker_array = MarkerArray()

        delete_all = Marker()
        delete_all.header = msg.header
        delete_all.ns = "aircraft_detector"
        delete_all.action = Marker.DELETEALL
        marker_array.markers.append(delete_all)

        detections = []
        if results:
            first = results[0]
            boxes = getattr(first, "boxes", None)
            if boxes is not None and boxes.xyxy is not None and boxes.cls is not None:
                boxes_xyxy = boxes.xyxy.cpu().numpy()
                class_ids = boxes.cls.cpu().numpy().astype(int)
                confidences = boxes.conf.cpu().numpy() if boxes.conf is not None else None
                for idx, coords in enumerate(boxes_xyxy):
                    class_id = class_ids[idx]
                    label = self._label_for_class(class_id)
                    if label not in self._allowed_labels:
                        continue
                    confidence = float(confidences[idx]) if confidences is not None else 0.0
                    detections.append((coords, label, confidence))

        if not detections:
            self._empty_count += 1
            if self._empty_count % self._log_interval == 0:
                self.get_logger().info("no detections in current frame; continuing")
            return marker_array

        self._empty_count = 0
        self.get_logger().info(f"detections found: {len(detections)}")

        for idx, (coords, label, confidence) in enumerate(detections):
            x1, y1, x2, y2 = [float(v) for v in coords]
            width = max(1.0, x2 - x1)
            height = max(1.0, y2 - y1)

            marker = Marker()
            marker.header = msg.header
            marker.ns = "aircraft_detector"
            marker.id = idx
            marker.type = Marker.CUBE
            marker.action = Marker.ADD
            marker.pose.position.x = x1 + width / 2.0
            marker.pose.position.y = y1 + height / 2.0
            marker.pose.position.z = 0.0
            marker.pose.orientation.w = 1.0
            marker.scale.x = width
            marker.scale.y = height
            marker.scale.z = 1.0
            marker.color.r = 0.0
            marker.color.g = 1.0
            marker.color.b = 0.0
            marker.color.a = 0.55
            marker.text = f"{label}:{confidence:.2f}"
            marker_array.markers.append(marker)

        return marker_array


def main() -> int:
    rclpy.init()
    node = AircraftDetector()
    try:
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    import sys

    sys.exit(main())
