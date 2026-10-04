import threading
import time

import cv2
import rclpy
from cv_bridge import CvBridge
from rclpy.node import Node
from sensor_msgs.msg import Image


class CameraBridgeNode(Node):
    def __init__(self):
        super().__init__('camera_bridge_node')

        self.declare_parameter('stream_url', 'tcp://127.0.0.1:8888')
        self.declare_parameter('image_topic', '/camera/image_raw')
        self.declare_parameter('publish_fps', 15.0)
        self.stream_url = self.get_parameter(
            'stream_url',
        ).get_parameter_value().string_value
        self.image_topic = self.get_parameter(
            'image_topic',
        ).get_parameter_value().string_value
        self.publish_fps = self.get_parameter(
            'publish_fps',
        ).get_parameter_value().double_value

        self.bridge = CvBridge()
        self.image_pub = self.create_publisher(Image, self.image_topic, 10)

        self.cap = cv2.VideoCapture(self.stream_url)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        if not self.cap.isOpened():
            self.get_logger().error(
                f'No se pudo abrir stream MJPEG: {self.stream_url}',
            )
        else:
            self.get_logger().info(f'Leyendo stream MJPEG: {self.stream_url}')

        self.latest_frame = None
        self.frame_lock = threading.Lock()
        self.running = True
        self.reader_thread = threading.Thread(
            target=self.read_loop,
            daemon=True,
        )
        self.reader_thread.start()

        period = 1.0 / max(1.0, self.publish_fps)
        self.timer = self.create_timer(period, self.publish_frame)

    def read_loop(self):
        while self.running:
            if not self.cap.isOpened():
                time.sleep(0.05)
                continue

            ok, frame = self.cap.read()
            if ok:
                with self.frame_lock:
                    self.latest_frame = frame
            else:
                time.sleep(0.02)

    def publish_frame(self):
        with self.frame_lock:
            if self.latest_frame is None:
                return
            frame = self.latest_frame.copy()

        msg = self.bridge.cv2_to_imgmsg(frame, encoding='bgr8')
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'camera'
        self.image_pub.publish(msg)

    def destroy_node(self):
        self.running = False

        if hasattr(self, 'reader_thread'):
            self.reader_thread.join(timeout=1.0)

        if hasattr(self, 'cap'):
            self.cap.release()

        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = CameraBridgeNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass

    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
