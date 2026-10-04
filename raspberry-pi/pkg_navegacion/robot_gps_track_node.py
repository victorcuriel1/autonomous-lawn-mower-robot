#!/usr/bin/env python3
import math
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import NavSatFix, NavSatStatus
from std_msgs.msg import Bool, Float64MultiArray, String

class RobotGpsTrackNode(Node):
    def __init__(self):
        super().__init__('robot_gps_track_node')

        self.declare_parameter('periodo_muestreo_s', 5.0)
        self.declare_parameter('distancia_min_m', 0.5)
        self.declare_parameter('puntos_max', 1000)
        self.periodo_muestreo_s = float(self.get_parameter('periodo_muestreo_s').value)
        self.distancia_min_m = float(self.get_parameter('distancia_min_m').value)
        self.puntos_max = int(self.get_parameter('puntos_max').value)
        # Publicador
        self.track_pub = self.create_publisher(Float64MultiArray, '/robot/gps_track', 10)
        # Suscriptores
        self.create_subscription(NavSatFix, '/gps/fix', self.gps_callback, 10)
        self.create_subscription(Bool, '/start', self.start_callback, 10)
        self.create_subscription(String, '/navigation_app/mode', self.mode_callback, 10)
        self.create_subscription(Bool, '/robot/gps_track_enable', self.track_manual_callback, 10)
        # Variables de estado
        self.naveg_activa = False
        self.modo_actual = 'idle'
        self.start_navegacion_activo = False
        self.track_manual_activo = False

        self.ult_fix = None
        self.ult_muestreo_t = None
        self.puntos_trackeados = []

        self.get_logger().info('robot_gps_track_node iniciado')
        self.get_logger().info('Escuchando /gps/fix, /start y /navigation_app/mode')
        self.get_logger().info('Publicando /robot/gps_track')

    def mode_callback(self, msg):
        self.modo_actual = msg.data.strip()

    def start_callback(self, msg):
        self.start_navegacion_activo = bool(msg.data)
        self.actualizar_estado_track()

        if self.naveg_activa and not estuvo_activa:
            self.puntos_trackeados = []
            self.ult_muestreo_t = None
            self.get_logger().info(
                f'Inicio de track GPS. Modo: {self.modo_actual}'
            )
            self.publish_track()

        elif not self.naveg_activa and estuvo_activa:
            self.get_logger().info(
                f'Track GPS detenido. Puntos guardados: {len(self.puntos_trackeados)}'
            )
            self.publish_track()

    def gps_callback(self, msg):
        self.ult_fix = msg

        if not self.naveg_activa:
            return
        if not self.valid_fix(msg):
            return

        ahora = self.get_clock().now()
        if self.ult_muestreo_t is not None:
            elapsed_s = (ahora - self.ult_muestreo_t).nanoseconds * 1e-9
            if elapsed_s < self.periodo_muestreo_s:
                return
        nuevo_punto = (float(msg.latitude), float(msg.longitude))

        if self.puntos_trackeados:
            last_point = self.puntos_trackeados[-1]
            distance_m = self.haversine_m(last_point, nuevo_punto)
            if distance_m < self.distancia_min_m:
                return

        self.puntos_trackeados.append(nuevo_punto)
        self.ult_muestreo_t = ahora
        if len(self.puntos_trackeados) > self.puntos_max:
            self.puntos_trackeados = self.puntos_trackeados[-self.puntos_max:]
        self.publish_track()

    def track_manual_callback(self, msg):
        self.track_manual_activo = bool(msg.data)
        self.actualizar_estado_track()

    def valid_fix(self, msg):
        if msg.status.status == NavSatStatus.STATUS_NO_FIX:
            return False
        if math.isnan(msg.latitude) or math.isnan(msg.longitude):
            return False
        if abs(msg.latitude) < 0.000001 and abs(msg.longitude) < 0.000001:
            return False
        return True

    def publish_track(self):
        data = []
        for lat, lon in self.puntos_trackeados:
            data.append(lat)
            data.append(lon)
        self.track_pub.publish(Float64MultiArray(data=data))

    def haversine_m(self, point_a, point_b):
        lat1, lon1 = point_a
        lat2, lon2 = point_b
        earth_radius_m = 6371000.0

        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)

        a = (
            math.sin(delta_phi / 2.0) ** 2
            + math.cos(phi1)
            * math.cos(phi2)
            * math.sin(delta_lambda / 2.0) ** 2
        )
        c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

        return earth_radius_m * c

    def actualizar_estado_track(self):
        estuvo_activa = self.naveg_activa
        self.naveg_activa = self.start_navegacion_activo or self.track_manual_activo

        if self.naveg_activa and not estuvo_activa:
            self.puntos_trackeados = []
            self.ult_muestreo_t = None
            self.get_logger().info(f'Inicio de track GPS. Modo: {self.modo_actual}')
            self.publish_track()

        elif not self.naveg_activa and estuvo_activa:
            self.get_logger().info(
                f'Track GPS detenido. Puntos guardados: {len(self.puntos_trackeados)}'
            )
            self.publish_track()

def main(args=None):
    rclpy.init(args=args)
    node = RobotGpsTrackNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando robot_gps_track_node')
    finally:
        node.destroy_node()
        rclpy.shutdown()

if __name__ == '__main__':
    main()