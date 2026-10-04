#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from std_msgs.msg import Bool, Float32, String

class BuzzerNode(Node):
    def __init__(self):
        super().__init__('buzzer_node')

        self.declare_parameter('voltaje_bateria_baja', 11.0)
        self.voltaje_bateria_baja = float(self.get_parameter('voltaje_bateria_baja').value)

        self.ultimo_modo = None
        self.ultimo_inicio = None
        self.ultimo_estop = None
        self.alerta_bateria_baja_enviada = False

        self.pub_comando_buzzer = self.create_publisher(String, '/esp32/cmd_buzzer', 10)
        self.create_subscription(String, '/navigation_app/mode', self.modo_callback, 10)
        self.create_subscription(Bool, '/start', self.inicio_callback, 10)
        self.create_subscription(Bool, '/safety/estop', self.estop_callback, 10)
        self.create_subscription(Float32, '/battery/voltage', self.bateria_callback, 10)

        self.get_logger().info('buzzer_node iniciado')
        self.reproducir('LISTO')

    def reproducir(self, texto):
        self.pub_comando_buzzer.publish(String(data=texto))
        self.get_logger().info(f'Buzzer: {texto}')

    def modo_callback(self, msg):
        modo = msg.data.strip()
        if modo == self.ultimo_modo:
            return

        self.ultimo_modo = modo
        modo_a_buzzer = {
            'manual': 'MODOMANUAL',
            'random': 'MODOALEATORIO',
            'parallel_lines': 'MODOPARALELO',
            'perimeter': 'MODOPERIMETRAL',
        }
        texto_buzzer = modo_a_buzzer.get(modo)
        if texto_buzzer is not None:
            self.reproducir(texto_buzzer)

    def inicio_callback(self, msg):
        inicio = bool(msg.data)
        if inicio == self.ultimo_inicio:
            return

        self.ultimo_inicio = inicio
        if inicio:
            self.reproducir('STARTCORTE')
        else:
            self.reproducir('STOP')

    def estop_callback(self, msg):
        estop = bool(msg.data)
        if estop == self.ultimo_estop:
            return

        self.ultimo_estop = estop
        if estop:
            self.reproducir('ESTOP')

    def bateria_callback(self, msg):
        voltaje = float(msg.data)
        if voltaje <= self.voltaje_bateria_baja:
            if not self.alerta_bateria_baja_enviada:
                self.reproducir('BATERIABAJA')
                self.alerta_bateria_baja_enviada = True
        else:
            self.alerta_bateria_baja_enviada = False

def main(args=None):
    rclpy.init(args=args)
    nodo = BuzzerNode()
    try:
        rclpy.spin(nodo)
    except KeyboardInterrupt:
        nodo.get_logger().info('Cerrando buzzer_node')
    finally:
        nodo.destroy_node()
        rclpy.shutdown()

if __name__ == '__main__':
    main()