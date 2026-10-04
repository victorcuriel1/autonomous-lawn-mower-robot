#!/usr/bin/env python3

import sys
import serial
import rclpy
from rclpy.node import Node
from std_msgs.msg import (Bool, Empty, Int32, Float32, Float32MultiArray, Int32MultiArray, String,)
from sensor_msgs.msg import Imu, NavSatFix, NavSatStatus

class ESP32BridgeNode(Node):
    def __init__(self):
        super().__init__('esp32_bridge_node')

        # ============================================================
        # Parámetros
        # ============================================================
        self.declare_parameter('port', '/dev/ttyUSB0')
        self.declare_parameter('baudrate', 115200)
        self.declare_parameter('status_period', 0.20)
        self.declare_parameter('auto_request_status', True)
        self.port = self.get_parameter('port').value
        self.baudrate = self.get_parameter('baudrate').value
        self.status_period = self.get_parameter('status_period').value
        self.auto_request_status = self.get_parameter('auto_request_status').value
        self.ser = None

        # ============================================================
        # Conexión serial
        # ============================================================
        try:
            self.ser = serial.Serial( port=self.port, baudrate=self.baudrate, timeout=0.02)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            self.get_logger().info(
                f'Conectado al ESP32 en {self.port} a {self.baudrate} baudios'
            )

        except Exception as e:
            self.get_logger().error(
                f'No se pudo abrir el puerto serial {self.port}: {e}'
            )
            sys.exit(1)

        # ============================================================
        # Publicadores: debug serial
        # ============================================================

        self.serial_rx_pub = self.create_publisher( String, '/esp32/serial_rx', 10)
        self.serial_tx_pub = self.create_publisher(String, '/esp32/serial_tx', 10)
        self.ack_pub = self.create_publisher(String,'/esp32/ack', 10)
        self.error_pub = self.create_publisher( String,'/esp32/error', 1 )

        # ============================================================
        # Publicadores: sensores y estados recibidos del ESP32
        # ============================================================
        self.ultrasonic_pub = self.create_publisher(Float32MultiArray, '/sensors/ultrasonic', 10)
        self.motors_rpm_pub = self.create_publisher(Float32MultiArray, '/motors/rpm', 10 )
        self.motors_ticks_pub = self.create_publisher(Int32MultiArray, '/motors/ticks',10)
        self.motors_time_pub = self.create_publisher(Float32,'/motors/time_ms', 10)
        self.trimmer_state_pub = self.create_publisher(Bool, '/actuators/trimmer_state', 10)
        self.brushless_state_pub = self.create_publisher(Bool, '/actuators/brushless_state', 10)
        self.buzzer_text_pub = self.create_publisher(String,'/actuators/buzzer_text', 10)
        self.display_text_pub = self.create_publisher(String, '/actuators/display_text', 10)
        self.imu_pub = self.create_publisher(Imu, '/imu/data_raw', 10)
        self.imu_angles_pub = self.create_publisher(Float32MultiArray,'/imu/angles', 10)
        self.battery_voltage_pub = self.create_publisher(Float32, '/battery/voltage', 10 )
        self.estop_pub = self.create_publisher(Bool, '/safety/estop', 10)

        # Estado del boton "vision" de la app reexpuesto como Bool para los nodos internos
        self.vision_enabled_pub = self.create_publisher(Bool, '/vision/enabled', 10)

        # ============================================================
        # Suscriptores: comandos ROS2 hacia el ESP32
        # ============================================================
        self.cmd_motores_sub = self.create_subscription( Float32MultiArray, '/esp32/cmd_motores', self.cmd_motores_cb, 10)
        self.cmd_trimmer_sub = self.create_subscription( Bool,'/esp32/cmd_trimmer', self.cmd_trimmer_cb, 10)
        self.cmd_brushless_sub = self.create_subscription( Bool, '/esp32/cmd_blade', self.cmd_brushless_cb, 10)
        self.cmd_display_sub = self.create_subscription( String, '/esp32/cmd_display', self.cmd_display_cb, 10)
        self.cmd_buzzer_sub = self.create_subscription( String, '/esp32/cmd_buzzer', self.cmd_buzzer_cb, 10)
        self.cmd_estop_sub = self.create_subscription(Empty, '/esp32/cmd_estop', self.cmd_estop_cb, 10)
        self.cmd_reset_estop_sub = self.create_subscription( Empty,'/esp32/cmd_reset_estop', self.cmd_reset_estop_cb,10)
        self.cmd_reset_encoders_sub = self.create_subscription( Empty, '/esp32/cmd_reset_encoders', self.cmd_reset_encoders_cb, 10)
        self.cmd_imu_calibrate_sub = self.create_subscription( Empty,'/esp32/cmd_imu_calibrate', self.cmd_imu_calibrate_cb, 10 )
        self.cmd_imu_reset_yaw_sub = self.create_subscription(  Empty,'/esp32/cmd_imu_reset_yaw', self.cmd_imu_reset_yaw_cb, 10)
        self.cmd_status_sub = self.create_subscription(Empty,'/esp32/cmd_status', self.cmd_status_cb, 10)
        self.cmd_ping_sub = self.create_subscription( Empty,'/esp32/cmd_ping', self.cmd_ping_cb,10)

        # Este topic permite bloquear o liberar desde ROS2:
        # False -> CMD_ESTOP
        # True  -> CMD_RESET_ESTOP
        self.motors_enable_sub = self.create_subscription(Bool ,'/motors_enable', self.motors_enable_cb, 10)

        # Boton "vision activada/desactivada" de la app:
        # 1 -> blade_node actua sobre el brushless segun grass_node
        # 0 -> se ignora la vision
        self.app_vision_sub = self.create_subscription(Int32, '/app/vision_enable', self.app_vision_enable_cb, 10)

        # ============================================================
        # Timers
        # ============================================================

        self.read_timer = self.create_timer(
            0.01,
            self.read_serial
        )

        if self.auto_request_status:
            self.status_timer = self.create_timer(
                self.status_period,
                self.request_status
            )
        else:
            self.status_timer = None

        # Prueba inicial de conexión
        self.send_serial('PING')
        self.get_logger().info('Nodo esp32_bridge_node iniciado')

    # ============================================================
    # Utilidades
    # ============================================================

    def safe_float(self, value, default=0.0):
        try:
            return float(value)
        except Exception:
            return default

    def safe_int(self, value, default=0):
        try:
            return int(float(value))
        except Exception:
            return default

    def send_serial(self, text):
        try:
            if not self.ser or not self.ser.is_open:
                self.get_logger().error('El puerto serial no está abierto')
                return

            clean_text = text.strip()

            if clean_text == '':
                return

            self.ser.write((clean_text + '\n').encode('utf-8'))

            self.serial_tx_pub.publish(
                String(data=clean_text)
            )

        except Exception as e:
            self.get_logger().error(f'Error enviando serial: {e}')

    # ============================================================
    # Callbacks: ROS2 -> ESP32
    # ============================================================

    def cmd_motores_cb(self, msg):
        if len(msg.data) < 2:
            self.get_logger().warn(
                'Mensaje /esp32/cmd_motores inválido. Se esperan 2 valores: [left_rpm, right_rpm]'
            )
            return

        left_rpm = float(msg.data[0])
        right_rpm = float(msg.data[1])

        self.send_serial(
            f'CMD_MOTORES,{left_rpm:.2f},{right_rpm:.2f}'
        )

    def cmd_trimmer_cb(self, msg):
        state = 1 if msg.data else 0
        self.send_serial(f'CMD_TRIMMER,{state}')

    def cmd_brushless_cb(self, msg):
        state = 1 if msg.data else 0
        self.send_serial(f'CMD_BRUSHLESS,{state}')

    def cmd_display_cb(self, msg):
        text = msg.data.strip()

        if text == '':
            text = 'OFF'

        self.send_serial(
            f'CMD_DISPLAY,{text}'
        )

    def cmd_buzzer_cb(self, msg):
        text = msg.data.strip()

        if text == '':
            self.get_logger().warn(
                'Mensaje /esp32/cmd_buzzer vacío. Ejemplos válidos: START, OK, ERROR, ESTOP, LOWBATTERY, STOP'
            )
            return

        self.send_serial(
            f'CMD_BUZZER,{text}'
        )

    def cmd_estop_cb(self, msg):
        self.send_serial('CMD_ESTOP')

    def cmd_reset_estop_cb(self, msg):
        self.send_serial('CMD_RESET_ESTOP')

    def cmd_reset_encoders_cb(self, msg):
        self.send_serial('RESET_ENCODERS')

    def cmd_imu_calibrate_cb(self, msg):
        self.send_serial('IMU_CALIBRATE')

    def cmd_imu_reset_yaw_cb(self, msg):
        self.send_serial('IMU_RESET_YAW')

    def cmd_status_cb(self, msg):
        self.send_serial('STATUS')

    def cmd_ping_cb(self, msg):
        self.send_serial('PING')

    def motors_enable_cb(self, msg):
        if msg.data:
            self.send_serial('CMD_RESET_ESTOP')
        else:
            self.send_serial('CMD_ESTOP')

    def app_vision_enable_cb(self, msg):
        self.vision_enabled_pub.publish(Bool(data=msg.data == 1))

    def request_status(self):
        self.send_serial('STATUS\n')

    # ============================================================
    # Lectura serial: ESP32 -> ROS2
    # ============================================================

    def read_serial(self):
        try:
            if not self.ser or not self.ser.is_open:
                return

            while self.ser.in_waiting > 0:
                line = self.ser.readline().decode(
                    'utf-8',
                    errors='ignore'
                ).strip()

                if line == '':
                    continue

                self.serial_rx_pub.publish(
                    String(data=line)
                )

                self.parse_serial_line(line)

        except Exception as e:
            self.get_logger().error(f'Error leyendo serial: {e}')

    # ============================================================
    # Parser principal
    # ============================================================

    def parse_serial_line(self, line):
        # Respuestas simples sin coma
        upper_line = line.upper()

        if upper_line == 'PONG':
            self.ack_pub.publish(String(data='PONG'))
            self.get_logger().info('ESP32 respondió PONG')
            return

        if upper_line.startswith('ACK'):
            self.ack_pub.publish(String(data=line))
            self.get_logger().info(f'ESP32 ACK: {line}')
            return

        if upper_line.startswith('ERR'):
            self.error_pub.publish(String(data=line))
            self.get_logger().error(f'ESP32 ERROR: {line}')
            return

        if upper_line.startswith("GPS_DEBUG"):
            return

        # Protocolo principal separado por comas
        parts = [p.strip() for p in line.split(',')]

        if len(parts) == 0:
            return

        msg_type = parts[0].upper()

        # --------------------------------------------------------
        # ULTRASONICOS,us_left,us_center,us_right,us_diag_right,
        #              us_diag_left,us_back_right
        # --------------------------------------------------------
        if msg_type == 'ULTRASONICOS':
            if len(parts) < 7:
                self.get_logger().warn(f'ULTRASONICOS incompleto: {line}')
                return

            ultrasonic_values = [
                self.safe_float(value)
                for value in parts[1:7]
            ]

            self.ultrasonic_pub.publish(
                Float32MultiArray(data=ultrasonic_values)
            )

        # --------------------------------------------------------
        # MOTORES,time_ms,left_rpm,right_rpm,left_ticks,right_ticks
        # --------------------------------------------------------
        elif msg_type == 'MOTORES':
            if len(parts) < 6:
                self.get_logger().warn(f'MOTORES incompleto: {line}')
                return

            time_ms = self.safe_float(parts[1])
            left_rpm = self.safe_float(parts[2])
            right_rpm = self.safe_float(parts[3])
            left_ticks = self.safe_int(parts[4])
            right_ticks = self.safe_int(parts[5])

            self.motors_time_pub.publish(
                Float32(data=time_ms)
            )

            self.motors_rpm_pub.publish(
                Float32MultiArray(data=[left_rpm, right_rpm])
            )

            self.motors_ticks_pub.publish(
                Int32MultiArray(data=[left_ticks, right_ticks])
            )

        # --------------------------------------------------------
        # TRIMMER,trimmer_state
        # --------------------------------------------------------
        elif msg_type == 'TRIMMER':
            if len(parts) < 2:
                self.get_logger().warn(f'TRIMMER incompleto: {line}')
                return

            trimmer_state = self.safe_int(parts[1])

            self.trimmer_state_pub.publish(
                Bool(data=bool(trimmer_state))
            )

        # --------------------------------------------------------
        # BRUSHLESS,brushless_state
        # --------------------------------------------------------
        elif msg_type == 'BRUSHLESS':
            if len(parts) < 2:
                self.get_logger().warn(f'BRUSHLESS incompleto: {line}')
                return

            brushless_state = self.safe_int(parts[1])

            self.brushless_state_pub.publish(
                Bool(data=bool(brushless_state))
            )

        # --------------------------------------------------------
        # BUZZER,buzzer_text
        # --------------------------------------------------------
        elif msg_type == 'BUZZER':
            text = ','.join(parts[1:]) if len(parts) > 1 else ''

            self.buzzer_text_pub.publish(
                String(data=text)
            )

        # --------------------------------------------------------
        # DISPLAY,text
        # --------------------------------------------------------
        elif msg_type == 'DISPLAY':
            text = ','.join(parts[1:]) if len(parts) > 1 else ''

            self.display_text_pub.publish(
                String(data=text)
            )

        # --------------------------------------------------------
        # IMU,ax,ay,az,gx,gy,gz
        # --------------------------------------------------------
        elif msg_type == 'IMU':
            if len(parts) < 7:
                self.get_logger().warn(f'IMU incompleto: {line}')
                return

            ax = self.safe_float(parts[1])
            ay = self.safe_float(parts[2])
            az = self.safe_float(parts[3])
            gx = self.safe_float(parts[4])
            gy = self.safe_float(parts[5])
            gz = self.safe_float(parts[6])

            imu_msg = Imu()
            imu_msg.header.stamp = self.get_clock().now().to_msg()
            imu_msg.header.frame_id = 'imu_link'

            imu_msg.linear_acceleration.x = ax
            imu_msg.linear_acceleration.y = ay
            imu_msg.linear_acceleration.z = az

            imu_msg.angular_velocity.x = gx
            imu_msg.angular_velocity.y = gy
            imu_msg.angular_velocity.z = gz

            self.imu_pub.publish(imu_msg)

        # --------------------------------------------------------
        # IMU_ANGLES,roll,pitch,yaw,calibrated
        # --------------------------------------------------------
        elif msg_type == 'IMU_ANGLES':
            if len(parts) < 4:
                self.get_logger().warn(f'IMU_ANGLES incompleto: {line}')
                return

            roll = self.safe_float(parts[1])
            pitch = self.safe_float(parts[2])
            yaw = self.safe_float(parts[3])
            calibrated = self.safe_float(parts[4]) if len(parts) > 4 else 0.0

            self.imu_angles_pub.publish(
                Float32MultiArray(data=[roll, pitch, yaw, calibrated])
            )

        # --------------------------------------------------------
        # GPS,fix,lat,lon,alt,speed
        # --------------------------------------------------------
        elif msg_type == 'GPS':
            if len(parts) < 6:
                self.get_logger().warn(f'GPS incompleto: {line}')
                return

            fix = self.safe_int(parts[1])
            lat = self.safe_float(parts[2])
            lon = self.safe_float(parts[3])
            alt = self.safe_float(parts[4])
            speed = self.safe_float(parts[5])
            satellites = self.safe_int(parts[6]) if len(parts) > 6 else 0

            gps_msg = NavSatFix()
            gps_msg.header.stamp = self.get_clock().now().to_msg()
            gps_msg.header.frame_id = 'gps_link'

            gps_msg.latitude = lat
            gps_msg.longitude = lon
            gps_msg.altitude = alt

            gps_msg.status.service = NavSatStatus.SERVICE_GPS

            if fix == 1:
                gps_msg.status.status = NavSatStatus.STATUS_FIX
            else:
                gps_msg.status.status = NavSatStatus.STATUS_NO_FIX

            self.gps_fix_pub.publish(gps_msg)
            self.gps_speed_pub.publish(Float32(data=speed))
            self.gps_satellites_pub.publish(Int32(data=satellites))

        # --------------------------------------------------------
        # BATTERY,voltage
        # --------------------------------------------------------
        elif msg_type == 'BATTERY':
            if len(parts) < 2:
                self.get_logger().warn(f'BATTERY incompleto: {line}')
                return

            voltage = self.safe_float(parts[1])

            self.battery_voltage_pub.publish(
                Float32(data=voltage)
            )

        # --------------------------------------------------------
        # ESTADO,estop_state
        # --------------------------------------------------------
        elif msg_type == 'ESTADO':
            if len(parts) < 2:
                self.get_logger().warn(f'ESTADO incompleto: {line}')
                return

            estop_state = self.safe_int(parts[1])

            self.estop_pub.publish(
                Bool(data=bool(estop_state))
            )

        else:
            self.get_logger().warn(f'Mensaje serial no reconocido: {line}')

    # ============================================================
    # Cierre seguro
    # ============================================================

    def destroy_node(self):
        try:
            if self.ser and self.ser.is_open:
                self.ser.close()
        except Exception:
            pass

        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)

    node = ESP32BridgeNode()

    try:
        rclpy.spin(node)

    except KeyboardInterrupt:
        node.get_logger().info('Cerrando esp32_bridge_node')

    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
