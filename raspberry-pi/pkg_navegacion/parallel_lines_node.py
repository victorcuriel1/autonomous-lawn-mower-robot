#!/usr/bin/env python3

import math
import rclpy
from rclpy.node import Node
from std_msgs.msg import String, Bool, Float32MultiArray, Int32, Float32MultiArray, Int32MultiArray


class ParallelLinesNode(Node):
    def __init__(self):
        super().__init__('parallel_lines_node')
        self.nombre_modo = 'parallel_lines'

        # Parámetros generales
        # ============================================================
        self.declare_parameter('rpm_maximo', 150)
        self.declare_parameter('velocidad_avance', 90)
        self.declare_parameter('velocidad_lateral',80)
        self.declare_parameter('tiempo_lateral_s', 3.0)

        # Control PI para avance recto
        self.declare_parameter('kp_avance', 1.0)
        self.declare_parameter('ki_avance', 0.03)
        self.declare_parameter('max_correccion_rpm', 30.0)
        self.declare_parameter('signo_correccion', 1.0)

        # Frecuencias y timeouts
        self.declare_parameter('frecuencia_control', 5.0)
        self.declare_parameter('periodo_estado', 0.25)
        self.declare_parameter('imu_timeout_s', 0.5)

        # Obstáculos y bumpers
        self.declare_parameter('distancia_obstaculo', 40.0)
        self.declare_parameter('bumper_activo', 1)

        # Giro con control P pivotante
        self.declare_parameter('angulo_giro', 75.0)
        self.declare_parameter('tolerancia_giro_grados', 5.0)
        self.declare_parameter('kp_giro', 0.4)
        self.declare_parameter('rpm_giro_min', 70.0)
        self.declare_parameter('rpm_giro_max', 90)
        self.declare_parameter('lado_giro_inicial', 1.0)
        self.declare_parameter('signo_motor_giro', 1.0)
        self.declare_parameter('tiempo_pausa_post_giro_s', 0.8)

        # Escape por bumper
        # Se usa tanto para retroceder como para avanzar.
        self.declare_parameter('tiempo_retroceso_bumper_s', 3.0)
        self.declare_parameter('rpm_retroceso_bumper', 25.0)

        # Estados internos
        # ============================================================
        self.modo_actual = ''
        self.estado = 'Esperando modo'
        self.estado_inicio_time = self.get_clock().now()
        self.razon_estado = ''
        self.sentido_giro_actual = 0.0

        self.cerco_valido = False
        self.start = False
        self.dentro_del_cerco = None
        self.parada_enviada = False

        # Ultrasonidos
        self.us_frente = None
        self.us_der = None
        self.us_izq = None

        self.obs_frente = False
        self.obs_der = False
        self.obs_izq = False

        # Bumpers
        self.bumpers = [False, False, False, False]
        self.bumper_activado = False
        self.bumper_bloqueado = False

        self.direccion_escape_bumper = 0.0
        self.giro_despues_escape = None
        self.motivo_bumper = ''

        # IMU
        self.orientacion_grados = 0.0
        self.tiempo_ult_imu = None

        # Avance recto
        self.orientacion_objetivo = 0.0
        self.integral_orientacion = 0.0
        self.avance_activo = False

        # Giro
        self.objetivo_giro = 0.0
        self.estado_despues_giro = 'Avanzando'
        self.invertir_lado_despues_giro = False
        self.lado_giro_actual = 1.0

        self.blade_encendido = False  

        # Lectura de parámetros
        # ============================================================
        self.max_rpm = float(self.get_parameter('rpm_maximo').value)

        self.vel_avance = float(self.get_parameter('velocidad_avance').value)
        self.velocidad_lateral = float(self.get_parameter('velocidad_lateral').value)
        self.tiempo_lateral_s = float(self.get_parameter('tiempo_lateral_s').value)

        self.kp_avance = float(self.get_parameter('kp_avance').value)
        self.ki_avance = float(self.get_parameter('ki_avance').value)
        self.max_correccion_rpm = float(self.get_parameter('max_correccion_rpm').value)
        self.signo_correccion = float(self.get_parameter('signo_correccion').value)

        self.frecuencia_control = float(self.get_parameter('frecuencia_control').value)
        self.periodo_estado = float(self.get_parameter('periodo_estado').value)
        self.imu_timeout_s = float(self.get_parameter('imu_timeout_s').value)

        self.distancia_obstaculo = float(self.get_parameter('distancia_obstaculo').value)
        self.bumper_activo = int(self.get_parameter('bumper_activo').value)

        self.angulo_giro = float(self.get_parameter('angulo_giro').value)
        self.tolerancia_giro_grados = float(self.get_parameter('tolerancia_giro_grados').value)
        self.kp_giro = float(self.get_parameter('kp_giro').value)
        self.rpm_giro_min = float(self.get_parameter('rpm_giro_min').value)
        self.rpm_giro_max = float(self.get_parameter('rpm_giro_max').value)

        self.lado_giro_actual = float(self.get_parameter('lado_giro_inicial').value)
        self.signo_motor_giro = float(self.get_parameter('signo_motor_giro').value)
        self.tiempo_pausa_post_giro_s = float(self.get_parameter('tiempo_pausa_post_giro_s').value)

        self.tiempo_retroceso_bumper_s = float(self.get_parameter('tiempo_retroceso_bumper_s').value)
        self.rpm_retroceso_bumper = float(self.get_parameter('rpm_retroceso_bumper').value)

        # Publicadores
        # ============================================================
        self.pub_estado = self.create_publisher(String, '/parallel_lines/status', 10)
        self.pub_debug = self.create_publisher(String, '/parallel_lines/debug', 10)
        self.pub_cmd_motores = self.create_publisher(Float32MultiArray, '/esp32/cmd_motores', 10)
        self.pub_cmd_blade = self.create_publisher(Bool, '/esp32/cmd_blade', 10)

        # Suscripciones
        # ============================================================
        self.sub_modo = self.create_subscription( String,'/navigation_app/mode',self.callback_modo,10)
        self.sub_cerco_valido = self.create_subscription( Bool,'/fencenode/valid',self.callback_cerco_valido,10)
        self.sub_start = self.create_subscription( Bool,'/start',self.callback_start, 10 )
        self.sub_dentro_del_cerco = self.create_subscription(Int32,'/fencenode/robot_dentro',self.callback_dentro_del_cerco,10)
        self.sub_angulos_imu = self.create_subscription( Float32MultiArray,'/imu/angles', self.callback_angulos_imu, 10)
        self.sub_ultrasonico = self.create_subscription( Float32MultiArray, '/sensors/ultrasonic', self.callback_ultrasonico, 10)
        self.sub_bumper = self.create_subscription( Int32MultiArray, '/sensors/limit_switches', self.callback_bumper, 10 )

        # Timers
        # ============================================================
        self.timer_estado = self.create_timer(self.periodo_estado,self.publicar_estado)
        self.control_timer = self.create_timer(1.0 / self.frecuencia_control, self.control_loop )
        self.get_logger().info('Parallel_lines_node iniciado')

    # Callbacks
    # ============================================================
    def callback_modo(self, msg):
        self.modo_actual = msg.data.strip()
        self.publicar_debug(f'Modo recibido: {self.modo_actual}')

    def callback_cerco_valido(self, msg):
        self.cerco_valido = bool(msg.data)

    def callback_start(self, msg):
        self.start = bool(msg.data)
        if not self.start:
            self.parada()
            self.salir_modo_avance()
            self.lado_giro_actual = float(self.get_parameter('lado_giro_inicial').value)
            self.cambiar_estado('Esperando inicio')
        else:
            self.publicar_debug('Inicio recibido.')

    def callback_dentro_del_cerco(self, msg):
        self.dentro_del_cerco = bool(msg.data)

    def callback_angulos_imu(self, msg): 
        if len(msg.data) < 3:
            return
        self.orientacion_grados = float(msg.data[2])
        self.tiempo_ult_imu = self.get_clock().now()

    def callback_ultrasonico(self, msg):
        if len(msg.data) < 3:
            return
        self.us_izq = float(msg.data[0])
        self.us_frente = float(msg.data[1])
        self.us_der = float(msg.data[2])

        self.obs_frente = ( self.us_frente > 0.0 and self.us_frente <= self.distancia_obstaculo)
        self.obs_izq = ( self.us_izq > 0.0 and self.us_izq <= self.distancia_obstaculo)
        self.obs_der = ( self.us_der > 0.0 and self.us_der <= self.distancia_obstaculo)

    def callback_bumper(self, msg):
        # [izquierda, derecha, atras, frente, dw]
        valores_sucios = [int(v) for v in msg.data]
        valores = valores_sucios[:-1]
        self.bumpers = [v == self.bumper_activo for v in valores]
        self.bumper_activado = any(self.bumpers)

        if not self.bumper_activado:
            self.bumper_bloqueado = False

    # Utilidades
    # ============================================================
    def cambiar_estado(self, nuevo_estado, motivo=''):
        if self.estado == nuevo_estado:
            return
        anterior = self.estado
        self.estado = nuevo_estado
        self.estado_inicio_time = self.get_clock().now()

        detalle = f': {motivo}' if motivo else ''
        self.publicar_debug(f'Transicion: {anterior} -> {nuevo_estado}{detalle}')

    def tiempo_en_estado(self):
        ahora = self.get_clock().now()
        return (ahora - self.estado_inicio_time).nanoseconds * 1e-9

    def parada(self):
        if self.parada_enviada:
            return
        self.pub_cmd_motores.publish(Float32MultiArray(data=[0.0, 0.0]))
        self.parada_enviada = True

    def limite(self, value, minimo, maximo):
        return max(minimo, min(value, maximo))

    def normalizar_angulo(self, angulo):
        while angulo > 180.0:
            angulo -= 360.0
        while angulo < -180.0:
            angulo += 360.0
        return angulo

    def salir_modo_avance(self):
        self.avance_activo = False
        self.integral_orientacion = 0.0

    def publicar_rpm(self, rpm_izq, rpm_der):
        rpm_izq = self.limite(rpm_izq, -self.max_rpm, self.max_rpm)
        rpm_der = self.limite(rpm_der, -self.max_rpm, self.max_rpm)
        self.pub_cmd_motores.publish(Float32MultiArray(data=[rpm_izq, rpm_der]))
        self.parada_enviada = False
    
    def activar_blade(self):
        activar = (
            self.modo_actual == self.nombre_modo
            and self.start
            and self.cerco_valido
            and self.dentro_del_cerco is True
        )

        if activar != self.blade_encendido:
            msg = Bool()
            msg.data = activar
            self.pub_cmd_blade.publish(msg)

            self.blade_encendido = activar

            estado = 'encendido' if activar else 'apagado'
            self.publicar_debug(f'Corte {estado}')

    def publicar_estado(self, txt=None):
        estado_txt = txt if txt is not None else self.estado
        giro_txt = 'sin'
        if self.estado == 'Girando':
            giro_txt = self.texto_giro(self.sentido_giro_actual)

        msg = (
            f'estado = {estado_txt}, '
            f'modo = {self.modo_actual}, '
            f'start = {self.start}, '
            f'cerco = {self.cerco_valido}, '
            f'dentro_cerco = {self.dentro_del_cerco}, '
            f'orientacion_objetivo = {self.objetivo_giro:.1f}, '
            f'orientacion_actual = {self.orientacion_grados:.1f}, '
            f'giro = {giro_txt}'
        )
        self.pub_estado.publish(String(data=msg))

    def publicar_debug(self, text):
        self.pub_debug.publish(String(data=text))

    def texto_giro(self, signo):
        if signo > 0:
            return 'izquierda'
        if signo < 0:
            return 'derecha'
        return 'sin'

    # Avance recto PI
    # ============================================================
    def control_avance(self, rpm_base, etiqueta_estado='Avanzando'):
        if not self.avance_activo:
            self.orientacion_objetivo = self.orientacion_grados
            self.integral_orientacion = 0.0
            self.avance_activo = True

        dt = 1.0 / self.frecuencia_control
        error_orientacion = self.normalizar_angulo(  self.orientacion_objetivo - self.orientacion_grados)
        self.integral_orientacion += error_orientacion * dt
        max_integral = self.max_correccion_rpm / max(self.ki_avance, 1e-6)
        self.integral_orientacion = self.limite( self.integral_orientacion, -max_integral, max_integral)
        
        correccion_rpm = (self.kp_avance * error_orientacion + self.ki_avance * self.integral_orientacion )
        correccion_rpm *= self.signo_correccion
        correccion_rpm = self.limite( correccion_rpm, -self.max_correccion_rpm, self.max_correccion_rpm )

        rpm_izq = rpm_base - correccion_rpm
        rpm_der = rpm_base + correccion_rpm
        self.publicar_rpm(rpm_izq, rpm_der)

    # Giro único reutilizable
    # ============================================================
    def iniciar_giro(self, signo_giro, estado_despues_giro, invertir_lado=False):
        self.parada()
        self.salir_modo_avance()

        self.sentido_giro_actual = signo_giro
        self.objetivo_giro = self.normalizar_angulo(
            self.orientacion_grados + signo_giro * self.angulo_giro
        )
        self.estado_despues_giro = estado_despues_giro
        self.invertir_lado_despues_giro = invertir_lado

        self.cambiar_estado(
            'Girando',
            f'sentido = {self.texto_giro(signo_giro)}, '
            f'actual = {self.orientacion_grados:.1f}, '
            f'objetivo = {self.objetivo_giro:.1f}'
        )

    def control_giro(self):
        error = self.normalizar_angulo(self.objetivo_giro - self.orientacion_grados)
        if abs(error) <= self.tolerancia_giro_grados:
            self.parada()
            self.salir_modo_avance()

            self.obs_frente = False
            self.obs_izq = False
            self.obs_der = False

            self.cambiar_estado('Pausa post giro')

            return

        rpm_giro = self.kp_giro * abs(error)
        rpm_giro = self.limite(rpm_giro, self.rpm_giro_min, self.rpm_giro_max)
        direccion = 1.0 if error > 0.0 else -1.0
        direccion *= self.signo_motor_giro

        if direccion > 0.0:
            rpm_izq = -rpm_giro
            rpm_der = rpm_giro
        else:
            rpm_izq = rpm_giro
            rpm_der = -rpm_giro

        self.publicar_rpm(rpm_izq, rpm_der)

    # Escape por bumper
    # ============================================================
    def iniciar_escape_bumper(self, direccion_escape, signo_giro_despues = None, motivo = 'Bumper'):
        self.parada()
        self.salir_modo_avance()

        self.direccion_escape_bumper = direccion_escape
        self.giro_despues_escape = signo_giro_despues
        self.motivo_bumper = motivo
        self.bumper_bloqueado = True

        self.cambiar_estado('Escape bumper', motivo)

    def control_escape_bumper(self):
        transcurrido = self.tiempo_en_estado()
        if transcurrido >= self.tiempo_retroceso_bumper_s:
            self.parada()
            self.salir_modo_avance()
            if self.bumper_activado:
                self.cambiar_estado('Esperando a que el bumper se libere')
                return
            if self.giro_despues_escape is not None:
                signo = self.giro_despues_escape
                self.giro_despues_escape = None
                self.iniciar_giro(signo_giro = signo, estado_despues_giro = 'Avance lateral', invertir_lado = False)
                return
            self.cambiar_estado('Avanzando')
            return

        rpm = abs(self.rpm_retroceso_bumper) * self.direccion_escape_bumper
        self.publicar_rpm(rpm, rpm)

    # Verificaciones generales
    # ============================================================
    def verificacion_ok(self):
        ahora = self.get_clock().now()
        if self.modo_actual != self.nombre_modo:
            self.estado = 'Esperando modo'
        elif not self.cerco_valido:
            self.estado = 'Esperando cerco'
        elif self.dentro_del_cerco is None:
            self.estado = 'Esperando al robot dentro'
        elif self.dentro_del_cerco is False:
            self.estado = 'Robot fuera del cerco'
        elif not self.start:
            self.lado_giro_actual = float(self.get_parameter('lado_giro_inicial').value)
            self.estado = 'Esperando inicio'
        else:
            return True

        self.parada()
        self.salir_modo_avance()
        self.publicar_estado(self.estado)
        return False

    # Loop principal
    # ============================================================
    def control_loop(self):
        self.activar_blade()
        if not self.verificacion_ok():
            return

        # 1. Escape por bumper en ejecución
        if self.estado == 'Escape bumper':
            self.control_escape_bumper()
            return
        # 2. Esperar liberación si el bumper sigue apretado
        if self.estado == 'Esperando a que el bumper se libere':
            self.parada()
            if not self.bumper_activado:
                self.bumper_bloqueado = False
                if self.giro_despues_escape is not None:
                    signo = self.giro_despues_escape
                    self.giro_despues_escape = None
                    self.iniciar_giro(signo_giro = signo, estado_despues_giro = 'Avanzando', invertir_lado = False)
                    return
                self.cambiar_estado('Avanzando')
            else:
                self.publicar_estado('Esperando a que el bumper se libere')
            return

        # 3. Nuevo bumper
        if self.bumper_activado and not self.bumper_bloqueado:
            # Frontal + derecho: retrocede y gira hacia el lado contrario.
            if self.bumpers[3] and self.bumpers[1]:
                self.lado_giro_actual = 1.0
                self.iniciar_escape_bumper(
                    direccion_escape = -1.0,
                    signo_giro_despues = self.lado_giro_actual,
                    motivo = 'Bumper frontal + derecho: retrocede y luego gira izquierda'
                )
                return
            # Frontal + izquierdo:retrocede y gira hacia el lado contrario.
            if self.bumpers[3] and self.bumpers[0]:
                self.lado_giro_actual = -1.0
                self.iniciar_escape_bumper(
                    direccion_escape = -1.0,
                    signo_giro_despues = self.lado_giro_actual,
                    motivo = 'Bumper frontal + izquierdo: retrocede y luego gira derecha'
                )
                return
            # Frontal solo:retrocede sin girar.
            if self.bumpers[3]:
                self.iniciar_escape_bumper(
                    direccion_escape = -1.0,
                    signo_giro_despues = self.lado_giro_actual,
                    motivo = 'Bumper frontal: retrocede y luego gira'
                )
                return
            # Trasero: avanza sin girar.
            if self.bumpers[2]:
                self.iniciar_escape_bumper(
                    direccion_escape = 1.0,
                    signo_giro_despues = None,
                    motivo = 'Bumper trasero: avanza para liberarse'
                )
                return
            # Laterales solos: por seguridad retrocede y gira al lado contrario.
            if self.bumpers[1]:
                self.lado_giro_actual = 1.0
                self.iniciar_escape_bumper(
                    direccion_escape = -1.0,
                    signo_giro_despues = self.lado_giro_actual,
                    motivo = 'Bumper derecho: retrocede y gira izquierda'
                )
                return
            if self.bumpers[0]:
                self.lado_giro_actual = -1.0
                self.iniciar_escape_bumper(
                    direccion_escape = -1.0,
                    signo_giro_despues = self.lado_giro_actual,
                    motivo = 'Bumper izquierdo: retrocede y gira derecha'
                )
                return

        # 4. Giro
        if self.estado == 'Girando':
            self.control_giro()
            return

        # 5. Pausa después de giro
        if self.estado == 'Pausa post giro':
            self.parada()
            transcurrido = self.tiempo_en_estado()
            if transcurrido >= self.tiempo_pausa_post_giro_s:
                self.orientacion_objetivo = self.orientacion_grados
                self.integral_orientacion = 0.0
                self.avance_activo = False
                if self.invertir_lado_despues_giro:
                    self.lado_giro_actual *= -1.0
                    self.invertir_lado_despues_giro = False
                self.cambiar_estado(self.estado_despues_giro)
            return

        # 6. Avance lateral reutilizando control_avance()
        if self.estado == 'Avance lateral':
            transcurrido = self.tiempo_en_estado()
            if transcurrido >= self.tiempo_lateral_s:
                self.parada()
                self.salir_modo_avance()
                self.iniciar_giro( signo_giro=self.lado_giro_actual,  estado_despues_giro='Avanzando', invertir_lado=True )
                return
            self.control_avance( self.velocidad_lateral, etiqueta_estado='Avance lateral')
            return

        # 7. Obstáculo frontal + derecho
        if self.obs_frente and self.obs_der:
            self.publicar_debug(
                f'Obstaculo frontal + derecho: '
                f'frente = {self.us_frente:.1f} cm, '
                f'der = {self.us_der:.1f} cm. Giro izquierda'
            )
            self.obs_frente = False
            self.obs_der = False
            # Forzamos el lado para que el segundo giro sea igual.
            self.lado_giro_actual = 1.0
            self.iniciar_giro( signo_giro=self.lado_giro_actual, estado_despues_giro='Avance lateral', invertir_lado=False )
            return

        # 8. Obstáculo frontal + izquierdo
        if self.obs_frente and self.obs_izq:
            self.publicar_debug(
                f'Obstaculo frontal + izquierdo: '
                f'frente = {self.us_frente:.1f} cm, '
                f'izq = {self.us_izq:.1f} cm. Giro derecha'
            )
            self.obs_frente = False
            self.obs_izq = False
            # Forzamos el lado para que el segundo giro sea igual.
            self.lado_giro_actual = -1.0
            self.iniciar_giro(signo_giro=self.lado_giro_actual, estado_despues_giro='Avance lateral', invertir_lado=False)
            return
        # 9. Obstáculo frontal solo
        if self.obs_frente:
            self.publicar_debug(
                f'Obstaculo frontal: frente = {self.us_frente:.1f} cm. '
                f'Giro {self.texto_giro(self.lado_giro_actual)}'
            )
            self.obs_frente = False
            self.iniciar_giro(signo_giro=self.lado_giro_actual, estado_despues_giro='Avance lateral', invertir_lado=False)
            return

        # 10. Avance normal
        self.cambiar_estado('Avanzando')
        self.control_avance( self.vel_avance,  etiqueta_estado='Avanzando'  )

    def destroy_node(self):
        try:
            self.pub_cmd_motores.publish(Float32MultiArray(data=[0.0, 0.0]))
        except Exception:
            pass
        super().destroy_node()

def main(args=None):
    rclpy.init(args=args)
    node = ParallelLinesNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando parallel_lines_node')
    finally:
        node.destroy_node()
        rclpy.shutdown()

if __name__ == '__main__':
    main()