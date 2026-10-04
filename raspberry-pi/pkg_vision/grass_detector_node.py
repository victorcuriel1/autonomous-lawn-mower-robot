import sys
sys.path.insert(0, "/home/captainp/brain_captainp/yolo_env/lib/python3.12/site-packages")

import cv2
import numpy as np
import rclpy
from cv_bridge import CvBridge
from ament_index_python.packages import get_package_share_directory
from pathlib import Path
from rclpy.node import Node
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sensor_msgs.msg import Image
from std_msgs.msg import String

from ai_edge_litert.interpreter import Interpreter


class GrassDetectorNode(Node):
    def __init__(self):
        super().__init__('grass_detector_node')

        self.declare_parameter('image_topic', '/camera/image_raw')
        self.declare_parameter('model_file', 'best_float16_grass.tflite')
        self.declare_parameter(
            'labels',
            [
                'no pasto',
                'pasto',
            ],
        )
        self.declare_parameter('roi_x', 0.25)
        self.declare_parameter('roi_y', 0.55)
        self.declare_parameter('roi_w', 0.50)
        self.declare_parameter('roi_h', 0.40)
        self.declare_parameter('confidence_threshold', 0.50)
        self.declare_parameter('num_threads', 4)

        self.bridge = CvBridge()

        model_path = self.resolve_model_path()
        self.labels = list(
            self.get_parameter('labels').get_parameter_value().string_array_value
        )
        self.confidence_threshold = self.get_parameter(
            'confidence_threshold'
        ).get_parameter_value().double_value

        self.load_model(model_path)

        image_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
        )

        self.state_pub = self.create_publisher(String, '/grass_state', 1)
        self.debug_pub = self.create_publisher(Image, '/grass/debug_image', 1)
        self.image_sub = self.create_subscription(
            Image,
            self.get_parameter('image_topic').get_parameter_value().string_value,
            self.on_image,
            image_qos,
        )

        self.get_logger().info(f'Grass detector usando modelo: {model_path}')

    def resolve_model_path(self):
        model_file = self.get_parameter('model_file').get_parameter_value().string_value
        path = Path(model_file)
        if path.is_absolute():
            return path

        package_share = Path(get_package_share_directory('pkg_vision'))
        return package_share / 'models' / model_file

    def load_model(self, model_path):
        num_threads = self.get_parameter('num_threads').get_parameter_value().integer_value

        try:
            self.interpreter = Interpreter(
                model_path=str(model_path),
                num_threads=num_threads,
            )
        except TypeError:
            self.interpreter = Interpreter(model_path=str(model_path))

        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()

        input_shape = self.input_details[0]['shape']
        self.input_h = int(input_shape[1])
        self.input_w = int(input_shape[2])
        self.input_dtype = self.input_details[0]['dtype']
        self.input_index = self.input_details[0]['index']
        self.output_index = self.output_details[0]['index']

    def crop_roi(self, frame):
        height, width = frame.shape[:2]
        roi_x = self.get_parameter('roi_x').get_parameter_value().double_value
        roi_y = self.get_parameter('roi_y').get_parameter_value().double_value
        roi_w = self.get_parameter('roi_w').get_parameter_value().double_value
        roi_h = self.get_parameter('roi_h').get_parameter_value().double_value

        x1 = min(width - 1, int(max(0.0, min(1.0, roi_x)) * width))
        y1 = min(height - 1, int(max(0.0, min(1.0, roi_y)) * height))
        x2 = min(width, x1 + int(max(0.0, min(1.0, roi_w)) * width))
        y2 = min(height, y1 + int(max(0.0, min(1.0, roi_h)) * height))

        x2 = max(x1 + 1, x2)
        y2 = max(y1 + 1, y2)
        return frame[y1:y2, x1:x2], (x1, y1, x2, y2)

    def preprocess(self, frame):
        image = cv2.resize(frame, (self.input_w, self.input_h))
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        image = image.astype(np.float32) / 255.0
        image = np.expand_dims(image, axis=0)

        if self.input_dtype == np.uint8:
            scale, zero_point = self.input_details[0]['quantization']
            image = image / scale + zero_point
            return image.astype(np.uint8)

        return image.astype(self.input_dtype)

    def classify_roi(self, roi):
        image = self.preprocess(roi)
        self.interpreter.set_tensor(self.input_index, image)
        self.interpreter.invoke()

        output = self.interpreter.get_tensor(self.output_index)
        scores = np.squeeze(output)

        if scores.ndim == 2:
            if scores.shape[0] < scores.shape[1]:
                scores = scores.transpose(1, 0)

            if scores.shape[1] >= 4 + len(self.labels):
                class_scores = scores[:, 4:4 + len(self.labels)]
                if class_scores.max() > 1.0 or class_scores.min() < 0.0:
                    class_scores = 1.0 / (1.0 + np.exp(-class_scores))

                detection_scores = class_scores.max(axis=1)
                best_detection = int(np.argmax(detection_scores))
                class_id = int(np.argmax(class_scores[best_detection]))
                confidence = float(detection_scores[best_detection])
            else:
                scores = scores.reshape(-1)
                class_scores = scores[:len(self.labels)]
                class_id, confidence = self.best_class(class_scores)
        else:
            class_scores = scores[:len(self.labels)]
            class_id, confidence = self.best_class(class_scores)

        if class_id < 0:
            return 'none', 0.0

        if confidence < self.confidence_threshold:
            return 'none', confidence

        label = self.labels[class_id] if class_id < len(self.labels) else f'class_{class_id}'
        return label, confidence

    def best_class(self, class_scores):
        if class_scores.size == 0:
            return -1, 0.0

        if class_scores.max() > 1.0 or class_scores.min() < 0.0:
            class_scores = 1.0 / (1.0 + np.exp(-class_scores))

        class_id = int(np.argmax(class_scores))
        return class_id, float(class_scores[class_id])

    def on_image(self, msg):
        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        roi, rect = self.crop_roi(frame)
        label, confidence = self.classify_roi(roi)

        self.state_pub.publish(String(data=f'{label},{confidence:.3f}'))
        self.publish_debug(frame, rect, label, confidence, msg.header)

    def publish_debug(self, frame, rect, label, confidence, header):
        x1, y1, x2, y2 = rect
        debug = frame.copy()
        color = (0, 255, 0) if label != 'none' else (0, 255, 255)
        text = f'{label} {confidence:.2f}'

        cv2.rectangle(debug, (x1, y1), (x2, y2), color, 2)
        cv2.putText(
            debug,
            text,
            (x1, max(20, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            color,
            2,
        )

        debug_msg = self.bridge.cv2_to_imgmsg(debug, encoding='bgr8')
        debug_msg.header = header
        self.debug_pub.publish(debug_msg)


def main(args=None):
    rclpy.init(args=args)
    node = GrassDetectorNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass

    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main()