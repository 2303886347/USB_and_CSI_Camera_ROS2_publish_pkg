"""ROS 2 publisher for a Jetson CSI camera opened through Argus."""

import threading

from .opencv_runtime import opencv_has_gstreamer, prefer_system_packages

prefer_system_packages()

import cv2  # noqa: E402
import rclpy  # noqa: E402
from cv_bridge import CvBridge  # noqa: E402
from rclpy.executors import ExternalShutdownException  # noqa: E402
from rclpy.node import Node  # noqa: E402
from rclpy.qos import qos_profile_sensor_data  # noqa: E402
from sensor_msgs.msg import Image  # noqa: E402

from .pipelines import build_csi_pipeline  # noqa: E402


class CsiCameraNode(Node):
    def __init__(self):
        super().__init__("csi_camera_publisher")
        self.declare_parameter("sensor_id", 0)
        self.declare_parameter("capture_width", 1280)
        self.declare_parameter("capture_height", 720)
        self.declare_parameter("output_width", 640)
        self.declare_parameter("output_height", 480)
        self.declare_parameter("framerate", 60)
        self.declare_parameter("flip_method", 0)
        self.declare_parameter("image_topic", "/image_raw")
        self.declare_parameter("frame_id", "csi_camera_optical_frame")
        self.declare_parameter("frame_limit", 0)

        self.sensor_id = int(self.get_parameter("sensor_id").value)
        self.capture_width = int(self.get_parameter("capture_width").value)
        self.capture_height = int(self.get_parameter("capture_height").value)
        self.output_width = int(self.get_parameter("output_width").value)
        self.output_height = int(self.get_parameter("output_height").value)
        self.framerate = int(self.get_parameter("framerate").value)
        self.flip_method = int(self.get_parameter("flip_method").value)
        self.image_topic = str(self.get_parameter("image_topic").value)
        self.frame_id = str(self.get_parameter("frame_id").value)
        self.frame_limit = int(self.get_parameter("frame_limit").value)

        if not self.image_topic.startswith("/"):
            raise ValueError("image_topic must be an absolute ROS topic")
        if self.frame_limit < 0:
            raise ValueError("frame_limit must be zero or greater")
        if not opencv_has_gstreamer(cv2):
            raise RuntimeError(
                "The selected OpenCV build has no GStreamer support: "
                f"{cv2.__file__}"
            )

        self.pipeline = build_csi_pipeline(
            self.sensor_id,
            self.capture_width,
            self.capture_height,
            self.output_width,
            self.output_height,
            self.framerate,
            self.flip_method,
        )
        self.bridge = CvBridge()
        self.publisher = self.create_publisher(
            Image,
            self.image_topic,
            qos_profile_sensor_data,
        )
        self.capture = cv2.VideoCapture(self.pipeline, cv2.CAP_GSTREAMER)
        if not self.capture.isOpened():
            self.capture.release()
            raise RuntimeError(
                "Unable to open CSI camera sensor-id=" f"{self.sensor_id}"
            )

        self.published_frames = 0
        self.failed_reads = 0
        self.timer = self.create_timer(1.0 / self.framerate, self.publish_frame)
        self.get_logger().info(f"OpenCV: {cv2.__version__} ({cv2.__file__})")
        self.get_logger().info(f"CSI pipeline: {self.pipeline}")
        self.get_logger().info(f"Publishing CSI images on {self.image_topic}")

    def publish_frame(self):
        ok, frame = self.capture.read()
        if not ok or frame is None:
            self.failed_reads += 1
            if self.failed_reads == 1 or self.failed_reads % self.framerate == 0:
                self.get_logger().error("Failed to read a CSI camera frame")
            return

        self.failed_reads = 0
        message = self.bridge.cv2_to_imgmsg(frame, encoding="bgr8")
        message.header.stamp = self.get_clock().now().to_msg()
        message.header.frame_id = self.frame_id
        self.publisher.publish(message)
        self.published_frames += 1

        if self.frame_limit and self.published_frames >= self.frame_limit:
            self.get_logger().info(
                f"Published requested {self.published_frames} frame(s); stopping"
            )
            self.timer.cancel()
            threading.Thread(target=rclpy.shutdown, daemon=True).start()

    def destroy_node(self):
        if hasattr(self, "capture") and self.capture is not None:
            self.capture.release()
        return super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = None
    try:
        node = CsiCameraNode()
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        if node is not None:
            node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
