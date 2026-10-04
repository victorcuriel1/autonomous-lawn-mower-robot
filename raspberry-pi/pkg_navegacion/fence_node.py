#!/usr/bin/env python3

import rclpy
from rclpy.node import Node

from geometry_msgs.msg import Polygon
from sensor_msgs.msg import NavSatFix
from std_msgs.msg import Bool, Int32, String


class FenceNode(Node):
    def __init__(self):
        super().__init__('fence_node')

        # =========================
        # Parametros
        # =========================
        self.declare_parameter('cant_min_puntos', 4)
        self.declare_parameter('publish_period', 0.5)

        self.cant_min_puntos = self.get_parameter('cant_min_puntos').get_parameter_value().integer_value
        self.publish_period = self.get_parameter('publish_period').get_parameter_value().double_value

        # =========================
        # Estado interno
        # =========================
        self.puntos_cerco_gps = []

        self.actual_lat = None
        self.actual_lon = None

        self.cerco_valido = False
        self.tiene_posicion_robot = False
        self.dentro_del_cerco = False

        # =========================
        # Suscriptores
        # =========================
        self.sub_fence_poligono = self.create_subscription(Polygon,'/fence/polygon',self.callback_cerco_poligono, 10)
        self.sub_gps_fix = self.create_subscription(NavSatFix,'/gps/fix',self.callback_gps,10)

        # =========================
        # Publicadores
        # =========================
        self.pub_cerco_valido = self.create_publisher(Bool,'/fencenode/valid',10)
        self.pub_robot_dentro = self.create_publisher( Int32,'/fencenode/robot_dentro',10)
        self.pub_status_text = self.create_publisher(String, '/fencenode/status_text',10)

        # =========================
        # Timer
        # =========================
        self.timer = self.create_timer(self.publish_period,self.publish_state)

        self.get_logger().info('fence_node iniciado correctamente')

    # ==================================================
    # Callbacks
    # ==================================================

    def callback_cerco_poligono(self, msg: Polygon):
        puntos = []

        for point in msg.points:
            lat = float(point.x)
            lon = float(point.y)
            puntos.append((lat, lon))

        if not self.es_cerco_valido(puntos):
            self.puntos_cerco_gps = []
            self.cerco_valido = False
            self.dentro_del_cerco = False
            self.publicar_estado('CERCO INVALIDO')
            self.get_logger().warn( f'Cerco invalido. Puntos recibidos: {len(puntos)}')
            return

        self.puntos_cerco_gps = puntos
        self.cerco_valido = True

        self.publicar_estado(f'CERCO OK: {len(self.puntos_cerco_gps)} puntos')
        self.get_logger().info('Cerco GPS recibido:')

        for i, (lat, lon) in enumerate(self.puntos_cerco_gps):
            self.get_logger().info(f'  Punto {i + 1}: lat={lat:.8f}, lon={lon:.8f}')

        self.ubicacion_dentro_del_cerco()

    def callback_gps(self, msg: NavSatFix):
        if msg.status.status < 0:
            self.tiene_posicion_robot = False
            self.dentro_del_cerco = False
            self.publicar_estado('GPS SIN FIX')
            return

        self.actual_lat = float(msg.latitude)
        self.actual_lon = float(msg.longitude)
        self.tiene_posicion_robot = True

        self.ubicacion_dentro_del_cerco()

    # ==================================================
    # Logica de cerco
    # ==================================================

    def es_cerco_valido(self, puntos):
        if len(puntos) < self.cant_min_puntos:
            return False

        return abs(self.area_poligono_gps(puntos)) > 1e-12

    def area_poligono_gps(self, puntos):
        area = 0.0
        n = len(puntos)

        for i in range(n):
            lat1, lon1 = puntos[i]
            lat2, lon2 = puntos[(i + 1) % n]
            area += lon1 * lat2 - lon2 * lat1

        return area / 2.0

    def ubicacion_dentro_del_cerco(self):
        if not self.cerco_valido:
            self.dentro_del_cerco = False
            return

        if not self.tiene_posicion_robot:
            self.dentro_del_cerco = False
            self.publicar_estado('CERCO OK - GPS ROBOT NO DISPONIBLE')
            return

        self.dentro_del_cerco = self.puntos_dentro_del_cerco(
            self.actual_lat,
            self.actual_lon,
            self.puntos_cerco_gps
        )

        if self.dentro_del_cerco:
            self.publicar_estado('ROBOT DENTRO DEL CERCO')
        else:
            self.publicar_estado('ROBOT FUERA DEL CERCO')

    def puntos_dentro_del_cerco(self, lat, lon, poligono):
        """
        Ray casting usando coordenadas GPS directamente.
        Para poligonos chicos funciona bien como verificacion dentro/fuera.

        Usamos:
        x = lon
        y = lat
        """
        if len(poligono) < 3:
            return False

        x = lon
        y = lat
        dentro = False
        j = len(poligono) - 1

        for i in range(len(poligono)):
            lat_i, lon_i = poligono[i]
            lat_j, lon_j = poligono[j]

            xi = lon_i
            yi = lat_i
            xj = lon_j
            yj = lat_j

            intersects = (((yi > y) != (yj > y))and ( x < (xj - xi) * (y - yi) / ((yj - yi) + 1e-12) + xi))

            if intersects:
                dentro = not dentro

            j = i

        return dentro

    # ==================================================
    # Publicacion periodica
    # ==================================================

    def publish_state(self):
        valid_msg = Bool()
        valid_msg.data = self.cerco_valido
        self.pub_cerco_valido.publish(valid_msg)

        dentro_msg = Int32()
        dentro_msg.data = 1 if self.dentro_del_cerco else 0
        self.pub_robot_dentro.publish(dentro_msg)

    # ==================================================
    # Publicadores auxiliares
    # ==================================================

    def publicar_estado(self, text):
        msg = String()
        msg.data = text
        self.pub_status_text.publish(msg)


def main(args=None):
    rclpy.init(args=args)

    node = FenceNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('fence_node detenido por teclado')
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
