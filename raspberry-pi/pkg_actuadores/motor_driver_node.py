#!/usr/bin/env python3

import math

import rclpy
from rclpy.node import Node

from geometry_msgs.msg import Twist
from std_msgs.msg import Float32MultiArray


class MotorDriverNode(Node):
    def __init__(self):
        super().__init__('motor_driver_node')

        # =========================
        # Parámetros físicos del robot
        # =========================
        self.declare_parameter('wheel_radius', 0.10)   # radio de rueda en metros
        self.declare_parameter('wheel_base', 0.32)     # distancia entre ruedas en metros
        self.declare_parameter('max_rpm', 80.0)        # límite máximo de RPM

        self.wheel_radius = self.get_parameter('wheel_radius').value
        self.wheel_base = self.get_parameter('wheel_base').value
        self.max_rpm = self.get_parameter('max_rpm').value

        # =========================
        # Publicador hacia esp32_bridge_node
        # =========================
        self.cmd_motores_pub = self.create_publisher(
            Float32MultiArray,
            '/esp32/cmd_motores',
            10
        )

        # =========================
        # Suscriptor de velocidad
        # =========================
        self.cmd_vel_sub = self.create_subscription(
            Twist,
            '/cmd_vel',
            self.cmd_vel_cb,
            10
        )

        self.get_logger().info('motor_driver_node iniciado')
        self.get_logger().info('Escuchando /cmd_vel')
        self.get_logger().info('Publicando RPM en /esp32/cmd_motores')

    # =========================
    # Limitar valores
    # =========================
    def clamp(self, value, min_value, max_value):
        return max(min_value, min(value, max_value))

    # =========================
    # Convertir /cmd_vel a RPM
    # =========================
    def cmd_vel_cb(self, msg):
        linear_x = msg.linear.x
        angular_z = msg.angular.z

        # Cinemática diferencial:
        # linear_x  > 0  -> avanzar
        # linear_x  < 0  -> retroceder
        # angular_z > 0  -> girar hacia la izquierda
        # angular_z < 0  -> girar hacia la derecha

        left_mps = linear_x - (angular_z * self.wheel_base / 2.0)
        right_mps = linear_x + (angular_z * self.wheel_base / 2.0)

        # Conversión de velocidad lineal de rueda a RPM
        left_rpm = (left_mps / (2.0 * math.pi * self.wheel_radius)) * 60.0
        right_rpm = (right_mps / (2.0 * math.pi * self.wheel_radius)) * 60.0

        # Límite de RPM
        left_rpm = self.clamp(left_rpm, -self.max_rpm, self.max_rpm)
        right_rpm = self.clamp(right_rpm, -self.max_rpm, self.max_rpm)

        # Publica las RPM para que esp32_bridge_node las mande al ESP32
        self.cmd_motores_pub.publish(
            Float32MultiArray(data=[left_rpm, right_rpm])
        )

    # =========================
    # Cierre del nodo
    # =========================
    def destroy_node(self):
        try:
            # Al cerrar el nodo, manda RPM 0 a ambos motores DC
            self.cmd_motores_pub.publish(
                Float32MultiArray(data=[0.0, 0.0])
            )
        except Exception:
            pass

        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)

    node = MotorDriverNode()

    try:
        rclpy.spin(node)

    except KeyboardInterrupt:
        node.get_logger().info('Cerrando motor_driver_node')

    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
