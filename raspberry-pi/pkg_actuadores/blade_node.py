#!/usr/bin/env python3

import rclpy
from rclpy.node import Node
from std_msgs.msg import Bool, String


class BladeNode(Node):
    """
    Controla el brushless (blade) segun la vision de grass_node.

    Entradas:
        /vision/enabled (Bool):
            Boton "vision activada/desactivada" de la app.
            El bridge lo genera desde /app/vision_enable (1 o 0).

        /grass_state (String):
            Salida de grass_node con formato "etiqueta,confianza"
            ('pasto', 'no pasto' o 'none').

    Salida:
        /esp32/cmd_blade (Bool):
            True  -> el bridge envia CMD_BRUSHLESS,1 (activa brushless)
            False -> el bridge envia CMD_BRUSHLESS,0 (apaga brushless)

    Logica:
        - Solo comanda el brushless si la vision esta activada desde la app.
        - Vision activada + 'pasto'                 -> brushless ON
        - Vision activada + 'no pasto' / 'none'     -> brushless OFF
        - Vision activada + grass_state sin datos
          frescos (grass_node caido)                -> brushless OFF (seguridad)
        - Al desactivar la vision publica un OFF y deja de comandar,
          para no interferir con las pruebas manuales del brushless.
        - Solo publica cuando cambia el estado deseado, para no
          saturar el serial con CMD_BRUSHLESS repetidos.
    """

    def __init__(self):
        super().__init__('blade_node')

        self.declare_parameter('grass_label', 'pasto')
        self.declare_parameter('grass_timeout_s', 2.0)
        self.declare_parameter('check_period_s', 0.5)

        self.grass_label = str(self.get_parameter('grass_label').value).strip().lower()
        self.grass_timeout_s = float(self.get_parameter('grass_timeout_s').value)

        self.vision_enabled = False
        self.grass_detected = False
        self.corte_solicitado = False
        self.manual_blade_hab = False
        self.t_ultimo_grass = None

        # None = no se esta comandando el brushless (vision desactivada)
        self.ultimo_cmd = None

        # ============================================================
        # Publicadores
        # ============================================================
        self.cmd_blade_pub = self.create_publisher(Bool, '/esp32/cmd_blade', 10)

        # ============================================================
        # Suscriptores
        # ============================================================
        self.vision_sub = self.create_subscription(
            Bool,
            '/vision/enabled',
            self.vision_enabled_cb,
            10
        )

        self.grass_sub = self.create_subscription(
            String,
            '/grass_state',
            self.grass_state_cb,
            10
        )

        self.corte_nav_sub = self.create_subscription(
            Bool,
            '/navegacion/corte',
            self.corte_nav_cb,
            10
        )

        self.manual_blade_sub = self.create_subscription(
            Bool,
            '/vision/manual_blade_enable',
            self.manual_blade_hab_cb,
            10
        )

        # ============================================================
        # Timer: revisa timeout de grass_state aunque no lleguen mensajes
        # ============================================================
        check_period = float(self.get_parameter('check_period_s').value)
        self.check_timer = self.create_timer(check_period, self.update_blade)

        self.get_logger().info(
            'blade_node iniciado: vision desactivada, sin comandar brushless'
        )

    # ============================================================
    # Callbacks
    # ============================================================
    def vision_enabled_cb(self, msg):
        if msg.data == self.vision_enabled:
            return
        self.vision_enabled = msg.data

        if self.vision_enabled:
            self.get_logger().info('Vision ACTIVADA desde la app: blade_node toma control del brushless')
            self.update_blade()
        else:
            self.get_logger().info('Vision DESACTIVADA: blade_node usa solo solicitud de navegacion')
            self.update_blade()

    def grass_state_cb(self, msg):
        etiqueta = msg.data.split(',')[0].strip().lower()
        self.grass_detected = (etiqueta == self.grass_label)
        self.t_ultimo_grass = self.get_clock().now()
        self.update_blade()

    def corte_nav_cb(self, msg):
        self.corte_solicitado = bool(msg.data)
        self.update_blade()

    def manual_blade_hab_cb(self, msg):
        self.manual_blade_hab = bool(msg.data)
        self.update_blade()

    # ============================================================
    # Logica principal
    # ============================================================

    def grass_state_fresco(self):
        if self.t_ultimo_grass is None:
            return False
        edad = (self.get_clock().now() - self.t_ultimo_grass).nanoseconds * 1e-9
        return edad <= self.grass_timeout_s

    def update_blade(self):
        solicitud_corte = self.corte_solicitado or self.manual_blade_hab

        if not solicitud_corte:
            if self.ultimo_cmd is not False:
                self.publicar_cmd(False)
                self.get_logger().info('Brushless OFF: no hay solicitud de corte')
            return

        if self.manual_blade_hab:
            deseado = True
            motivo = 'solicitud manual desde app'

        elif self.vision_enabled:
            deseado = self.grass_detected and self.grass_state_fresco()
            motivo = (
                f'vision activa, pasto={self.grass_detected}, '
                f'dato_fresco={self.grass_state_fresco()}'
            )

        else:
            deseado = True
            motivo = 'vision desactivada, corte solicitado por navegacion'

        if deseado != self.ultimo_cmd:
            self.publicar_cmd(deseado)
            self.get_logger().info(
                f'Brushless {"ON" if deseado else "OFF"} ({motivo})'
            )

    def publicar_cmd(self, estado):
        self.cmd_blade_pub.publish(Bool(data=bool(estado)))
        self.ultimo_cmd = bool(estado)

    # ============================================================
    # Cierre seguro
    # ============================================================

    def destroy_node(self):
        try:
            if self.ultimo_cmd:
                self.cmd_blade_pub.publish(Bool(data=False))
        except Exception:
            pass
        super().destroy_node()

def main(args=None):
    rclpy.init(args=args)
    node = BladeNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando blade_node')
    finally:
        try:
            node.destroy_node()
        except Exception:
            pass
        if rclpy.ok():
            rclpy.shutdown()

if __name__ == '__main__':
    main()