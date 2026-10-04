#!/usr/bin/env python3
import math
import rclpy
from rclpy.node import Node
from std_msgs.msg import String, Bool, Float32MultiArray

class PerimetralNode(Node):
    """
    Nodo perimetral integrado con la app.

    Se activa solamente cuando:
        /navigation_app/mode == 'perimeter'
        /start == True

    No requiere:
        - cerco virtual
        - robot dentro del cerco

    Usa el orden que publica esp32_bridge_node en /sensors/ultrasonic:

        [us_left, us_center, us_right, us_diag_right, us_diag_left, us_back_right, us_back_left]

    Sensores usados:

        FC       = us_center      = ultrasonico delantero central
        RF       = us_right       = lateral derecho delantero
        RR_REAL  = us_back_right  = lateral derecho trasero real
        RR       = RR_REAL - correccion_rr_cm
    """

    # ==========================================================
    # Estados
    # ==========================================================
    E_ESPERANDO_MODO = 'Esperando modo perimetral'
    E_ESPERANDO_INICIO = 'Esperando inicio'
    E_ESPERANDO_DATOS = 'Esperando datos'
    E_SIGUIENDO_PARED = 'Siguiendo pared derecha'
    E_OBSTACULO_FRONTAL = 'Obstaculo frontal'
    E_CURVA_90_DERECHA = 'Curva 90 derecha'
    E_PARED_PERDIDA = 'Pared derecha perdida'

    def __init__(self):
        super().__init__('perimetral_node')
        self.nombre_modo = 'perimeter'

        # ==========================================================
        # Parametros de velocidad
        # ==========================================================
        self.declare_parameter('rpm_avance', 70.0)
        self.declare_parameter('rpm_lento', 60.0)
        self.declare_parameter('rpm_giro_frontal_izq', 70.0)
        self.declare_parameter('rpm_giro_curva_90', 70.0)

        # Rueda interna (derecha) durante la curva 90.
        # Debe ser menor que rpm_giro_curva_90 para que el robot doble en arco.
        self.declare_parameter('rpm_curva_90_interna', 25.0)
        self.declare_parameter('rpm_giro_busqueda', 90.0)
        self.declare_parameter('rpm_maximo', 140.0)

        # ==========================================================
        # Parametros de seguimiento de pared derecha
        # ==========================================================
        self.declare_parameter('distancia_pared_cm', 15.0)
        self.declare_parameter('tolerancia_pared_cm', 2.0)
        self.declare_parameter('pared_perdida_cm', 50.0)
        self.declare_parameter('lateral_seguro_min_cm', 10.0)

        # Correccion fija del sensor trasero derecho.
        # RR = RR_REAL - correccion_rr_cm
        self.declare_parameter('correccion_rr_cm', 10.0)

        # ==========================================================
        # Parametros del sensor delantero
        # ==========================================================
        self.declare_parameter('frontal_obstaculo_cm', 30.0)

        # El giro por obstaculo frontal sale recien cuando FC ve mas de
        # frontal_liberado_cm Y paso frontal_tiempo_min_s girando.
        # Valores altos para que el giro no quede corto: el FC deja de ver
        # el obstaculo mucho antes de que el robot realmente lo esquive.
        self.declare_parameter('frontal_liberado_cm', 60.0)
        self.declare_parameter('frontal_tiempo_min_s', 1.2)

        # ==========================================================
        # Parametros para detectar curva derecha de 90 grados
        # ==========================================================
        self.declare_parameter('curva_90_rf_entrada_cm', 40.0)
        self.declare_parameter('curva_90_rr_max_cm', 35.0)
        self.declare_parameter('curva_90_rf_salida_cm', 30.0)
        self.declare_parameter('curva_90_tiempo_min_s', 0.4)

        # ==========================================================
        # Parametros de control
        # ==========================================================
        self.declare_parameter('k_distancia', 0.5)
        self.declare_parameter('k_angulo', 0.45)
        self.declare_parameter('max_correccion_rpm', 25.0)

        # Si se pierde completamente la pared:
        # RF y RR estan muy lejos.
        self.declare_parameter('usar_giro_cerrado_si_pared_perdida', True)

        # ==========================================================
        # Parametros de tiempo
        # ==========================================================
        self.declare_parameter('frecuencia_control', 10.0)
        self.declare_parameter('periodo_estado_s', 0.25)
        self.declare_parameter('ultrasonic_timeout_s', 0.5)
        self.declare_parameter('debug_pausa_estado_s', 3.0)

        # ==========================================================
        # Lectura de parametros
        # ==========================================================
        self.rpm_avance = float(self.get_parameter('rpm_avance').value)
        self.rpm_lento = float(self.get_parameter('rpm_lento').value)
        self.rpm_giro_frontal_izq = float(self.get_parameter('rpm_giro_frontal_izq').value)
        self.rpm_giro_curva_90 = float(self.get_parameter('rpm_giro_curva_90').value)

        self.rpm_curva_90_interna = float(self.get_parameter('rpm_curva_90_interna').value)
        if self.rpm_curva_90_interna < 0.0:
            self.rpm_curva_90_interna = 0.0
        if self.rpm_curva_90_interna >= self.rpm_giro_curva_90:
            self.rpm_curva_90_interna = self.rpm_giro_curva_90 * 0.5
        self.rpm_giro_busqueda = float(self.get_parameter('rpm_giro_busqueda').value)
        self.max_rpm = float(self.get_parameter('rpm_maximo').value)

        self.distancia_pared_cm = float(self.get_parameter('distancia_pared_cm').value)
        self.tolerancia_pared_cm = float(self.get_parameter('tolerancia_pared_cm').value)
        self.pared_perdida_cm = float(self.get_parameter('pared_perdida_cm').value)
        self.lateral_seguro_min_cm = float(self.get_parameter('lateral_seguro_min_cm').value)

        self.correccion_rr_cm = float(self.get_parameter('correccion_rr_cm').value)
        if self.correccion_rr_cm < 0.0:
            self.correccion_rr_cm = 0.0

        self.frontal_obstaculo_cm = float(self.get_parameter('frontal_obstaculo_cm').value)
        self.frontal_liberado_cm = float(self.get_parameter('frontal_liberado_cm').value)
        self.frontal_tiempo_min_s = float(self.get_parameter('frontal_tiempo_min_s').value)

        if self.frontal_liberado_cm < self.frontal_obstaculo_cm:
            self.frontal_liberado_cm = self.frontal_obstaculo_cm + 10.0

        self.curva_90_rf_entrada_cm = float(self.get_parameter('curva_90_rf_entrada_cm').value)
        self.curva_90_rr_max_cm = float(self.get_parameter('curva_90_rr_max_cm').value)
        self.curva_90_rf_salida_cm = float(self.get_parameter('curva_90_rf_salida_cm').value)
        self.curva_90_tiempo_min_s = float(self.get_parameter('curva_90_tiempo_min_s').value)

        self.k_distancia = float(self.get_parameter('k_distancia').value)
        self.k_angulo = float(self.get_parameter('k_angulo').value)
        self.max_correccion_rpm = float(self.get_parameter('max_correccion_rpm').value)

        self.usar_giro_cerrado_si_pared_perdida = bool(self.get_parameter('usar_giro_cerrado_si_pared_perdida').value)

        self.frecuencia_control = float(self.get_parameter('frecuencia_control').value)
        self.periodo_estado_s = float(self.get_parameter('periodo_estado_s').value)
        self.ultrasonic_timeout_s = float(self.get_parameter('ultrasonic_timeout_s').value)
        self.debug_pausa_estado_s = float(self.get_parameter('debug_pausa_estado_s').value)

        if self.max_correccion_rpm > self.rpm_avance:
            self.max_correccion_rpm = self.rpm_avance

        # ==========================================================
        # Datos recibidos desde la app / ROS
        # ==========================================================
        self.modo_actual = ''
        self.inicio = False

        # ==========================================================
        # Datos de ultrasonicos
        # ==========================================================
        self.us = {
            'FC': None,
            'RF': None,
            'RR_REAL': None,
            'RR': None,
        }

        self.t_ultimo_us = None

        # ==========================================================
        # Estado interno
        # ==========================================================
        self.estado = self.E_ESPERANDO_MODO
        self.t_entrada_estado = self.get_clock().now()
        self.razon_estado = ''

        self.debug_pausando = False
        self.debug_t_inicio_pausa = None

        self.ultimo_d_prom = 0.0
        self.ultimo_error_dist = 0.0
        self.ultimo_error_ang = 0.0
        self.ultima_correccion = 0.0
        self.ultimo_rpm_izq = 0.0
        self.ultimo_rpm_der = 0.0

        # Evita spamear el serial con paradas repetidas.
        self.parada_enviada = False

        # Estado del trimmer para publicar solo cuando cambia.
        self.trimmer_encendido = False

        # ==========================================================
        # Publicadores
        # ==========================================================
        self.pub_estado = self.create_publisher(String, '/perimetral/status', 10)
        self.pub_debug = self.create_publisher(String, '/perimetral/debug', 10)
        self.pub_cmd_motores = self.create_publisher(Float32MultiArray, '/esp32/cmd_motores', 10)
        self.pub_cmd_trimmer = self.create_publisher(Bool, '/esp32/cmd_trimmer', 10)

        # ==========================================================
        # Suscriptores
        # ==========================================================
        self.sub_modo = self.create_subscription(String, '/navigation_app/mode', self.callback_modo, 10)
        self.sub_start = self.create_subscription(Bool, '/start', self.callback_start, 10)
        self.sub_ultrasonicos = self.create_subscription(Float32MultiArray, '/sensors/ultrasonic', self.callback_ultrasonicos, 10)

        # ==========================================================
        # Timer principal
        # ==========================================================
        self.control_timer = self.create_timer(1.0 / self.frecuencia_control, self.control_loop)
        self.timer_estado = self.create_timer(self.periodo_estado_s, self.publicar_estado)
        self.get_logger().info('perimetral_node iniciado')
        # self.publicar_debug('Orden recibido desde bridge: '
        # '[us_left, us_center, us_right, us_diag_right, us_diag_left, us_back_right, us_back_left]')
        # self.publicar_debug('Usando: FC=us_center, RF=us_right, RR_REAL=us_back_right')
        # self.publicar_debug(f'Correccion fija: RR = RR_REAL - {self.correccion_rr_cm:.1f}cm')

    # ==========================================================
    # Callbacks
    # ==========================================================
    def callback_modo(self, msg):
        nuevo_modo = msg.data.strip()
        if nuevo_modo != self.modo_actual:
            self.publicar_debug(f'Modo recibido: {nuevo_modo}')
        self.modo_actual = nuevo_modo

    def callback_start(self, msg):
        nuevo_inicio = bool(msg.data)
        if nuevo_inicio != self.inicio:
            self.publicar_debug(
                'Inicio recibido' if nuevo_inicio else 'Movimiento detenido'
            )
        self.inicio = nuevo_inicio

    def callback_ultrasonicos(self, msg):
        data = msg.data
        if len(data) < 6:
            return
        us_center = float(data[1])
        us_right = float(data[2])
        us_back_right = float(data[5])

        if us_center <= 0.0:
            us_center = 999.9

        if us_right <= 0.0:
            us_right = 999.9

        if us_back_right <= 0.0:
            us_back_right = 999.9

        FC = us_center
        RF = us_right
        RR_REAL = us_back_right
        RR = RR_REAL - self.correccion_rr_cm

        if RR <= 0.0:
            RR = 0.1

        self.us['FC'] = FC
        self.us['RF'] = RF
        self.us['RR_REAL'] = RR_REAL
        self.us['RR'] = RR

        self.t_ultimo_us = self.get_clock().now()

    # ==========================================================
    # Loop principal
    # ==========================================================

    def control_loop(self):
        entradas = self.leer_entradas()

        # El trimmer queda prendido mientras el modo perimetral este activo y haya start.
        self.activar_trimmer(entradas)

        # Pausa obligatoria después de cada transición.
        # Durante la pausa, el robot queda detenido.
        if self.debug_pausando:
            self.parada()

            ahora = self.get_clock().now()
            tiempo_pausa = (ahora - self.debug_t_inicio_pausa).nanoseconds * 1e-9

            if tiempo_pausa >= self.debug_pausa_estado_s:
                self.debug_pausando = False
                self.t_entrada_estado = ahora

            self.publicar_estado()
            return

        nuevo_estado = self.controlador(entradas)

        if nuevo_estado != self.estado:
            estado_anterior = self.estado
            self.estado = nuevo_estado
            self.t_entrada_estado = self.get_clock().now()

            self.entrar_estado(estado_anterior, nuevo_estado)

            self.parada()
            self.debug_pausando = True
            self.debug_t_inicio_pausa = self.get_clock().now()

            return

        self.camino_datos()
        self.publicar_estado()

    # ==========================================================
    # Lectura de entradas
    # ==========================================================

    def leer_entradas(self):
        datos_ok = self.datos_ultrasonicos_ok()

        if not datos_ok:
            return {
                'perimetral': self.modo_actual == self.nombre_modo,
                'inicio': self.inicio,
                'datos_ok': False,
            }

        FC = self.us['FC']
        RF = self.us['RF']
        RR = self.us['RR']

        obstaculo_frontal = FC <= self.frontal_obstaculo_cm
        frontal_liberado = FC >= self.frontal_liberado_cm

        curva_90_derecha = (
            RF > self.curva_90_rf_entrada_cm and
            RR <= self.curva_90_rr_max_cm
        )

        curva_90_recuperada = RF <= self.curva_90_rf_salida_cm

        pared_perdida = (
            RF > self.pared_perdida_cm and
            RR > self.pared_perdida_cm
        )

        lateral_muy_cerca = (
            self.obstaculo_por_us(RF, self.lateral_seguro_min_cm) or
            self.obstaculo_por_us(RR, self.lateral_seguro_min_cm)
        )

        return {
            'perimetral': self.modo_actual == self.nombre_modo,
            'inicio': self.inicio,
            'datos_ok': True,
            'obstaculo_frontal': obstaculo_frontal,
            'frontal_liberado': frontal_liberado,
            'curva_90_derecha': curva_90_derecha,
            'curva_90_recuperada': curva_90_recuperada,
            'pared_perdida': pared_perdida,
            'lateral_muy_cerca': lateral_muy_cerca,
        }

    # ==========================================================
    # Controlador de estados
    # ==========================================================

    def controlador(self, entradas):
        self.razon_estado = ''

        if not entradas['perimetral']:
            self.razon_estado = f'Modo actual no es {self.nombre_modo}: modo_actual={self.modo_actual}'
            return self.E_ESPERANDO_MODO

        if not entradas['inicio']:
            self.razon_estado = 'Start/inicio no activado'
            return self.E_ESPERANDO_INICIO

        if not entradas['datos_ok']:
            self.razon_estado = 'Sin datos validos de ultrasonicos'
            return self.E_ESPERANDO_DATOS

        if self.estado in [
            self.E_ESPERANDO_MODO,
            self.E_ESPERANDO_INICIO,
            self.E_ESPERANDO_DATOS,
        ]:
            self.razon_estado = 'Condiciones iniciales cumplidas, pasa a seguir pared'
            return self.E_SIGUIENDO_PARED

        if self.estado == self.E_OBSTACULO_FRONTAL:
            if (
                self.tiempo_en_estado() >= self.frontal_tiempo_min_s and
                entradas['frontal_liberado']
            ):
                self.razon_estado = (
                    f'Frente liberado: FC={self.fmt_cm(self.us["FC"])}, '
                    f'tiempo={self.tiempo_en_estado():.2f}s'
                )
                return self.E_SIGUIENDO_PARED

            self.razon_estado = (
                f'Sigue girando por obstaculo frontal: FC={self.fmt_cm(self.us["FC"])}, '
                f'tiempo={self.tiempo_en_estado():.2f}s'
            )
            return self.E_OBSTACULO_FRONTAL

        if entradas['obstaculo_frontal']:
            self.razon_estado = (
                f'FC detecta obstaculo: FC={self.fmt_cm(self.us["FC"])} '
                f'<= {self.frontal_obstaculo_cm:.1f}cm, girar izquierda'
            )
            return self.E_OBSTACULO_FRONTAL

        if self.estado == self.E_CURVA_90_DERECHA:
            if (
                self.tiempo_en_estado() >= self.curva_90_tiempo_min_s and
                entradas['curva_90_recuperada']
            ):
                self.razon_estado = (
                    f'RF volvio a detectar pared: RF={self.fmt_cm(self.us["RF"])}, '
                    f'tiempo={self.tiempo_en_estado():.2f}s'
                )
                return self.E_SIGUIENDO_PARED

            self.razon_estado = (
                f'Sigue curva 90: RF={self.fmt_cm(self.us["RF"])}, '
                f'RR_CORR={self.fmt_cm(self.us["RR"])}, '
                f'tiempo={self.tiempo_en_estado():.2f}s'
            )
            return self.E_CURVA_90_DERECHA

        if entradas['curva_90_derecha']:
            self.razon_estado = (
                f'RF lejos y RR_CORR cerca: RF={self.fmt_cm(self.us["RF"])}, '
                f'RR_CORR={self.fmt_cm(self.us["RR"])}, curva derecha de 90 grados'
            )
            return self.E_CURVA_90_DERECHA

        if entradas['pared_perdida']:
            self.razon_estado = (
                f'RF y RR_CORR lejos: RF={self.fmt_cm(self.us["RF"])}, '
                f'RR_CORR={self.fmt_cm(self.us["RR"])}, pared derecha perdida'
            )
            return self.E_PARED_PERDIDA

        if entradas['lateral_muy_cerca']:
            self.razon_estado = (
                f'Pared derecha muy cerca: RF={self.fmt_cm(self.us["RF"])}, '
                f'RR_CORR={self.fmt_cm(self.us["RR"])}, corrige hacia izquierda sin retroceder'
            )
            return self.E_SIGUIENDO_PARED

        self.razon_estado = (
            f'Sin eventos, sigue pared: FC={self.fmt_cm(self.us["FC"])}, '
            f'RF={self.fmt_cm(self.us["RF"])}, RR_CORR={self.fmt_cm(self.us["RR"])}'
        )
        return self.E_SIGUIENDO_PARED

    # ==========================================================
    # Acciones al entrar en estados
    # ==========================================================

    def entrar_estado(self, estado_anterior, estado_nuevo):
        detalle = f' | razon: {self.razon_estado}' if self.razon_estado else ''
        self.publicar_debug(
            f'Transicion: {estado_anterior} -> {estado_nuevo}{detalle}'
        )

    # ==========================================================
    # Acciones por estado
    # ==========================================================

    def camino_datos(self):
        if self.estado == self.E_SIGUIENDO_PARED:
            rpm_izq, rpm_der = self.control_seguimiento_pared()
            self.publicar_rpm_sin_reversa(rpm_izq, rpm_der)

        elif self.estado == self.E_OBSTACULO_FRONTAL:
            rpm_izq, rpm_der = self.control_obstaculo_frontal()
            self.publicar_rpm(rpm_izq, rpm_der)

        elif self.estado == self.E_CURVA_90_DERECHA:
            rpm_izq, rpm_der = self.control_curva_90_derecha()
            self.publicar_rpm(rpm_izq, rpm_der)

        elif self.estado == self.E_PARED_PERDIDA:
            rpm_izq, rpm_der = self.control_buscar_pared()
            self.publicar_rpm(rpm_izq, rpm_der)

        else:
            self.parada()

    # ==========================================================
    # Control de seguimiento de pared derecha
    # ==========================================================

    def control_seguimiento_pared(self):
        RF = self.us['RF']
        RR = self.us['RR']

        d_prom = (RF + RR) / 2.0
        error_dist = self.distancia_pared_cm - d_prom

        if abs(error_dist) <= self.tolerancia_pared_cm:
            error_dist_control = 0.0
        else:
            error_dist_control = error_dist - math.copysign(
                self.tolerancia_pared_cm,
                error_dist
            )

        error_ang = RR - RF

        correccion = (
            self.k_distancia * error_dist_control +
            self.k_angulo * error_ang
        )

        correccion = self.limite(
            correccion,
            -self.max_correccion_rpm,
            self.max_correccion_rpm
        )

        correccion = self.aplicar_limitaciones_de_seguridad(correccion)

        self.ultimo_d_prom = d_prom
        self.ultimo_error_dist = error_dist
        self.ultimo_error_ang = error_ang
        self.ultima_correccion = correccion

        rpm_izq = self.rpm_avance - correccion
        rpm_der = self.rpm_avance + correccion

        return rpm_izq, rpm_der

    def aplicar_limitaciones_de_seguridad(self, correccion):
        RF = self.us['RF']
        RR = self.us['RR']

        espacio_der_chico = (
            self.obstaculo_por_us(RF, self.lateral_seguro_min_cm) or
            self.obstaculo_por_us(RR, self.lateral_seguro_min_cm)
        )

        if correccion < 0.0 and espacio_der_chico:
            correccion = 0.0

        return correccion

    def control_obstaculo_frontal(self):
        # Giro pivotante hacia la izquierda sobre el propio eje:
        # rueda izquierda retrocede y rueda derecha avanza.
        rpm_izq = -self.rpm_giro_frontal_izq
        rpm_der = self.rpm_giro_frontal_izq

        self.ultima_correccion = abs(rpm_der - rpm_izq) / 2.0

        return rpm_izq, rpm_der

    def control_curva_90_derecha(self):
        # Giro en arco hacia la derecha:
        # la rueda izquierda (externa) avanza rapido y la derecha (interna)
        # avanza lento. Ninguna retrocede, asi el robot rodea la esquina
        # con radio en vez de pivotar en el lugar y barrer contra la pared.
        rpm_izq = self.rpm_giro_curva_90
        rpm_der = self.rpm_curva_90_interna

        self.ultima_correccion = -abs(rpm_izq - rpm_der) / 2.0

        return rpm_izq, rpm_der

    def control_buscar_pared(self):
        # Giro pivotante hacia la derecha sobre el propio eje.
        if self.usar_giro_cerrado_si_pared_perdida:
            rpm_izq = self.rpm_giro_busqueda
            rpm_der = -self.rpm_giro_busqueda
        else:
            rpm_izq = self.rpm_lento + self.rpm_giro_busqueda
            rpm_der = self.rpm_lento

        self.ultima_correccion = -abs(rpm_izq - rpm_der) / 2.0

        return rpm_izq, rpm_der

    # ==========================================================
    # Utilidades
    # ==========================================================

    def datos_ultrasonicos_ok(self):
        if self.t_ultimo_us is None:
            return False

        ahora = self.get_clock().now()
        edad = (ahora - self.t_ultimo_us).nanoseconds * 1e-9

        if edad > self.ultrasonic_timeout_s:
            return False

        requeridos = ['FC', 'RF', 'RR_REAL', 'RR']

        for nombre in requeridos:
            if not self.valid_distance(self.us[nombre]):
                return False

        return True

    def publicar_rpm_sin_reversa(self, rpm_izq, rpm_der):
        rpm_izq = self.limite(rpm_izq, 0.0, self.max_rpm)
        rpm_der = self.limite(rpm_der, 0.0, self.max_rpm)
        self.publicar_rpm(rpm_izq, rpm_der)

    def publicar_rpm(self, rpm_izq, rpm_der):
        rpm_izq = self.limite(rpm_izq, -self.max_rpm, self.max_rpm)
        rpm_der = self.limite(rpm_der, -self.max_rpm, self.max_rpm)

        self.ultimo_rpm_izq = rpm_izq
        self.ultimo_rpm_der = rpm_der

        es_parada = abs(rpm_izq) < 1e-3 and abs(rpm_der) < 1e-3
        if es_parada and self.parada_enviada:
            return

        self.pub_cmd_motores.publish(
            Float32MultiArray(data=[rpm_izq, rpm_der])
        )

        self.parada_enviada = es_parada

    def parada(self):
        self.publicar_rpm(0.0, 0.0)

    def activar_trimmer(self, entradas):
        encender = entradas['perimetral'] and entradas['inicio']

        if encender != self.trimmer_encendido:
            self.publicar_trimmer(encender)
            self.trimmer_encendido = encender

            estado = 'encendido' if encender else 'apagado'
            self.publicar_debug(f'Trimmer {estado}')

    def publicar_trimmer(self, encendido):
        self.pub_cmd_trimmer.publish(Bool(data=bool(encendido)))

    def publish_stop_burst(self):
        for _ in range(8):
            if not rclpy.ok():
                return

            self.parada()
            rclpy.spin_once(self, timeout_sec=0.02)

    def publicar_estado(self):
        msg = String()

        msg.data = (
            f'estado={self.estado}, '
            f'razon={self.razon_estado}, '
            f'modo={self.modo_actual}, '
            f'start={self.inicio}, '
            f'pausa={self.debug_pausando}, '
            f'parada_enviada={self.parada_enviada}, '
            f'trimmer={self.trimmer_encendido}, '
            f'FC={self.fmt_cm(self.us["FC"])}, '
            f'RF={self.fmt_cm(self.us["RF"])}, '
            f'RR_REAL={self.fmt_cm(self.us["RR_REAL"])}, '
            f'RR_CORR={self.fmt_cm(self.us["RR"])}, '
            f'd_prom={self.ultimo_d_prom:.1f}, '
            f'k_dist={self.k_distancia:.2f}, '
            f'k_ang={self.k_angulo:.2f}, '
            f'corr={self.ultima_correccion:.2f}, '
            f'rpm_izq={self.ultimo_rpm_izq:.1f}, '
            f'rpm_der={self.ultimo_rpm_der:.1f}'
        )

        self.pub_estado.publish(msg)

    def publicar_debug(self, texto):
        self.pub_debug.publish(String(data=texto))
        self.get_logger().info(texto)

    def obstaculo_por_us(self, valor, umbral_cm):
        return valor is not None and valor > 0.0 and valor <= umbral_cm

    def valid_distance(self, valor):
        return valor is not None and valor > 0.0 and math.isfinite(valor)

    def tiempo_en_estado(self):
        ahora = self.get_clock().now()
        return (ahora - self.t_entrada_estado).nanoseconds * 1e-9

    def limite(self, valor, minimo, maximo):
        return max(minimo, min(valor, maximo))

    def fmt_cm(self, valor):
        if valor is None:
            return 'S/D'
        return f'{valor:.1f}cm'

    def destroy_node(self):
        try:
            self.publicar_trimmer(False)
            self.trimmer_encendido = False
            self.publish_stop_burst()
        except Exception:
            pass

        super().destroy_node()

def main(args=None):
    rclpy.init(args=args)
    node = PerimetralNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando perimetral_node')
    finally:
        try:
            node.destroy_node()
        except Exception:
            pass
        try:
            rclpy.shutdown()
        except Exception:
            pass

if __name__ == '__main__':
    main()