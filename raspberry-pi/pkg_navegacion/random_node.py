import math
import random
import rclpy
from rclpy.node import Node
from std_msgs.msg import String, Bool, Float32MultiArray, Int32, Int32MultiArray

class RandomNode(Node):
    #Estados de la maquina de estados
    E_Esperando_modo = 'Esperando modo random'
    E_Esperando_cerco = 'Esperando cerco virtual'
    E_Esperando_inicio = 'Esperando inicio'
    E_Avanzando = 'Avanzando'
    E_Retrocediendo = 'Retrocediendo'
    E_Girando = 'Girando'

    def __init__(self):
        super().__init__('random_node')
        self.nombre_modo = 'random'

        # PARAMETROS GENERALES
        # ==========================================================
        # PARAMETROS DE CONTROL
        # Declaracion de parametros con valores por defecto
        # Velocidades
        self.declare_parameter('rpm_avance', 80)
        self.declare_parameter('rpm_retroceso', 80)
        self.declare_parameter('rpm_maximo', 120.0)
        # Cambio de signo de rpm
        self.rpm_izq_anterior = 0.0
        self.rpm_der_anterior = 0.0
        self.rpm_pendiente = None
        self.umbral_cambio_signo_rpm = 1.0
        # Giros
        self.declare_parameter('giro_izq', 1)
        self.declare_parameter('giro_der', -1)
        self.declare_parameter('giro_min_grados', 70.0)
        self.declare_parameter('giro_max_grados', 150.0)
        self.declare_parameter('giro_agudo_min_grados', 20.0)
        self.declare_parameter('giro_agudo_max_grados', 45.0)
        self.declare_parameter('giro_obtuso_min_grados', 120.0)
        self.declare_parameter('giro_obtuso_max_grados', 170.0)
        self.declare_parameter('giro_no_central_min_grados', 50.0)
        self.declare_parameter('giro_no_central_max_grados', 80.0)
        # Margenes
        self.declare_parameter('tolerancia_giro_grados', 5.0)
        self.declare_parameter('distancia_obstaculo_frontal_cm', 35.0)
        self.declare_parameter('distancia_obstaculo_lateral_cm', 35.0)
        self.declare_parameter('zona_muerta_imu_grados', 1.5)
        # Control PI para avance recto
        self.declare_parameter('kp_avance', 1.0)
        self.declare_parameter('ki_avance', 0.03)
        self.declare_parameter('max_correccion_rpm',25.0)
        self.declare_parameter('signo_correccion', 1.0)
        # Control P para giro
        self.declare_parameter('kp_giro', 0.4)
        self.declare_parameter('rpm_giro_min', 60.0)
        self.declare_parameter('rpm_giro_max', 90.0)
        # Campo potencial clasico
        self.declare_parameter('distancia_campo_cm', 50.0)
        self.declare_parameter('distancia_min_campo_cm', 10.0)
        self.declare_parameter('k_atraccion_campo', 1.0)
        self.declare_parameter('k_repulsion_campo', 0.8)
        self.declare_parameter('max_desvio_campo_grados', 45.0)
        self.declare_parameter('tendencia_de_giro_campo', 0.9)
        self.declare_parameter('angulo_us_izq_grados', 90.0)
        self.declare_parameter('angulo_us_diag_izq_grados', 45.0)
        self.declare_parameter('angulo_us_frente_grados', 0.0)
        self.declare_parameter('angulo_us_diag_der_grados', -45.0)
        self.declare_parameter('angulo_us_der_grados', -90.0)
        # Tiempos
        self.declare_parameter('frecuencia_control', 10.0)
        self.declare_parameter('tiempo_retroceso_s', 5.0)

        # Lectura de parametros
        self.rpm_avance = float(self.get_parameter('rpm_avance').value)
        self.rpm_retroceso = float(self.get_parameter('rpm_retroceso').value)
        self.max_rpm = float(self.get_parameter('rpm_maximo').value)

        self.giro_izq = int(self.get_parameter('giro_izq').value)
        self.giro_der = int(self.get_parameter('giro_der').value)
        self.giro_min_grados = float(self.get_parameter('giro_min_grados').value)
        self.giro_max_grados = float(self.get_parameter('giro_max_grados').value)
        self.giro_agudo_min_grados = float(self.get_parameter('giro_agudo_min_grados').value)
        self.giro_agudo_max_grados = float(self.get_parameter('giro_agudo_max_grados').value)
        self.giro_obtuso_min_grados = float(self.get_parameter('giro_obtuso_min_grados').value)
        self.giro_obtuso_max_grados = float(self.get_parameter('giro_obtuso_max_grados').value)
        self.giro_no_central_min_grados = float(self.get_parameter('giro_no_central_min_grados').value)
        self.giro_no_central_max_grados = float(self.get_parameter('giro_no_central_max_grados').value)

        self.distancia_obstaculo_frontal_cm = float(self.get_parameter('distancia_obstaculo_frontal_cm').value)
        self.distancia_obstaculo_lateral_cm = float(self.get_parameter('distancia_obstaculo_lateral_cm').value)
        self.tolerancia_giro_grados = float(self.get_parameter('tolerancia_giro_grados').value)
        self.zona_muerta_imu_grados = float(self.get_parameter('zona_muerta_imu_grados').value)

        self.kp_avance = float(self.get_parameter('kp_avance').value)
        self.ki_avance = float(self.get_parameter('ki_avance').value)
        self.max_correccion_rpm = float(self.get_parameter('max_correccion_rpm').value)
        self.signo_correccion = float(self.get_parameter('signo_correccion').value)

        self.kp_giro = float(self.get_parameter('kp_giro').value)
        self.rpm_giro_min = float(self.get_parameter('rpm_giro_min').value)
        self.rpm_giro_max = float(self.get_parameter('rpm_giro_max').value)

        self.distancia_campo_cm = float(self.get_parameter('distancia_campo_cm').value)
        self.distancia_min_campo_cm = float(self.get_parameter('distancia_min_campo_cm').value)
        self.k_atraccion_campo = float(self.get_parameter('k_atraccion_campo').value)
        self.k_repulsion_campo = float(self.get_parameter('k_repulsion_campo').value)
        self.max_desvio_campo_grados = float(self.get_parameter('max_desvio_campo_grados').value)
        self.tendencia_de_giro_campo = float(self.get_parameter('tendencia_de_giro_campo').value)
        self.angulo_us_izq_grados = float(self.get_parameter('angulo_us_izq_grados').value)
        self.angulo_us_diag_izq_grados = float(self.get_parameter('angulo_us_diag_izq_grados').value)
        self.angulo_us_frente_grados = float(self.get_parameter('angulo_us_frente_grados').value)
        self.angulo_us_diag_der_grados = float(self.get_parameter('angulo_us_diag_der_grados').value)
        self.angulo_us_der_grados = float(self.get_parameter('angulo_us_der_grados').value)

        self.frecuencia_control = float(self.get_parameter('frecuencia_control').value)
        self.tiempo_retroceso_s = float(self.get_parameter('tiempo_retroceso_s').value)

        # PARAMETROS RECIBIDOS
        self.modo_actual = ' '
        self.inicio = False
        self.dentro_del_cerco = None
        # Ultrasonicos
        self.us_izq = None
        self.us_diag_izq = None
        self.us_frente = None
        self.us_diag_der = None
        self.us_der = None
        # Bumper
        self.bumpers = [False, False, False, False, False]  # [izq, der, atr, fr izq, fr der]
        # Cerco
        self.cerco_valido = False
        # Imu
        self.orientacion_grados = 0.0

        # PARAMETROS DE ESTADO
        self.estado = self.E_Esperando_modo
        self.t_entrada_estado = self.get_clock().now()
        self.parada_enviada = False
        self.razon_estado = ''
        self.sentido_giro = 1.0
        self.tipo_giro = 'normal'
        self.corte_encendido = False

        self.orientacion_objetivo = 0.0
        self.orientacion_base_avance = 0.0
        self.integral_orientacion = 0.0

        self.campo_potencial_activo = False
        self.angulo_campo_grados = 0.0
        self.fuerza_campo_x = 0.0
        self.fuerza_campo_y = 0.0
        self.ultimo_angulo_debug_campo = 0.0

        self.t_ultimo_debug_campo = self.get_clock().now()
        self.t_pausa_estado_s = 1.5
        self.pausar = False
        self.t_inicio_pausa = None
        
        # PUBLICADORES
        # ==========================================================
        # create_publisher(tipo de mensaje, topico, tamaño del buffer)
        self.pub_estado = self.create_publisher(String, '/random/status', 10)
        self.pub_debug = self.create_publisher(String, '/random/debug', 10)
        self.pub_cmd_motores = self.create_publisher(Float32MultiArray, '/esp32/cmd_motores', 10)
        self.pub_corte_nav = self.create_publisher(Bool, '/navegacion/corte', 10)

        # SUSCRIPTORES
        # ==========================================================
        # create_subscription(tipo de mensaje, topico, callback, tamaño del buffer)
        self.sub_modo = self.create_subscription(String, '/navigation_app/mode', self.callback_modo, 10)
        self.sub_cerco_valido = self.create_subscription(Bool, '/fencenode/valid', self.callback_cerco_valido, 10)
        self.sub_start = self.create_subscription(Bool, '/start', self.callback_start, 10)
        self.sub_dentro_del_cerco = self.create_subscription(Int32, '/fencenode/robot_dentro', self.callback_dentro_del_cerco, 10)
        self.sub_campo_potencial = self.create_subscription(Bool, '/potential_field/enable', self.callback_campo_potencial, 10)
        self.sub_angulos_imu = self.create_subscription(Float32MultiArray, '/imu/angles', self.callback_angulos_imu, 10)
        self.sub_ultrasonico_centro = self.create_subscription(Float32MultiArray, '/sensors/ultrasonic', self.callback_ultrasonicos, 10)
        self.sub_bumper = self.create_subscription(Int32MultiArray, '/sensors/limit_switches', self.callback_bumper, 10)

        # Timer principal (loop)
        # ==========================================================
        self.control_timer = self.create_timer(1.0 / self.frecuencia_control, self.control_loop)
        self.get_logger().info('random_node iniciado')

    # CALLBACKS
    # Actualizan los valores recibidos
    # AGREGAR O SACAR DEBUG? PENSANDO EN LA APP
    def callback_modo(self, msg):
        nuevo_modo = msg.data.strip()
        if nuevo_modo != self.modo_actual:
            self.publicar_debug(f'Modo recibido: {nuevo_modo}')
        self.modo_actual = nuevo_modo

    def callback_start(self, msg):
        nuevo_inicio = bool(msg.data)
        if nuevo_inicio != self.inicio:
            self.publicar_debug('Inicio recibido' if nuevo_inicio else 'Movimiento detenido')
        self.inicio = nuevo_inicio

    def callback_cerco_valido(self, msg):
        self.cerco_valido =  bool(msg.data)
    
    def callback_dentro_del_cerco(self, msg):
        self.dentro_del_cerco = int(msg.data) == 1

    def callback_campo_potencial(self, msg):
        self.campo_potencial_activo = bool(msg.data)

    def callback_angulos_imu(self, msg):
        data = msg.data
        if len(data) < 3:
            return
        self.orientacion_grados = float(data[2])
        self.t_ultimo_imu = self.get_clock().now()
    
    def callback_ultrasonicos(self, msg):
        data = msg.data
        if len(data) < 3:
            return
        self.us_izq = float(data[0])
        self.us_frente = float(data[1])
        self.us_der = float(data[2])
        self.us_diag_der = float(data[3])
        self.us_diag_izq = float(data[4])
        
    def callback_bumper(self, msg):
        if len(msg.data) < 6:
            return
        bumpers_aux = [int(v) for v in msg.data]
        self.bumpers = bumpers_aux[:-1]
        
    # LOOP PRINCIPAL: Lee entradas, el controlador decide el siguiente estado
    # y se ejecutan las acciones correspondientes al estado actual
    # ==========================================================
    def control_loop(self):
        entradas = self.leer_entradas()
        self.activar_corte(entradas)

        if self.pausar:
            self.parada()
            ahora = self.get_clock().now()
            tiempo_pausa = (ahora - self.t_inicio_pausa).nanoseconds * 1e-9
            if tiempo_pausa >= self.t_pausa_estado_s:
                self.pausar = False
                self.t_entrada_estado = self.get_clock().now()
                self.publicar_estado()
            return
        
        nuevo_estado = self.controlador(entradas)
        # Si entra en un nuevo estado, actualizamos tiempo
        if nuevo_estado != self.estado:
            estado_anterior = self.estado
            self.estado = nuevo_estado
            self.t_entrada_estado = self.get_clock().now()
            self.entrar_estado(estado_anterior, nuevo_estado, entradas)

            if self.debe_pausar_transicion(estado_anterior, nuevo_estado, entradas):
                self.parada()
                self.pausar = True
                self.t_inicio_pausa = self.get_clock().now()
                return

        self.camino_datos()
        self.publicar_estado()

    # LECTURA DE ENTRADAS
    # ==========================================================
    def leer_entradas(self):
        # Bumpers
        bumpers = [v == 1 for v in self.bumpers]
        bumpers.append(True if bumpers[3] and bumpers[4] else False) # Frontal [5]

        # Ultrasonicos
        obs_frente = self.obstaculo_por_us(self.us_frente, self.distancia_obstaculo_frontal_cm)
        obs_izq = self.obstaculo_por_us(self.us_izq, self.distancia_obstaculo_lateral_cm)
        obs_der = self.obstaculo_por_us(self.us_der, self.distancia_obstaculo_lateral_cm)
        obs_diag_izq = self.obstaculo_por_us(self.us_diag_izq, self.distancia_obstaculo_lateral_cm)
        obs_diag_der = self.obstaculo_por_us(self.us_diag_der, 20)

        # Sentido de giro
        if bumpers[5]:
            giro = random.choice([self.giro_izq, self.giro_der])
        elif bumpers[0]:
            giro = self.giro_der
        elif bumpers[1]:
            giro = self.giro_izq
        elif bumpers[3]:
            giro = self.giro_der
        elif bumpers[4]:
            giro = self.giro_izq
        elif obs_izq or obs_diag_izq:
            giro = self.giro_der
        elif obs_der or obs_diag_der:
            giro = self.giro_izq
        elif obs_frente:
            giro = random.choice([self.giro_izq, self.giro_der])
        else:
            giro = random.choice([self.giro_izq, self.giro_der])

        entradas = {
            'random': self.modo_actual == self.nombre_modo,
            'inicio': self.inicio,
            'cerco_valido': self.cerco_valido,
            'dentro_del_cerco': self.dentro_del_cerco,
            'obs_frente': obs_frente,
            'obs_izq': obs_izq,
            'obs_der': obs_der,
            'obs_diag_der': obs_diag_der,
            'obs_diag_izq': obs_diag_izq,
            'bumpers': bumpers,
            'giro': giro
        }
        return entradas
    # UNIT CONTROL: Decide el siguiente estado en base a las entradas
    # ==========================================================
    def controlador(self, entradas):
        self.razon_estado = ''
        self.tipo_giro = 'normal'
        if not entradas['random']:
            return self.E_Esperando_modo
        if not entradas['cerco_valido']:
            return self.E_Esperando_cerco
        if not entradas['inicio']:
            return self.E_Esperando_inicio
        if self.estado in [self.E_Esperando_modo, self.E_Esperando_cerco, self.E_Esperando_inicio]:
            return self.E_Avanzando
        
        # Transiciones de estados
        # Bumpers
        if self.estado == self.E_Retrocediendo and entradas['bumpers'][2]:
            self.razon_estado = 'Bumper trasero presionado durante retroceso. Deja de retroceder y gira'
            return self.E_Girando
        
        elif entradas['bumpers'][3] or entradas['bumpers'][4] or entradas['bumpers'][5]:
            if entradas['bumpers'][5]:
                self.razon_estado = 'Bumper frontal activo, retrocede'
            elif entradas['bumpers'][3]:
                self.razon_estado = 'Bumper frontal izquierdo activo, retrocede'
            elif entradas['bumpers'][4]:
                self.razon_estado = 'Bumper frontal derecho activo, retrocede'
            return self.E_Retrocediendo
        
        elif entradas['bumpers'][0] or entradas['bumpers'][1]:
            self.tipo_giro = 'agudo'
            if entradas['bumpers'][0]:
                self.razon_estado = 'Bumper lateral izquierdo activo, giro leve'
            else:
                self.razon_estado = 'Bumper lateral derecho activo, giro leve'
            return self.E_Girando
        
        # Ultrasonicos
        if self.campo_potencial_activo:
            if self.estado == self.E_Retrocediendo:
                if self.tiempo_en_estado() >= self.tiempo_retroceso_s:
                    self.tipo_giro = 'no_central'
                    self.razon_estado = 'Retroceso con campo potencial terminado. Girando'
                    return self.E_Girando
                return self.E_Retrocediendo

            if self.estado == self.E_Girando:
                error = self.error_angular(self.orientacion_objetivo, self.orientacion_grados)
                if abs(error) <= self.tolerancia_giro_grados:
                    return self.E_Avanzando
                return self.E_Girando

            if self.obstaculo_por_us(self.us_frente, self.distancia_min_campo_cm):
                self.tipo_giro = 'no_central'
                self.razon_estado = (
                    f'Obstaculo frontal muy cercano con campo potencial activo. '
                    f'frente = {self.fmt_cm(self.us_frente)}. Retrocede'
                )
                return self.E_Retrocediendo
            return self.E_Avanzando
            
        elif entradas['obs_frente'] and entradas['obs_izq'] and entradas['obs_der']:
            self.razon_estado = (
                f'Obstaculos en frente, derecha e izquierda. '
                f'frente = {self.fmt_cm(self.us_frente)}, '
                f'izq = {self.fmt_cm(self.us_izq)}, '
                f'der = {self.fmt_cm(self.us_der)}. Retrocede'
            )
            return self.E_Retrocediendo
        
        elif entradas['obs_diag_der'] and entradas['obs_diag_izq']:
            self.tipo_giro = 'obtuso'
            self.razon_estado = (
                f'Obstaculo frontal con ambos laterales. '
                f'frente = {self.fmt_cm(self.us_frente)}, '
                f'izq = {self.fmt_cm(self.us_izq)}, '
                f'der = {self.fmt_cm(self.us_der)}. Giro obtuso'
            )
            return self.E_Girando

        elif entradas['obs_diag_der']:
            self.razon_estado = (
                f'Obstaculo frontal-derecho logico. '
                f'frente = {self.fmt_cm(self.us_frente)}, '
                f'der = {self.fmt_cm(self.us_der)}. Giro izquierda'
            )
            return self.E_Girando
        
        elif entradas['obs_diag_izq']:
            self.razon_estado = (
                f'Obstaculo frontal-izquierdo logico. '
                f'frente = {self.fmt_cm(self.us_frente)}, '
                f'izq = {self.fmt_cm(self.us_izq)}. Giro derecha'
            )
            return self.E_Girando

        elif entradas['obs_der']:
            self.tipo_giro = 'agudo'
            self.razon_estado = f'Obstaculo lateral derecho. der = {self.fmt_cm(self.us_der)}. Giro leve izquierda'
            return self.E_Girando

        elif entradas['obs_izq']:
            self.tipo_giro = 'agudo'
            self.razon_estado = f'Obstaculo lateral izquierdo. izq = {self.fmt_cm(self.us_izq)}. Giro leve derecha'
            return self.E_Girando
        
        elif entradas['obs_frente']:
            self.tipo_giro = 'no_central'
            self.razon_estado = f'Obstaculo frontal. frente = {self.fmt_cm(self.us_frente)}. Giro no central'
            return self.E_Girando
        
        # Duracion de estados
        elif self.estado == self.E_Retrocediendo:
            if self.tiempo_en_estado() >= self.tiempo_retroceso_s:
                return self.E_Girando
            return self.E_Retrocediendo
        
        elif self.estado == self.E_Girando:
            error = self.error_angular(self.orientacion_objetivo, self.orientacion_grados)
            if abs(error) <= self.tolerancia_giro_grados:
                return  self.E_Avanzando
            return self.E_Girando

        else:
            return self.E_Avanzando
            
    # ACCIONES EN CADA ESTADO
    # ==========================================================
    def entrar_estado(self, estado_anterior, estado_nuevo, entradas):
        if estado_nuevo == self.E_Girando:
            if self.tipo_giro == 'agudo':
                giro_min = self.giro_agudo_min_grados
                giro_max = self.giro_agudo_max_grados
            elif self.tipo_giro == 'obtuso':
                giro_min = self.giro_obtuso_min_grados
                giro_max = self.giro_obtuso_max_grados
            elif self.tipo_giro == 'no_central':
                giro_min = self.giro_no_central_min_grados
                giro_max = self.giro_no_central_max_grados
            else:
                giro_min = self.giro_min_grados
                giro_max = self.giro_max_grados
            angulo_giro = random.uniform(giro_min, giro_max)

            self.sentido_giro = entradas['giro']
            self.orientacion_objetivo = self.normalizar_angulo(self.orientacion_grados + angulo_giro * self.sentido_giro)

            detalle_base = f'{self.razon_estado}. ' if self.razon_estado else ''
            detalle = f': {detalle_base}Sentido = {self.texto_giro(self.sentido_giro)}'
            self.publicar_debug(f'Transicion: {estado_anterior} -> {estado_nuevo}{detalle}')
            return

        detalle = f': {self.razon_estado}' if self.razon_estado else ''
        self.publicar_debug(f'Transicion: {estado_anterior} -> {estado_nuevo}{detalle}')

        if estado_nuevo == self.E_Avanzando:
            self.orientacion_base_avance = self.orientacion_grados
            self.integral_orientacion = 0.0
            return

    def camino_datos(self):
        if self.estado == self.E_Avanzando:
            [rpm_izq, rpm_der] = self.control_avance()
            self.publicar_rpm(rpm_izq, rpm_der)

        elif self.estado == self.E_Retrocediendo:
            self.publicar_rpm(-self.rpm_retroceso, -self.rpm_retroceso)

        elif self.estado == self.E_Girando:
            [rpm_izq, rpm_der] = self.control_giro()
            self.publicar_rpm(rpm_izq, rpm_der)

        else:
            self.parada()

    # FUNCIONES AUXILIARES
    # ==========================================================
    def control_avance(self):
        dt = 1.0 / self.frecuencia_control
        rpm_base = self.rpm_avance

        self.angulo_campo_grados = self.angulo_campo_potencial()
        self.orientacion_objetivo = self.normalizar_angulo(self.orientacion_base_avance + self.angulo_campo_grados)

        error_orientacion = self.normalizar_angulo(self.orientacion_objetivo - self.orientacion_grados)
        if abs(error_orientacion) < self.zona_muerta_imu_grados:
            error_orientacion = 0.0

        self.integral_orientacion += error_orientacion * dt
        max_integral = self.max_correccion_rpm / max(self.ki_avance, 1e-6)
        self.integral_orientacion = self.limite(self.integral_orientacion, -max_integral, max_integral)

        correccion_rpm = self.correccion_imu(error_orientacion)
        rpm_izq = rpm_base - correccion_rpm
        rpm_der = rpm_base + correccion_rpm
        return [rpm_izq, rpm_der]

    def control_giro(self):
        error = self.error_angular(self.orientacion_objetivo, self.orientacion_grados)
        rpm_giro = self.kp_giro * abs(error)
        rpm_giro = self.limite(rpm_giro, self.rpm_giro_min, self.rpm_giro_max)
        direccion = 1.0 if error > 0.0 else -1.0
        if direccion > 0.0:
            return -rpm_giro, rpm_giro
        else:
            return rpm_giro, -rpm_giro
        
    def correccion_imu(self, error_orientacion):
        correccion = self.kp_avance * error_orientacion + self.ki_avance * self.integral_orientacion
        correccion *= self.signo_correccion
        return self.limite(correccion, -self.max_correccion_rpm, self.max_correccion_rpm)
    
    def error_angular(self, objetivo, actual):
        return self.normalizar_angulo(objetivo - actual)
    
    def normalizar_angulo(self, angulo):
        while angulo > 180.0:
            angulo -= 360.0
        while angulo < -180.0:
            angulo += 360.0
        return angulo
    
    def limite(self, value, minimo, maximo):
        return max(minimo, min(value, maximo))
    
    def cambio_de_signo(self, anterior, nuevo):
        return (
            abs(anterior) > self.umbral_cambio_signo_rpm and
            abs(nuevo) > self.umbral_cambio_signo_rpm and
            anterior * nuevo < 0.0
        )

    def publicar_rpm(self, rpm_izq, rpm_der):
        rpm_izq = self.limite(rpm_izq, -self.max_rpm, self.max_rpm)
        rpm_der = self.limite(rpm_der, -self.max_rpm, self.max_rpm)

        if self.rpm_pendiente is not None:
            rpm_izq, rpm_der = self.rpm_pendiente
            self.rpm_pendiente = None
        
        elif (not self.campo_potencial_activo and (self.cambio_de_signo(self.rpm_izq_anterior, rpm_izq) or self.cambio_de_signo(self.rpm_der_anterior, rpm_der))):
            self.rpm_pendiente = (rpm_izq, rpm_der)
            rpm_izq = 0.0
            rpm_der = 0.0

        es_parada = abs(rpm_izq) < 1e-3 and abs(rpm_der) < 1e-3
        if es_parada and self.parada_enviada:
            return

        self.pub_cmd_motores.publish(Float32MultiArray(data = [rpm_izq, rpm_der]))
        self.parada_enviada = es_parada
        self.rpm_izq_anterior = rpm_izq
        self.rpm_der_anterior = rpm_der

    def parada(self):
        self.publicar_rpm(0.0, 0.0)

    def activar_corte(self, entradas): 
        cortar = (entradas['random'] and entradas['inicio'] and entradas['cerco_valido'] and entradas['dentro_del_cerco'])
        if cortar != self.corte_encendido:
            self.publicar_corte(cortar)
            self.corte_encendido = cortar

            estado = 'encendido' if cortar else 'apagado'
            self.publicar_debug(f'Corte {estado}')

    def publicar_corte(self, encendido):
        msg = Bool()
        msg.data = bool(encendido)
        self.pub_corte_nav.publish(msg)      
    
    def obstaculo_por_us(self, valor, umbral_cm):
        return valor is not None and valor > 0.0 and valor <= umbral_cm

    def fuerza_repulsion(self, distancia_cm, angulo_sensor_rad):
        if distancia_cm is None or distancia_cm <= 0.0 or distancia_cm > self.distancia_campo_cm:
            return 0.0, 0.0
        
        # Convertimos de centimetros a metros
        g = distancia_cm / 100.0                        # distancia al obstaculo
        g0 = self.distancia_campo_cm / 100.0            # distancia maxima de influencia
        
        g_min = self.distancia_min_campo_cm / 100.0
        g = max(g, g_min)                               # Para que la formula no se desborde si es muy chica la distancia
        
        magnitud = (self.k_repulsion_campo * (1.0 / g - 1.0 / g0) * (1.0 / (g * g)))
        fuerza_x = -magnitud * math.cos(angulo_sensor_rad)                           # La repulsion apunta en sentido contrario.
        fuerza_y = -magnitud * math.sin(angulo_sensor_rad)
        return fuerza_x, fuerza_y
    
    def angulo_campo_potencial(self):
        if not self.campo_potencial_activo:
            self.fuerza_campo_x = 0.0
            self.fuerza_campo_y = 0.0
            return 0.0

        # No hay un punto objetivo, entonces la fuerza de atraccion es ir hacia adelante
        d = 1.0                                 # Distancia al objetivo = 1 para que vaya hacia adelante
        fuerza_x = self.k_atraccion_campo  * d
        fuerza_y = 0.0

        sensores = [
            (self.us_izq, math.radians(self.angulo_us_izq_grados)),
            (self.us_diag_izq, math.radians(self.angulo_us_diag_izq_grados)),
            (self.us_frente, math.radians(self.angulo_us_frente_grados)),
            (self.us_diag_der, math.radians(self.angulo_us_diag_der_grados)),
            (self.us_der, math.radians(self.angulo_us_der_grados)),
        ]

        for distancia_cm, angulo_sensor_rad in sensores:
            rep_x, rep_y = self.fuerza_repulsion(distancia_cm, angulo_sensor_rad)
            fuerza_x += rep_x
            fuerza_y += rep_y
        # necesario?
        if self.obstaculo_por_us(self.us_frente, self.distancia_campo_cm):
            izq = self.us_izq if self.obstaculo_por_us(self.us_izq, self.distancia_campo_cm) else self.distancia_campo_cm
            der = self.us_der if self.obstaculo_por_us(self.us_der, self.distancia_campo_cm) else self.distancia_campo_cm
            if izq > der:
                fuerza_y += self.tendencia_de_giro_campo
            elif der > izq:
                fuerza_y -= self.tendencia_de_giro_campo
            else:
                fuerza_y += self.tendencia_de_giro_campo * self.sentido_giro

        self.fuerza_campo_x = fuerza_x
        self.fuerza_campo_y = fuerza_y

        # Evita que un obstaculo frontal puro genere un atan2 raro hacia 180 grados.
        fuerza_x_para_angulo = max(fuerza_x, 0.2)
        angulo_campo = math.degrees(math.atan2(fuerza_y, fuerza_x_para_angulo))
        angulo_campo = self.limite(angulo_campo, -self.max_desvio_campo_grados, self.max_desvio_campo_grados)
        return angulo_campo

    def debe_pausar_transicion(self, estado_anterior, estado_nuevo, entradas):
        if not self.campo_potencial_activo or estado_nuevo == self.E_Retrocediendo:
            return True
        transiciones_suaves = [self.E_Avanzando, self.E_Girando,]
        if estado_anterior in transiciones_suaves and estado_nuevo in transiciones_suaves:
            return False
        # Estados de espera tambien deben parar
        if estado_nuevo in [self.E_Esperando_modo, self.E_Esperando_cerco, self.E_Esperando_inicio,]:
            return True
        return False

    def publicar_estado(self):
        msg = String()
        giro_txt = 'sin'
        if self.estado == self.E_Girando:
            giro_txt = 'derecha' if self.sentido_giro == -1 else 'izquierda'
        msg.data = (
            f'estado = {self.estado}, '
            f'modo = {self.modo_actual}, '
            f'start = {self.inicio}, '
            f'cerco = {self.cerco_valido}, '
            f'campo_activo = {self.campo_potencial_activo}, '
            f'angulo_campo = {self.angulo_campo_grados:.1f}, '
            f'dentro_cerco = {self.dentro_del_cerco}, '
            f'orientacion_objetivo = {self.orientacion_objetivo:.1f}, '
            f'orientacion_actual = {self.orientacion_grados:.1f}, '
            f'giro = {giro_txt}'
        )
        self.pub_estado.publish(msg)

    def publicar_debug(self, texto):
        msg = String()
        msg.data = texto
        self.pub_debug.publish(msg)
        self.get_logger().info(texto)

    def fmt_cm(self, valor):
        if valor is None:
            return 'S/D'
        return f'{valor:.1f} cm'

    def texto_giro(self, giro):
        if giro == self.giro_der:
            return 'derecha'
        if giro == self.giro_izq:
            return 'izquierda'
        return 'aleatorio'

    def tiempo_en_estado(self):
        ahora = self.get_clock().now()
        return (ahora - self.t_entrada_estado).nanoseconds * 1e-9
    
def main(args = None):
    rclpy.init(args = args)
    node = RandomNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        node.get_logger().info('Cerrando random_node')
    finally:
        try:
            node.publicar_rpm(0.0, 0.0)
        except Exception:
            pass
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()

if __name__ == '__main__':
    main()
