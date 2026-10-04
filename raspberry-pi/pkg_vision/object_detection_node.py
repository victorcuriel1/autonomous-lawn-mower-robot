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


class ObjectDetectionNode(Node):
    def __init__(self):
        super().__init__('object_detection_node')

        self.declare_parameter('image_topic', '/camera/image_raw')
        self.declare_parameter('model_file', 'best_float16_obstacle.tflite')
        self.declare_parameter(
            'labels',
            [
                'obstaculo',
            ],
        )
        self.declare_parameter('roi_y', 0.25)
        self.declare_parameter('roi_h', 0.50)
        self.declare_parameter('confidence_threshold', 0.40)
        self.declare_parameter('iou_threshold', 0.45)
        self.declare_parameter('num_threads', 4)

        self.bridge = CvBridge()
        self.labels = list(
            self.get_parameter('labels').get_parameter_value().string_array_value
        )
        self.confidence_threshold = self.get_parameter(
            'confidence_threshold'
        ).get_parameter_value().double_value
        self.iou_threshold = self.get_parameter(
            'iou_threshold'
        ).get_parameter_value().double_value

        self.load_model(self.resolve_model_path())

        image_qos = QoSProfile(
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            reliability=ReliabilityPolicy.BEST_EFFORT,
        )

        self.state_pub = self.create_publisher(String, '/vision_obstacle_state', 1)
        self.debug_pub = self.create_publisher(Image, '/obstacle/debug_image', 1)
        self.image_sub = self.create_subscription(
            Image,
            self.get_parameter('image_topic').get_parameter_value().string_value,
            self.on_image,
            image_qos,
        )

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
        roi_y = self.get_parameter('roi_y').get_parameter_value().double_value
        roi_h = self.get_parameter('roi_h').get_parameter_value().double_value

        y1 = min(height - 1, int(max(0.0, min(1.0, roi_y)) * height))
        y2 = min(height, y1 + int(max(0.0, min(1.0, roi_h)) * height))
        y2 = max(y1 + 1, y2)

        return frame[y1:y2, :], (0, y1, width, y2)

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

    def detect(self, roi):
        roi_height, roi_width = roi.shape[:2]

        image = self.preprocess(roi)
        self.interpreter.set_tensor(self.input_index, image)
        self.interpreter.invoke()

        output = np.squeeze(self.interpreter.get_tensor(self.output_index))
        if output.ndim != 2:
            return []

        # YOLO exporta (4+nc, N); lo queremos como (N, 4+nc)
        if output.shape[0] < output.shape[1]:
            output = output.transpose(1, 0)

        if output.shape[1] < 4 + len(self.labels):
            return []

        class_scores = output[:, 4:4 + len(self.labels)]
        if class_scores.max() > 1.0 or class_scores.min() < 0.0:
            class_scores = 1.0 / (1.0 + np.exp(-class_scores))

        confidences = class_scores.max(axis=1)
        keep = confidences >= self.confidence_threshold
        if not np.any(keep):
            return []

        boxes = output[keep, :4].astype(np.float32).copy()
        confidences = confidences[keep].astype(np.float32)
        class_ids = class_scores[keep].argmax(axis=1)

        # Coordenadas en pixeles del input del modelo -> normalizadas
        if np.max(np.abs(boxes)) > 2.0:
            boxes[:, [0, 2]] /= float(self.input_w)
            boxes[:, [1, 3]] /= float(self.input_h)

        # cx,cy,w,h normalizado -> x,y,w,h en pixeles del ROI
        boxes[:, 0] = (boxes[:, 0] - boxes[:, 2] / 2.0) * roi_width
        boxes[:, 1] = (boxes[:, 1] - boxes[:, 3] / 2.0) * roi_height
        boxes[:, 2] *= roi_width
        boxes[:, 3] *= roi_height

        indices = cv2.dnn.NMSBoxes(
            boxes,
            confidences,
            self.confidence_threshold,
            self.iou_threshold,
        )
        if len(indices) == 0:
            return []

        detections = []
        for i in np.asarray(indices).flatten():
            x, y, w, h = boxes[i]
            x1 = max(0, int(x))
            y1 = max(0, int(y))
            x2 = min(roi_width - 1, int(x + w))
            y2 = min(roi_height - 1, int(y + h))
            detections.append(
                (x1, y1, x2, y2, float(confidences[i]), int(class_ids[i]))
            )

        return detections

    def label_for(self, class_id):
        if class_id < len(self.labels):
            return self.labels[class_id]

        return f'class_{class_id}'

    def on_image(self, msg):
        frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        roi, rect = self.crop_roi(frame)
        detections = self.detect(roi)

        if detections:
            best = max(detections, key=lambda d: d[4])
            state = f'{self.label_for(best[5])},{best[4]:.3f}'
        else:
            state = 'none,0.000'

        self.state_pub.publish(String(data=state))

        # Solo se dibuja/convierte la imagen de debug si alguien la mira
        if self.debug_pub.get_subscription_count() > 0:
            self.publish_debug(frame, rect, detections, msg.header)

    def publish_debug(self, frame, rect, detections, header):
        roi_x1, roi_y1, roi_x2, roi_y2 = rect
        cv2.rectangle(frame, (roi_x1, roi_y1), (roi_x2, roi_y2), (0, 255, 255), 1)

        for x1, y1, x2, y2, confidence, class_id in detections:
            x1 += roi_x1
            x2 += roi_x1
            y1 += roi_y1
            y2 += roi_y1
            text = f'{self.label_for(class_id)} {confidence:.2f}'

            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            cv2.putText(
                frame,
                text,
                (x1 + 4, max(20, y1 - 8)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (0, 255, 0),
                2,
            )

        debug_msg = self.bridge.cv2_to_imgmsg(frame, encoding='bgr8')
        debug_msg.header = header
        self.debug_pub.publish(debug_msg)


def main(args=None):
    rclpy.init(args=args)
    node = ObjectDetectionNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass

    node.destroy_node()
    if rclpy.ok():
        rclpy.shutdown()


if __name__ == '__main__':
    main()
