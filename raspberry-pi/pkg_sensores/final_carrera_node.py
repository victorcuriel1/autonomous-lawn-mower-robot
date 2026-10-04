#!/usr/bin/env python3
#
# limit_switch_node.py - Nodo ROS2 liviano para leer los 6 finales de
# carrera directamente desde los GPIO de la Raspberry Pi.
#
# Reemplaza la lectura local que hacía el ESP32 (LimitSwitchManager),
# que se eliminó del firmware para liberar GPIO para los 4 nuevos
# sensores ultrasónicos.
#
# Publica en el MISMO tópico y con el MISMO formato que publicaba
# pkg_esp32_bridge al parsear la línea FINALCARRERA, para que el resto
# del stack ROS2 siga funcionando sin cambios:
#
#   Tópico:  /sensors/limit_switches
#   Tipo:    std_msgs/Int32MultiArray
#   Orden:   [limit_left, limit_right, limit_back,
#             limit_center_left, limit_center_right, limit_down]
#   Valores: 1 = presionado, 0 = libre
#
# Cableado (igual que estaba en el ESP32):
#   GPIO (BCM) -> NO del final de carrera
#   GND        -> COM del final de carrera
#   Pull-up interno activado -> presionado = LOW = 1
#
# Debounce: 30 ms por canal (mismo criterio que el firmware original).
#
# Dependencias en la Raspberry:
#   sudo apt install python3-gpiozero python3-lgpio
#
# Los pines BCM por defecto son de EJEMPLO: ajustarlos con parámetros
# ROS o editando los defaults según el cableado real, por ejemplo:
#   ros2 run <pkg> limit_switch_node --ros-args -p pin_left:=6 -p pin_right:=13

import rclpy
from rclpy.node import Node
from std_msgs.msg import Int32MultiArray
from gpiozero import Button

DEBOUNCE_S = 0.030   # 30 ms, igual que LIMIT_DEBOUNCE_MS del firmware
SAMPLE_HZ = 100.0    # frecuencia de muestreo de los GPIO
PUBLISH_HZ = 20.0    # frecuencia de publicación del estado


class LimitSwitchNode(Node):
    def __init__(self):
        super().__init__('limit_switch_node')

        # Pines BCM por defecto (AJUSTAR al cableado real de la Raspberry)
        # Nota: se evitan los GPIO 4 y 5 a propósito.
        self.declare_parameter('pin_left', 6)
        self.declare_parameter('pin_right', 13)
        self.declare_parameter('pin_back', 19)
        self.declare_parameter('pin_center_left', 20)
        self.declare_parameter('pin_center_right', 21)
        self.declare_parameter('pin_down', 26)   # support_switch (base/apoyo)

        # Orden de publicación:
        # [limit_left, limit_right, limit_back,
        #  limit_center_left, limit_center_right, limit_down]
        self.names = ['left', 'right', 'back', 'center_left', 'center_right', 'down']
        pins = [
            self.get_parameter(f'pin_{name}').value
            for name in self.names
        ]

        # pull_up=True: presionado = pin a GND = is_pressed True
        # bounce_time=None: el debounce lo hacemos nosotros, por muestreo,
        # igual que en el firmware.
        self.buttons = [Button(pin, pull_up=True, bounce_time=None) for pin in pins]

        # Estado de debounce por canal
        now = self.get_clock().now()
        self.debounced = [1 if b.is_pressed else 0 for b in self.buttons]
        self.last_raw = list(self.debounced)
        self.last_change_time = [now] * len(self.buttons)

        self.publisher = self.create_publisher(
            Int32MultiArray, '/sensors/limit_switches', 10
        )

        self.sample_timer = self.create_timer(1.0 / SAMPLE_HZ, self.sample)
        self.publish_timer = self.create_timer(1.0 / PUBLISH_HZ, self.publish_state)

        pins_txt = ', '.join(
            f'{name}=BCM{pin}' for name, pin in zip(self.names, pins)
        )
        self.get_logger().info(f'Nodo limit_switch_node iniciado ({pins_txt})')

    def sample(self):
        """Muestrea los GPIO y aplica debounce de 30 ms por canal."""
        now = self.get_clock().now()

        for i, button in enumerate(self.buttons):
            raw = 1 if button.is_pressed else 0

            if raw != self.last_raw[i]:
                self.last_raw[i] = raw
                self.last_change_time[i] = now

            stable_s = (now - self.last_change_time[i]).nanoseconds / 1e9
            if raw != self.debounced[i] and stable_s >= DEBOUNCE_S:
                self.debounced[i] = raw
                self.get_logger().info(
                    f'Final de carrera {self.names[i]}: '
                    f'{"PRESIONADO" if raw else "libre"}'
                )

    def publish_state(self):
        self.publisher.publish(Int32MultiArray(data=list(self.debounced)))

    def destroy_node(self):
        for button in self.buttons:
            try:
                button.close()
            except Exception:
                pass
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)

    node = LimitSwitchNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando limit_switch_node')
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
