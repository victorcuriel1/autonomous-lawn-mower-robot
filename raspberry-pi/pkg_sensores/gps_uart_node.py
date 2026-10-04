#!/usr/bin/env python3

import math
import serial
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import NavSatFix, NavSatStatus
from std_msgs.msg import Float32, Int32

class GPSUartNode(Node):
    def __init__(self):
        super().__init__('gps_uart_node')

        self.declare_parameter('port', '/dev/ttyAMA3')
        self.declare_parameter('baudrate', 9600)

        self.port = self.get_parameter('port').value
        self.baudrate = int(self.get_parameter('baudrate').value)

        self.gps_fix_pub = self.create_publisher(NavSatFix, '/gps/fix', 10)
        self.gps_speed_pub = self.create_publisher(Float32, '/gps/speed', 10)
        self.gps_satellites_pub = self.create_publisher(Int32, '/gps/satellites', 10)

        self.latitude = 0.0
        self.longitude = 0.0
        self.altitude = 0.0
        self.satellites = 0
        self.has_fix = False

        self.ser = serial.Serial(
            port=self.port,
            baudrate=self.baudrate,
            timeout=0.05
        )

        self.timer = self.create_timer(0.02, self.read_gps)

        self.get_logger().info(
            f'GPS UART iniciado en {self.port} a {self.baudrate} baudios'
        )

    def nmea_to_decimal(self, value, hemisphere):
        if value == '':
            return 0.0

        raw = float(value)
        degrees = int(raw / 100)
        minutes = raw - degrees * 100
        decimal = degrees + minutes / 60.0

        if hemisphere in ['S', 'W']:
            decimal *= -1.0

        return decimal

    def publish_fix(self):
        msg = NavSatFix()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'gps_link'

        msg.latitude = self.latitude
        msg.longitude = self.longitude
        msg.altitude = self.altitude

        msg.status.service = NavSatStatus.SERVICE_GPS
        msg.status.status = (
            NavSatStatus.STATUS_FIX
            if self.has_fix
            else NavSatStatus.STATUS_NO_FIX
        )

        self.gps_fix_pub.publish(msg)
        self.gps_satellites_pub.publish(Int32(data=self.satellites))

    def read_gps(self):
        try:
            while self.ser.in_waiting > 0:
                line = self.ser.readline().decode(
                    'ascii',
                    errors='ignore'
                ).strip()

                if line.startswith('$GNGGA') or line.startswith('$GPGGA'):
                    self.parse_gga(line)

                elif line.startswith('$GNRMC') or line.startswith('$GPRMC'):
                    self.parse_rmc(line)

        except Exception as e:
            self.get_logger().error(f'Error leyendo GPS UART: {e}')

    def parse_gga(self, line):
        parts = line.split(',')

        if len(parts) < 10:
            return

        fix_quality = int(parts[6]) if parts[6].isdigit() else 0
        self.has_fix = fix_quality > 0

        if parts[7].isdigit():
            self.satellites = int(parts[7])

        if parts[2] and parts[3] and parts[4] and parts[5]:
            self.latitude = self.nmea_to_decimal(parts[2], parts[3])
            self.longitude = self.nmea_to_decimal(parts[4], parts[5])

        if parts[9]:
            self.altitude = float(parts[9])

        self.publish_fix()

    def parse_rmc(self, line):
        parts = line.split(',')

        if len(parts) < 8:
            return

        status = parts[2]
        self.has_fix = status == 'A'

        if parts[3] and parts[4] and parts[5] and parts[6]:
            self.latitude = self.nmea_to_decimal(parts[3], parts[4])
            self.longitude = self.nmea_to_decimal(parts[5], parts[6])

        speed_knots = float(parts[7]) if parts[7] else 0.0
        speed_kmh = speed_knots * 1.852

        if math.isnan(speed_kmh) or math.isinf(speed_kmh):
            speed_kmh = 0.0

        self.gps_speed_pub.publish(Float32(data=speed_kmh))
        self.publish_fix()

    def destroy_node(self):
        try:
            if self.ser and self.ser.is_open:
                self.ser.close()
        except Exception:
            pass

        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = GPSUartNode()

    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando gps_uart_node')
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()