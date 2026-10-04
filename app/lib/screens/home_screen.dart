import 'dart:async';  
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../config/app_config.dart';
import '../services/robot_connection.dart';
import '../services/robot_state.dart';
import '../theme/app_theme.dart';
import 'tabs/config_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/operation_tab.dart';
import 'tabs/sensors_tab.dart';

// ──────────────────────────────────────────────────────────────────────────────────────────
//                                   VARIABLES GLOBALES
// ──────────────────────────────────────────────────────────────────────────────────────────
// MODOS DE NAVEGACION
// Lista con los modos que se muestran en la app
const List<String> kModos = [
  'Líneas Paralelas',
  'Aleatorio',
  'Perimetral',
  'Manual',
];

// Mapa que traduce el modo actual en la app al nombre que ROS entiende
const Map<String, String> kModoRos = {
  'Líneas Paralelas': 'parallel_lines',
  'Aleatorio': 'random',
  'Perimetral': 'perimeter',
  'Manual': 'manual',
};
// Texto corto que se muestra en el display/OLED del ESP32 al cambiar de modo.
const Map<String, String> kModoDisplay = {
  'LÃ­neas Paralelas': 'LINEAS',
  'Aleatorio': 'ALEATORIO',
  'Perimetral': 'PERIMETRAL',
  'Manual': 'MANUAL',
};

// SIMULACION
// Desde el archivo AppConfig se elige si la app corre como simulacion o conexion real
// simulationEnabled define tambien si la app usa datos simulados o datos reales.
// true  → usa estos valores fijos para probar la interfaz sin robot.
// false → usa RobotState, actualizado desde ROS mediante rosbridge.
const double kSimBattery = 0.72;                // nivel de batería simulado
const int kSimCorteMinutos = 23;                // minutos de corte simulados
const double kSimUsLeft = 0.82;                 // ultrasonido izquierdo
const double kSimUsFront = 0.4;                 // ultrasonido frontal
const double kSimUsRight = 0.61;                // ultrasonido derecho
const double kSimUsDiagonalRight = 0.72;        // ultrasonido diagonal derecho
const double kSimUsDiagonalLeft = 0.76;         // ultrasonido diagonal izquierdo
const double kSimUsRearRight = 0.95;            // ultrasonido trasero derecho
const double kSimImuInc = 2.1;                  // inclinación IMU en grados
const double kSimImuHead = 127;                 // orientación IMU en grados
const double kSimSpeedKmh = 1.8;                // velocidad simulada en ??
const double kSimGpsLat = -25.2867;             // latitud GPS simulada 
const double kSimGpsLon = -57.6470;             // longitud GPS simulada
const double kParaguayFallbackLat = -25.2637;   // latitud de respaldo si no hay lectura del gps (Py)
const double kParaguayFallbackLon = -57.5759;   // longitud de respaldo si no hay lectura del gps (Py)
const int kSimGpsSats = 8;                      // cantidad de satélites GPS simulados
const bool kSimBumperLeft = false;              // estado del bumper izquierdo simulado, lo mismo para los siguientes
const bool kSimBumperRight = false;
const bool kSimBumperBack = false;
const bool kSimBumperFrontLeft = false;
const bool kSimBumperFrontRight = false;
const bool kSimSupportSwitchPressed = true; 

// TARJETAS DE INFORMACION DE MODOS
const Map<String, Map<String, String>> kModoInfo = {
  'Líneas Paralelas': {
    'desc':
        'El robot recorre el área en líneas paralelas, '
        'como un patrón de siega. Cubre toda la superficie de forma ordenada.',
    'icon': '🟰',
  },
  'Aleatorio': {
    'desc':
        'El robot navega de forma aleatoria por el área. '
        'Hace uso de los sensores para evitar obstáculos.',
    'icon': '🔀',
  },
  'Perimetral': {
    'desc':
        'El robot recorre los bordes del área siguiendo los sesnsores. '
        'El perímetro se almacena en la memoria del robot',
    'icon': '⏹',
  },
  'Manual': {
    'desc':
        'Control directo desde el joystick. '
        'El robot responde en tiempo real a los comandos del operador.',
    'icon': '🕹️',
  },
};

// ──────────────────────────────────────────────────────────────────────────────────────────
//                                     CLASE PRINCIPAL
// ────────────────────────────────────────────────────────────────────────────────────────── 
class HomeScreen extends StatefulWidget {
  final int initialIndex;
  final RobotState? robotState;
  final RobotConnection? robot;

  //  Constructor, puede tener estado y conexion, como no
  const HomeScreen({
    super.key,
    this.initialIndex = 0,
    this.robotState,
    this.robot,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin { // with agrega una funcionalidad, en este caso es un ticker, o mas facil, 
    // como un clock, para indicarle, a alguna animacion cuando actualizarse

  // ───────────────────────────────────────────── VARIABLES DE ESTADO Y SIMULACION ─────────────────────────────────────────────
  // ESTADO GENERAL DE LA PANTALLA
  int _navIndex = 0;                                        // INDICE DE PESTAÑA
  bool _ros2Connected = true;
  bool _moving = false;
  int _modeIndex = 0;                                       // INDICE DEL MODO DE NAVEGACIÓN
  bool _campoPotencial = false;
  bool _visionEnabled = false;
  // Permiso que el usuario da desde Manual para que la cuchilla/brushless pueda encender.
  // Cuando vision esta ON, este valor actua como habilitacion para que ROS decida.
  // Cuando vision esta OFF, este valor se manda directo al ESP32 como comando manual.
  bool _manualBrushlessRequested = false;
  int _duracionCorteMin = AppConfig.defaultCutDurationMin;
  RobotState? _robotState;
  RobotConnection? _robot;

  // VALORES DE SIMULACION O ESTADO DEL ROBOT
  // Depende de AppConfig.simulationEnabled
  // Si simulationEnabled = true → valores ksim definidos arriba
  // Si simulationEnabled = false → valores que vienen del robotState

  // Batería y duración de corte
  double get _batteryLevel => AppConfig.simulationEnabled? 
      kSimBattery : (_robotState?.batteryLevel ?? 0.0);
  double get _batteryVoltage => AppConfig.simulationEnabled? 
      12.44 : (_robotState?.batteryVoltage ?? 0.0);
  int get _corteMinutos => AppConfig.simulationEnabled? 
      kSimCorteMinutos : (_robotState?.mowingMinutes ?? 0);
  // Actuadores manuales: se leen desde RobotState para que no se reinicien al cambiar de pestaña.
  bool get _trimmerActive => AppConfig.simulationEnabled? 
      false : (_robotState?.trimmerActive ?? false);
  bool get _brushlessActive => AppConfig.simulationEnabled? 
      false : (_robotState?.brushlessActive ?? false);
  // En vision ON el boton manual representa permiso, no necesariamente estado fisico.
  // Ej: puede estar permitido, pero ROS apagarlo si no detecta pasto.
  bool get _brushlessManualButtonActive =>
      _visionEnabled ? _manualBrushlessRequested : _brushlessActive;
  // Ultrasonidos — ROS ya manda distancias en cm. En simulación multiplicamos metros simulados por 100.
  double get _usLeftCm => AppConfig.simulationEnabled? 
      kSimUsLeft * 100 : (_robotState?.usLeft ?? 0.0);
  double get _usFrontCm => AppConfig.simulationEnabled? 
      kSimUsFront * 100 : (_robotState?.usFront ?? 0.0);
  double get _usRightCm => AppConfig.simulationEnabled?
      kSimUsRight * 100 : (_robotState?.usRight ?? 0.0);
  double get _usDiagonalRightCm => AppConfig.simulationEnabled?
      kSimUsDiagonalRight * 100 : (_robotState?.usDiagonalRight ?? 0.0);
  double get _usDiagonalLeftCm => AppConfig.simulationEnabled?
      kSimUsDiagonalLeft * 100 : (_robotState?.usDiagonalLeft ?? 0.0);
  double get _usRearRightCm => AppConfig.simulationEnabled?
      kSimUsRearRight * 100 : (_robotState?.usRearRight ?? 0.0);
  // IMU — inclinación, orientación y estado de calibración
  double get _imuInc => AppConfig.simulationEnabled?
      kSimImuInc : (_robotState?.imuInclination ?? 0.0);
  double get _imuHead => AppConfig.simulationEnabled?
      kSimImuHead : (_robotState?.imuHeading ?? 0.0);
  double get _imuRoll => AppConfig.simulationEnabled?
      kSimImuInc : (_robotState?.imuRoll ?? 0.0);
  double get _imuPitch => AppConfig.simulationEnabled?
      0.0 : (_robotState?.imuPitch ?? 0.0);
  double get _imuYaw => AppConfig.simulationEnabled?
      kSimImuHead : (_robotState?.imuYaw ?? 0.0);
  bool get _imuCalibrated => AppConfig.simulationEnabled?
      true : (_robotState?.imuCalibrated ?? false);
  // GPS — latitud, longitud, cantidad de satélites, si hay fix y manejo de posicion en el mapa 
  double get _gpsLat => AppConfig.simulationEnabled?
      kSimGpsLat : (_robotState?.gpsLat ?? 0.0);
  double get _gpsLon => AppConfig.simulationEnabled? 
      kSimGpsLon : (_robotState?.gpsLon ?? 0.0);
  int get _gpsSats => AppConfig.simulationEnabled? 
      kSimGpsSats : (_robotState?.gpsSatellites ?? 0);
  List<LatLng> get _robotGpsTrackPoints => AppConfig.simulationEnabled
      ? const <LatLng>[]
      : (_robotState?.robotGpsTrackPoints ?? const <LatLng>[]);
  bool get _hasValidGps => _gpsLat.abs() > 0.000001 || _gpsLon.abs() > 0.000001;
  LatLng? _lastValidRobotPosition;  // Guarda la última posición GPS para usar de respaldo si se pierde la señal
  LatLng get _robotMapPosition {
    if (_hasValidGps) {
      final position = LatLng(_gpsLat, _gpsLon);
      _lastValidRobotPosition = position;
      return position;
    }
    return _lastValidRobotPosition ?? const LatLng(kParaguayFallbackLat, kParaguayFallbackLon);
  }
  bool get _usingLastKnownGps => !AppConfig.simulationEnabled && !_hasValidGps && _lastValidRobotPosition != null;
  bool get _usingParaguayFallback => !AppConfig.simulationEnabled && !_hasValidGps && _lastValidRobotPosition == null;
  String get _mapGpsLabel {
    if (_hasValidGps) return 'Posicion actual del robot';
    if (_usingLastKnownGps) return 'Última posición válida del robot';
    if (_usingParaguayFallback) return 'Usando respaldo: Paraguay';
    return 'OpenStreetMap';
  }
  // Bumpers y switch de levantamiento
  bool get _bumperLeft => AppConfig.simulationEnabled?
      kSimBumperLeft : (_robotState?.bumperLeft ?? false);
  bool get _bumperRight => AppConfig.simulationEnabled? 
      kSimBumperRight : (_robotState?.bumperRight ?? false);
  bool get _bumperBack => AppConfig.simulationEnabled?
      kSimBumperBack : (_robotState?.bumperBack ?? false);
  bool get _bumperFrontLeft => AppConfig.simulationEnabled?
      kSimBumperFrontLeft : (_robotState?.bumperFrontLeft ?? false);
  bool get _bumperFrontRight => AppConfig.simulationEnabled? 
      kSimBumperFrontRight : (_robotState?.bumperFrontRight ?? false);
  bool get _supportSwitchPressed => AppConfig.simulationEnabled?
      kSimSupportSwitchPressed : (_robotState?.supportSwitchPressed ?? true);
  bool get _liftDetected => !_supportSwitchPressed;
  // Estado de navegación, cerco virtual y waypoints de líneas paralelas
  String get _navigationStatusText {
    if (AppConfig.simulationEnabled) return 'Simulación activa';
    final status = _robotState?.navigationStatusText.trim() ?? '';
    return status.isEmpty? 'Sin estado ROS' : status;
  }
  String get _navigationFenceInfo {
    final count = _fenceSent?
        _fencePoints.length : 0;
    return count > 0 ? 'Sí / $count puntos' : 'No / 0 puntos';
  }
  // URL a partir de los campos editables en Config
  String get _robotUrl => 'ws://${_ipController.text}:${_portController.text}';
  // Lista de eventos del sistema. El primero es "Sistema iniciado" y luego se van a agregando mas
  final List<Map<String, String>> _events = [
    {
      'time': DateTime.now().toString(),
      'msg': 'Sistema iniciado',
      'type': 'ok',
    },
  ];

  // VARIALES DEL CERCO VIRTUAL
  final List<LatLng> _fencePoints = [];               // Puntos del cerco guardados y enviados al robot
  final List<LatLng> _draftFencePoints = [];          // Puntos del cerco dibujados pero aún no se guardan
  List<Map<String, double>> _lastFencePolygon = [];   // Último cerco enviado al robot 
  bool _definingFence = false;
  bool _fenceSaved = false;
  bool _fenceSent = false;
  bool _manualControlActive = false;

  // CONTROLADORES Y ANIMACIONES
  // Variables para deslizar entre moodos y controles en el mapa
  late final PageController _pageController;
  late final MapController _mapController;
  // Animación de parpadeo para el ícono de Mapa cuando campo potencial activo
  late final AnimationController _mapBlinkController;   // Controla ciclo de animacion 
  late final Animation<double> _mapBlinkAnimation;      // Controla intensidad de parpadeo (valor de opacidad)

  // VARIABLES DE CONFIGURACION Y DEBUG 
  // Controladores de texto, guardan lo que el usuario escribio. Se inicializan con los valores actuales y solo se aplican al confirmar
  // Modo debug, AppConfig.simulationEnabled de forma visual en forma de toggle
  // Estimacion de tiempo restante de corte
  // Bandera para detectar cambio en IP o puerto
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  bool _debugMode = AppConfig.simulationEnabled;
  int get _estimatedRuntimeMin => (_batteryLevel * AppConfig.estimatedFullBatteryRuntimeMin).round(); // !!!!! Probable cambio de formula
  bool get _connectionConfigChanged => _ipController.text.trim() != AppConfig.robotIp || _portController.text.trim() != AppConfig.rosPort;

  // ───────────────────────────────────────────── CICLO DE VIDA (INITIALIZE Y DISPOSE) ─────────────────────────────────────────────
  @override
  // Inicializamos pestaña, creamos controladores, asignamos el modo debug y la conexion
  // Si no es sim y tenemos estado del robot, hacemos un attach al estado del robot, basicamente escuchamos siempre
  // este objeto, y siempre que haya un cambio en el estado del robot, se actualice la interfaz. (Mas adelante se ve la funcion)
  // Otro caso es si no es una sim, no hay conexion, 
  void initState() {
    super.initState();
    _navIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _mapController = MapController();
    _debugMode = AppConfig.simulationEnabled;
    _ros2Connected = AppConfig.simulationEnabled; // Si esta en simulacion, la conexion es true, si no es sim, es false y se conecta luego

    if (!AppConfig.simulationEnabled && widget.robotState != null) {
      _attachRobotState(widget.robotState!);
      _robot = widget.robot;
      _ros2Connected = widget.robotState!.connected;
    }

    // Inicializamos los controladores definidos antes con valores los valores de app config
    _ipController = TextEditingController(text: AppConfig.robotIp);
    _portController = TextEditingController(text: AppConfig.rosPort);

    // Animación de parpadeo para el ícono Mapa (cuando campo potencial esta activo)
    // Le asigna al controlador un clock o animacion que dura 800 ms
    _mapBlinkController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800),);
    // Le asigna a la animacion una variacion entre 2 valores de opacidad con una curva suave de cambio y el controlador 
    _mapBlinkAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(CurvedAnimation(parent: _mapBlinkController, curve: Curves.easeInOut),); 

    // Es el catch para intentar reconectar, en el caso que: No sea simulacion, no hayamos entrado a config a cambiar
    // ip o puerto, o no se haya conectado aun
    if (!AppConfig.simulationEnabled && _ros2Connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncRobotContextAfterConnect();
      });
    }

    if (!AppConfig.simulationEnabled && widget.initialIndex != 4 && !_ros2Connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) { // Espera a que se renderice la interfaz
        if (mounted) _tryConnectToRobot(); // Una vez renderizada, intenta reconectar
      });
    }
  }

  @override
  // Al cerrar la app, hacemos detach al estado del robot para dejar de escuchar cambios, limpiamos controladores, 
  // desconectamos el robot, limpiamos ip y puerto, y luego cerramos normalmente 
  void dispose() {
    _detachRobotState();
    _pageController.dispose();
    _mapBlinkController.dispose();
    _robot?.disconnect();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }
// ─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                     UX Y OPERACION                                    
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Funcion para cambiar de pestaña, recibe el indice y renderiza la app con ese inidice.
  // Ademas, anima la transicion entre paginas con una duracion de 280 ms y una curva suave de cambio
  void _goToPage(int index) {
    setState(() => _navIndex = index);
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 280), curve: Curves.easeInOut,);
  }
  // Si el robot esta conectado, envia el modo de navegacion actual a ROS
  void _sendCurrentNavigationMode() {
    _robot?.sendNavigationMode(kModoRos[kModos[_modeIndex]]!);
  }
  // Envia al OLED del ESP32 un texto corto con el modo elegido.
  void _sendCurrentDisplayMode() {
    _robot?.sendDisplayText(kModoDisplay[kModos[_modeIndex]]!);
  }
  // Recuerda el contexto en el que se encontraba el robot antes de desconectarse
  void _syncRobotContextAfterConnect(){
    _sendCurrentNavigationMode();
    _sendCurrentDisplayMode();
    _robot?.sendVisionEnable(_visionEnabled);
    _robot?.sendVisionManualBladeEnable(_manualBrushlessRequested);
    if (_fenceSent && _lastFencePolygon.isNotEmpty){
      _robot?.sendFencePolygon(_lastFencePolygon);
      _addEvent('Cerco reenviado al reconectarse', 'info');
    }
  }
  // Recibe el modo de navegación, renderiza segun este indice.  Caso especial: Si es perimetral o manual, se apaga el campo potencial. En cuanto a animacion, detiene el parpadeo
  void _setMode(int index) {
    final previousMode = kModos[_modeIndex];
    final nextMode = kModos[index];
    var sendPotentialOff = false;
    setState(() {
      _modeIndex = index;
      // Perimetral y Manual no tienen campo potencial -> se apaga automáticamente el parpadeo del icono de mapa
      if (nextMode != 'Aleatorio') {
        if (_campoPotencial) {
          _campoPotencial = false;
          sendPotentialOff = true;
          _mapBlinkController.stop();
          _mapBlinkController.reset();
        }
      }
    });// Agregamos evento del cambio de modo, enviamos ese modo a ROS y en caso de que no requiere campo p. mandamos false para apagarlo
    _addEvent(
      'Modo: ${kModos[index]}',
      'info'
    );
    _sendCurrentNavigationMode();
    _sendCurrentDisplayMode();
    // Seguridad: si salimos de Manual, apagamos actuadores manuales y el registro GPS manual.
    if (previousMode == 'Manual' && nextMode != 'Manual') {
      if (_moving) {
        setState(() => _moving = false);
        _robot?.sendGpsTrackEnable(false);
      }
      _setTrimmerActive(false);
      _setBrushlessActive(false);
    }
    if (sendPotentialOff) {
      _robot?.sendPotentialField(false);
    }
  }
  // Activa/desactiva campo potencial y controla el parpadeo del ícono Mapa
  void _setCampoPotencial(bool value) {
    setState(() => _campoPotencial = value);
    _addEvent(
      'Campo potencial ${value? "activado" : "desactivado"}',
      'info',
    );
    // Si el c.p. esta activo, repite la animacion (parpadea), si no, detiene el controlador y lo resetea para que este en su estado inicial
    if (value) {
      _mapBlinkController.repeat(reverse: true);
    } else {
      _mapBlinkController.stop();
      _mapBlinkController.reset();
    }
    // Avisa a ROS del estado del campo potencial
    _robot?.sendPotentialField(value);
  }
  // Logica al presionar Iniciar/Detener.
  // En modos autonomos publica /start. En Manual solo habilita el registro GPS,
  // para no despertar nodos de navegacion ni actuadores autonomos.
  void _toggleMove() {
    final selectedMode = kModos[_modeIndex];

    if (selectedMode == 'Manual') {
      final willStart = !_moving;
      if (willStart) {
        _robotState?.updateRobotGpsTrack(const <LatLng>[]);
      }
      setState(() => _moving = !_moving);
      _robot?.sendGpsTrackEnable(_moving);
      _addEvent(
        _moving ? 'Registro de recorrido manual activado' : 'Registro de recorrido manual detenido',
        _moving ? 'info' : 'ok',
      );
      return;
    }

    final selectedRosMode = kModoRos[selectedMode];
    final needsFence = selectedRosMode == 'parallel_lines' || selectedRosMode == 'random';
    if (!_moving && needsFence && !_fenceSaved) {
      _goToPage(1);
      _showErrorSnack('Defini un cerco virtual antes de iniciar.');
      _addEvent(
        'Defini un cerco virtual antes de iniciar $selectedMode',
        'err',
      );
      return;
    }

    final willStart = !_moving;
    if (willStart) {
      _robotState?.updateRobotGpsTrack(const <LatLng>[]);
    }
    setState(() => _moving = !_moving);
    _addEvent(
      _moving ? 'Movimiento activado' : 'Movimiento detenido',
      _moving ? 'info' : 'ok',
    );
    _robot?.sendStartMoving(_moving);

    // Al iniciar un modo autonomo volvemos a Home para ver el debug/estado.
    if (willStart) {
      _goToPage(0);
    }
  }
  // Si el modo manual se activa, renderizamos
  void _setManualControlActive(bool active) {
    if (_manualControlActive == active) return;
    setState(() => _manualControlActive = active);
  }
  // Cambia el estado del trimmer desde un solo lugar: manda el comando a ROS/ESP32
  // y actualiza RobotState para que el boton quede igual aunque se reconstruya la pantalla.
  void _setTrimmerActive(bool active) {
    if (_trimmerActive == active) return;
    _robot?.sendTrimmerCommand(active);
    _robotState?.updateTrimmer(active);
    _addEvent(
      'Trimmer ${active ? "activado" : "detenido"}',
      active ? 'warn' : 'ok',
    );
  }
  // Control manual de la cuchilla/brushless.
  // Si vision esta ON, no mandamos directo al ESP32: solo publicamos el permiso
  // para que ROS decida segun la camara. Si vision esta OFF, el boton manda directo.
  void _setBrushlessActive(bool active) {
    if (_manualBrushlessRequested != active) {
      setState(() => _manualBrushlessRequested = active);
    }


    // ROS recibe siempre el pedido manual, aunque vision este OFF.
    // Asi blade_node no pisa el comando manual con un apagado viejo.
    _robot?.sendVisionManualBladeEnable(active);
    if (_visionEnabled) {
      _addEvent(
        active ? 'Cuchilla habilitada para vision' : 'Cuchilla bloqueada para vision',
        active ? 'warn' : 'ok',
      );
      return;
    }

    if (_brushlessActive == active) return;
    _robot?.sendBladeCommand(active);
    _robotState?.updateBrushless(active);
    _addEvent(
      active ? 'Cuchilla activada' : 'Cuchilla detenida',
      active ? 'warn' : 'ok',
    );
  }

  // Habilita/deshabilita la logica de vision en ROS.
  // Se publica una sola vez en cada cambio del switch.
  void _setVisionEnabled(bool active) {
    if (_visionEnabled == active) return;
    _robot?.sendVisionEnable(active);

    if (active) {
      // Al encender vision, ROS recibe el permiso actual del boton manual.
      _robot?.sendVisionManualBladeEnable(_manualBrushlessRequested);
    } else {
      // Al apagar vision, ROS conserva el pedido manual actual y la app manda directo.
      _robot?.sendVisionManualBladeEnable(_manualBrushlessRequested);
      _robot?.sendBladeCommand(_manualBrushlessRequested);
      _robotState?.updateBrushless(_manualBrushlessRequested);
    }

    setState(() => _visionEnabled = active);
    _addEvent(
      active ? 'Vision activada' : 'Vision desactivada',
      active ? 'warn' : 'ok',
    );
  }
  // Muestra un diálogo de confirmación antes de salir de la app
  Future<bool> _confirmExitApp() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Salir de la app?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
        content: const Text('¿Deseás cerrar Captain Pingui?', style: TextStyle(fontSize: 14, color: AppColors.text2),),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppColors.text3),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Salir',
              style: TextStyle(
                color: AppColors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //          SUSCRIPCION Y ACTUALIZACION AL ESTADO DEL ROBOT = RENDERIZADO DE PANTALLA
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Se "suscribe" al estado del robot para escuchar cambios.
  void _attachRobotState(RobotState state) {
    _detachRobotState();
    _robotState = state;
    _robotState!.addListener(_onRobotStateChanged); // Cada vez que robotState cambie, se llama a la funcion onRobotStateChanged
  }
  // Se "desuscribe" del estado del robot para dejar de escuchar cambios. 
  void _detachRobotState() {
    _robotState?.removeListener(_onRobotStateChanged);
    _robotState = null;
  }
  // Se ejecuta cada que hay un cambio en el estado, si la app no esta corriendo o estamos en sim, no hace nada
  // Si no, reconstruye la interfaz con los datos nuevos de robotState (hace los getters)
  void _onRobotStateChanged() {
    if (!mounted || AppConfig.simulationEnabled) return;
    final wasConnected = _ros2Connected;
    final isConnected = _robotState?.connected ?? false;
    setState(() {
      _ros2Connected = isConnected; 
    });
    if (!wasConnected && isConnected) {
      _syncRobotContextAfterConnect();
    } 
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                CONEXION Y CONFIG
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Intenta la reconexion, tipo Future porque es asincrona, tarda un tiempo y no bloquea la interfaz
  Future<void> _tryConnectToRobot() async {
    // Si esta en sim, marcamos como true la conexion
    if (AppConfig.simulationEnabled) {
      setState(() => _ros2Connected = true);
      return;
    }
    // Validamos IP, puerto y URL (en las variables se carga msg de error)
    final ipError = _validateIp(_ipController.text);
    final rosPortError = _validatePort(_portController.text);
    // Entonces si estan vacios, siginifica que no hay error.
    // Si hay error, agrega evento y muestra dialogo con el msg de error o un mensaje generico
    if (ipError != null || rosPortError != null) {
      _addEvent('Config de conexión inválida', 'warn');
      _showConnectionConfigError(ipError ?? rosPortError ?? 'Revisá los datos.',);
      return;
    }
    // Ya con todos las cnfiguraciones nuevas, desconectamos. Luego, creamos la nueva conexion, hacemos attach
    // _robot es global, robot es solo de esta funcion
    _robot?.disconnect();
    final state = RobotState();
    final robot = RobotConnection(_robotUrl, state);
    _attachRobotState(state);
    _robot = robot;
    robot.connect();
    // Esperamos un rato a que se conecte (20 intentos con 200 ms de delay cada uno = 4 segundos)
    for (var i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
      if (AppConfig.simulationEnabled) return;
      // Si se conecto, renderizamos , y agregamos event
      if (state.connected) {
        setState(() => _ros2Connected = true);
        _addEvent('Robot conectado en $_robotUrl', 'ok');
        return;
      }
    }
    // Verificamos si no es sim, y si no, no se pudo conectar, agregamos evento de error
    if (AppConfig.simulationEnabled) return;
    setState(() => _ros2Connected = false);
    _addEvent('No se pudo conectar al robot', 'err');
    _showConnectionRecoveryDialog();
  }
  // Funcion para mostrar un widget de Reintentrar conexion/Configurar
  void _showConnectionRecoveryDialog() {
    // En caso que no este corriendo la app o este en sim, sale
    if (!mounted) return;
    if (AppConfig.simulationEnabled) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('No se pudo conectar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
        content: const Text('¿Deseás reintentar la conexión o cambiar la configuración del robot?', style: TextStyle(fontSize: 14, color: AppColors.text2),),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goToPage(4);
            },
            child: const Text('Configurar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _tryConnectToRobot();
            },
            child: const Text(
              'Reintentar',
              style: TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
  // Muestra dialogo de error ip o puerto invalidos, con un boton para ir a configurar
  void _showConnectionConfigError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Configuración inválida', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
        content: Text(message, style: const TextStyle(fontSize: 14, color: AppColors.text2),),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _goToPage(4);
            },
            child: const Text('Corregir', style: TextStyle( color: AppColors.blue, fontWeight: FontWeight.w700,),
            ),
          ),
        ],
      ),
    );
  }
  // Cuando se presiona el boton de conexion en la barra superior para desconectarse o conectarse segun el estado actual
  Future<void> _handleConnectionTap() async {
    if (_ros2Connected) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('¿Desconectarse?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
          content: const Text('¿Estás seguro que deseás desconectarte de Captain Pingui?', style: TextStyle(fontSize: 14, color: AppColors.text2),),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle( color: AppColors.text3, fontWeight: FontWeight.w500,),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _robot?.disconnect();
                _detachRobotState();
                setState(() => _ros2Connected = false);
                _addEvent('ROS2 desconectado por el usuario', 'warn');
              },
              child: const Text('Desconectar', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ),
      );
    } else {
      if (AppConfig.simulationEnabled) {
        setState(() => _ros2Connected = true);
        _addEvent('Conexión simulada restaurada', 'ok');
        return;
      }
      _addEvent('Intentando reconectar a ROS2...', 'info');
      await _tryConnectToRobot();
    }
  }
  // Validamos IP y puerto para guardar la config
  Future<void> _applyConnectionConfig() async {
    final ipError = _validateIp(_ipController.text);
    final rosPortError = _validatePort(_portController.text);
    if (ipError != null) {
      _addEvent(ipError, 'warn');
      return;
    }
    if (rosPortError != null) {
      _addEvent('Puerto ROS2 inválido', 'warn');
      return;
    }
    AppConfig.robotIp = _ipController.text.trim();
    AppConfig.rosPort = _portController.text.trim();
    await AppConfig.save();
    _addEvent('Config guardada: ${AppConfig.robotIp}:${AppConfig.rosPort}', 'info',);
    // Luego de validar y guardar, nos aseguramos que la pantalla este montada para
    // renderizar y que no sea sim, entonces reconectamos
    if (mounted) setState(() {});
    if (!AppConfig.simulationEnabled) _tryConnectToRobot();
  }
  // Funcion para activar o desactivar el modo debug
  Future<void> _handleDebugModeChanged(bool value) async {
    // Si se activa el debug, nos desconectamos del robot y activamos el modo debug y sim
    if (value) {
      _robot?.disconnect();
      _detachRobotState();
      setState(() {
        _debugMode = true;
        _ros2Connected = true;
        AppConfig.simulationEnabled = true;
      });
      await AppConfig.save();
      _addEvent('Modo debug activado: simulando sin robot', 'warn');
      return;
    }
    // Si desactivamos el debug, pregunta si queremos conectarnos
    final confirmed = await _confirmRealConnectionMode();
    // Si no se quiere conectar, o no esta corrienda la app, salimos
    if (!confirmed || !mounted) return;
    // Desactivamos debug y sim, y reconectamos al robot real
    setState(() {
      _debugMode = false;
      _ros2Connected = false;
      AppConfig.simulationEnabled = false;
    });
    await AppConfig.save();
    _addEvent('Modo debug desactivado: conectando al robot', 'info');
    await _tryConnectToRobot();
  }
  // Dialogo de confirmacion para activar el modo real
  // Devuelve un bool que indica si el usuario confirmo (true) o cancelo (false)
  Future<bool> _confirmRealConnectionMode() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Conectarse al robot?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
        content: const Text('La aplicación dejará de simular datos e intentará conectarse al robot real.', style: TextStyle(fontSize: 14, color: AppColors.text2),),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.text3),),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Conectar', style: TextStyle( color: AppColors.blue, fontWeight: FontWeight.w700,),),
          ),
        ],
      ),
    );
    return result ?? false;
  }
  // Para cargar un perfil de IP
  void _applyConnectionProfile(RobotConnectionProfile profile) {
    setState(() {_ipController.text = profile.ip;});
    _addEvent('Perfil cargado: ${profile.label}', 'info');
  }
  // Para guardar un perfil de IP
  Future<void> _saveCurrentConnectionProfile(String label) async {
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      _addEvent('El nombre del perfil no puede estar vacío', 'warn');
      return;
    }
    // Creamos un nuevo perfil con la IP actual y el label ingresado
    final profile = RobotConnectionProfile(label: trimmedLabel, ip: _ipController.text.trim(),);
    // Reemplazamos el perfil existente
    AppConfig.connectionProfiles = [...AppConfig.connectionProfiles.where((p) => p.label != trimmedLabel), profile,];
    // Guardamos
    await AppConfig.save();
    setState(() {});
    _addEvent('Perfil guardado: $trimmedLabel', 'ok');
  }
  // Para eliminar un perfil de IP
  Future<void> _deleteConnectionProfile(String label) async {
    AppConfig.connectionProfiles = AppConfig.connectionProfiles.where((p) => p.label != label).toList();
    await AppConfig.save();
    setState(() {});
    _addEvent('Perfil eliminado: $label', 'info');
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                   CERCO VIRTUAL Y MAPA
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Centra el mapa en la posición GPS del robot y agrega un evento al log. Si no hay GPS, centra en el respaldo
  void _centerMapOnRobot() {
    _mapController.move(_robotMapPosition, 18);
    _addEvent('Mapa centrado en la posición GPS del robot', 'info');
  }
  // Se ejecuta cuando presionamos Definir cerco, limpia la lista de "dibujo" y activa un modo "definiendo"
  void _startFenceDefinition() {
    setState(() {_definingFence = true; _draftFencePoints.clear();});
    _addEvent('Marcado de cerco virtual activado', 'info');
  }
  // Se ejecuta cuando presionamos Cancelar definición de cerco, limpia la lista de "dibujo" y desactiva el modo "definiendo"
  void _cancelFenceDefinition() {
    setState(() {_definingFence = false; _draftFencePoints.clear();});
    _addEvent('Marcado de cerco virtual cancelado', 'info');
  }
  // Se ejecuta cuando presionamos Limpiar puntos de cerco, limpia la lista de "dibujo" pero no desactiva el modo "definiendo" para seguir marcando
  void _clearDraftFencePoints() {
    setState(() => _draftFencePoints.clear());
    _addEvent('Puntos del cerco limpiados', 'info');
  }
  // Se ejecuta cada vez que se toca el mapa en modo "definiendo", se agrega el punto a la lista de "dibujo" 
  void _addDraftFencePoint(LatLng latLng) {
    setState(() {_draftFencePoints.add(latLng);});
    _addEvent(
      'Punto GPS ${_draftFencePoints.length}: '
          '${latLng.latitude.toStringAsFixed(6)}, '
          '${latLng.longitude.toStringAsFixed(6)}',
      'info',
    );
  }
  // Se ejecuta cuando se presiona Guardar cerco, valida que haya al menos 3 puntos y que no se crucen las líneas
  // luego guarda los puntos del "dibujo" en la lista de puntos del cerco oficial, limpia el "dibujo", desactiva 
  // el modo "definiendo", marca que el cerco esta guardado y guarda el último polígono para mostrar
  void _saveFenceDefinition() {
    if (_draftFencePoints.length < 4) {
      _showErrorSnack('Marcá al menos 4 puntos para guardar el cerco.');
      _addEvent('Tocá el mapa para marcar al menos 4 puntos', 'warn');
      return;
    }
    if (_hasSelfIntersectingFence(_draftFencePoints)) {
      _showErrorSnack('Cerco inválido: las líneas se cruzan.');
      _addEvent('Cerco inválido: las líneas del polígono se cruzan', 'err');
      return;
    }
    setState(() {
      _fencePoints
        ..clear()
        ..addAll(_draftFencePoints);
      _draftFencePoints.clear();
      _definingFence = false;
      _fenceSaved = true;
      _fenceSent = false;
      _lastFencePolygon = _fencePoints.map(_latLngToFencePoint).toList(growable: false); // map itera sobre cada punto y transforma, en este caso, de LatLng a Map<String, double> con claves 'lat' y 'lon', luego toList lo convierte en una lista que no puede variar su tamaño (growable: false)
    });
    _addEvent('Cerco virtual definido con ${_fencePoints.length} puntos', 'ok');
  }
  // Se ejecuta cuando se presiona Enviar cerco a robot, envia el último polígono guardado al robot y marca que el cerco fue enviado
  void _sendFenceToRobot() {
    _robot?.sendFencePolygon(_lastFencePolygon);
    setState(() => _fenceSent = true);
    _addEvent(
      'Cerco GPS enviado a CaptainP (${_lastFencePolygon.length} puntos)',
      'ok',
    );
  }
  // Se ejecuta cuando se presiona Eliminar cerco, limpia todas las listas de puntos, desactiva el 
  // modo "definiendo", marca que el cerco no esta guardado ni enviado, limpia el último polígono
  void _deleteCurrentFence() {
    setState(() {
      _fencePoints.clear();
      _draftFencePoints.clear();
      _lastFencePolygon = [];
      _definingFence = false;
      _fenceSaved = false;
      _fenceSent = false;
    });
    // Tambien actualizamos el cerco a uno vacio para que no se dibuje en el mapa y
    // enviamos un cerco vacio al robot para que no entre en algun estado por error
    _robot?.sendFencePolygon(const []);
    _addEvent('Cerco actual eliminado', 'info');
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                              HELPERS GEOMETRICOS PARA CERCO VIRTUAL
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Convierte un LatLng a un Map<String, double> con claves 'lat' y 'lon' 
  Map<String, double> _latLngToFencePoint(LatLng point) {
    return {'lat': point.latitude, 'lon': point.longitude};
  }
  // Convierte un LatLng a un Offset con dx = longitude y dy = latitude para facilitar calculos geometrico
  Offset _latLngToPlanarPoint(LatLng point) {
    return Offset(point.longitude, point.latitude);
  }
  // Producto vectorial 2D, el resultado representa el area del paralelogramo que forman los vectores
  // y el signo hacia que lado se hace la mano derecha, lo que tambien se puede interpretar como 
  // la direccion de rotacion de a->b hacia c (para saber que lado esta C de AB)
  double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  }
  // Verifica que p este entre a y b, partiendo de la premisa que el prodcuto vectorial ya dio 0
  // es decir, p esta contenida en la recta de AB, ahora corroboramos que este entre los extremos
  bool _isPointOnSegment(Offset a, Offset p, Offset b) {
    const epsilon = 0.000001;
    final minX = a.dx < b.dx ? a.dx : b.dx;
    final maxX = a.dx > b.dx ? a.dx : b.dx;
    final minY = a.dy < b.dy ? a.dy : b.dy;
    final maxY = a.dy > b.dy ? a.dy : b.dy;
    return p.dx >= minX - epsilon &&
        p.dx <= maxX + epsilon &&
        p.dy >= minY - epsilon &&
        p.dy <= maxY + epsilon;
  }
  // Verifica si dos segmentos (a-b y c-d) se cruzan. Para eso calcula el producto vectorial de 
  // AB con AC y AD, y el producto de CD con CA y CB 
  bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final o1 = _cross(a, b, c);
    final o2 = _cross(a, b, d);
    final o3 = _cross(c, d, a);
    final o4 = _cross(c, d, b);
    // Si alguno de los productos  = 0, significa que los vectores son colineales. Verificamos que 
    // el punto no este sobre el segmento. Si esta, consideramos que se cruzan
    if (o1.abs() < 0.0000000001 && _isPointOnSegment(a, c, b)) return true;
    if (o2.abs() < 0.0000000001 && _isPointOnSegment(a, d, b)) return true;
    if (o3.abs() < 0.0000000001 && _isPointOnSegment(c, a, d)) return true;
    if (o4.abs() < 0.0000000001 && _isPointOnSegment(c, b, d)) return true;
    // Si tanto el segmento AB tiene a C y D en lados opuestos (o1 y o2 tienen signos opuestos)  
    // y el segmento CD tiene a A y B en lados opuestos (o3 y o4 tienen signos opuestos), 
    // entonces se cruzan
    return (o1 > 0 && o2 < 0 || o1 < 0 && o2 > 0) &&
        (o3 > 0 && o4 < 0 || o3 < 0 && o4 > 0);
  }
  // Verifica que las lineas del poligono no se crucen
  bool _hasSelfIntersectingFence(List<LatLng> points) {
    // Si tiene menos de 4 puntos, no se pueden cruzar
    if (points.length < 4) return false;
    final segmentCount = points.length;
    // El 1er for itera sobre los puntos y forma los segmentos. Usa "%" para conectar el ultimo punto
    // con el 1ero: a1 = 3, a2 = (3 + 1) % 4 = 0
    for (var i = 0; i < segmentCount; i++) {
      final a1 = _latLngToPlanarPoint(points[i]);
      final a2 = _latLngToPlanarPoint(points[(i + 1) % segmentCount]);
      // El 2do sigue la misma logica, pero empieza desde el siguiente segmento (b1 y b2) y va hasta
      // el ultimo segmento, para comparar cada par de segmentos 
      for (var j = i + 1; j < segmentCount; j++) {
        final b1 = _latLngToPlanarPoint(points[j]);
        final b2 = _latLngToPlanarPoint(points[(j + 1) % segmentCount]);
        // Guarda los puntos extremos del segmento con indice i, y compara con los puntos de los segmentos
        // con indice j
        final aStart = i;
        final aEnd = (i + 1) % segmentCount;
        final bStart = j;
        final bEnd = (j + 1) % segmentCount;
        // Si comparten un vertice, no pueden cruzarse, entonces salta al siguiente segmento (j++)
        final shareVertex =
            aStart == bStart ||
            aStart == bEnd ||
            aEnd == bStart ||
            aEnd == bEnd;
        if (shareVertex) continue;
        // Si no comparte, verifica con la funcion de interseccion
        if (_segmentsIntersect(a1, a2, b1, b2)) return true;
      }
    }
    return false;
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                            HELPERS DE VALIDACION DE CONFIGURACION
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Valida, la IP, primero elimina espacios, luego separa por puntos y verifica si hay 4 partes
  String? _validateIp(String value) {
    final parts = value.trim().split('.');
    if (parts.length != 4) return 'La IP debe tener 4 números separados por puntos. Ej: 192.168.0.10';
    // Verifica que cada parte sea un numero entre 0 y 255
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0 || number > 255) return 'Cada parte de la IP debe ser un número entre 0 y 255.';
      if (part.length > 1 && part.startsWith('0')) return 'La IP no debe usar ceros iniciales. Ej: 192.168.0.10';
    }
    return null;
  }
  // Valida el puerto, hace lo mismo que la IP pero con un solo numero y entre 1 y 65535
  String? _validatePort(String value) {
    final port = int.tryParse(value.trim());
    if (port == null) return 'El puerto debe ser un número.';
    if (port < 1 || port > 65535) return 'El puerto debe estar entre 1 y 65535.';
    return null;
  }
  // Valida que el tiempo de corte sea un numero, mayor a 0 y menor al tiempo estimado de la bateria 
  String? _validateCutDuration(String value) {
    final minutes = int.tryParse(value.trim());
    if (minutes == null) return 'La duración debe ser un número.';
    if (minutes <= 0) return 'La duración debe ser mayor a 0 minutos.';
    if (_estimatedRuntimeMin <= 0) return 'No hay batería suficiente para iniciar un corte.';
    if (minutes > _estimatedRuntimeMin) return 'La duración supera la autonomía estimada: $_estimatedRuntimeMin min.';
    return null;
  }
  // Diálogo de edición de cualquier campo de Config. Con la opcion de confirmar o cancelar.
  // Si cancela, el valor original no se modifica.
  void _showEditDialog({
    required String label,
    required String current,
    required String hint,
    required ValueChanged<String> onSave,
    String? Function(String)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final tempController = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),),
            content: TextField(
              controller: tempController,
              keyboardType: keyboardType,
              autofocus: true, // abre el teclado automáticamente
              decoration: InputDecoration(
                hintText: hint,
                errorText: errorText,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            actions: [
              // Cancelar: cierra sin guardar, el valor original permanece
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: AppColors.text3),),),
              // Guardar — valida, llama onSave con el nuevo valor y cierra
              TextButton(
                onPressed: () {
                  final newValue = tempController.text.trim();
                  final validationError = newValue.isEmpty?
                      'El campo no puede quedar vacío.' : validator?.call(newValue);
                  if (validationError != null) {
                    setDialogState(() => errorText = validationError);
                    return;
                  }
                  onSave(newValue);
                  Navigator.pop(ctx);
                },
                child: const Text('Guardar', style: TextStyle( color: AppColors.blue, fontWeight: FontWeight.w700,),),
              ),
            ],
          ),
        );
      },
    );
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                EVENTOS Y ERROR
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // Funcion para agregar eventos a la lista _events
  void _addEvent(String msg, String type) {
    final now = DateTime.now(); // Hora y dia actual
    final time =  // Formatea la hora en hora:muinuto:segundo (padLeft es para rellanar con '0' hacia la izquierda hasata cubrir dos digitos)
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() => _events.add({'time': time, 'msg': msg, 'type': type})); // Agrega el evento a la lista y reconstruye la interfaz
  }
  // Devuelve un color segun el tipo de evento (Hay 4 tipos definidos: ok, warn, err e info)
  Color _eventColor(String type) {
    switch (type) {
      case 'ok':
        return AppColors.greenOk;
      case 'warn':
        return AppColors.amber;
      case 'err':
        return AppColors.red;
      case 'info':
        return AppColors.blue;
      default:
        return AppColors.text2;
    }
  }
  // Funcion para mostrar un mensaje de error en un SnackBar (pantallita flotante en la parte inferior)
  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
// ─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|─────|
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                    BUILD GENERAL
  // ──────────────────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmExitApp()) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              // Habilita el scroll horizontal solo si no estamos en modo de control manual
              // (interferencia con el joystick)
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: _manualControlActive? 
                      const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                  onPageChanged: (i) => setState(() => _navIndex = i),
                  children: [
                    _buildPageHome(),
                    _buildPageMapa(),
                    _buildPageSensores(),
                    _buildPageOperacion(),
                    _buildPageConfig(),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Barra inferior
        bottomNavigationBar: _buildNavBar(),
      ),
    );
  }
  // ──────────────────────────────────────────────────────────────────────────────────────────
  //                                BUILD DE CADA SECCION
  // ──────────────────────────────────────────────────────────────────────────────────────────
  // BARRA SUPERIOR, CAPTAIN PINGUI, BARRA DE CONECTIVIDAD Y ESTADO DE CONECTIVIDAD
  Widget _buildTopBar() {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          const Text(
            'Captain Pingui',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          if (_moving && _navIndex != 3) ...[
            TextButton.icon(
              onPressed: _toggleMove,
              icon: const Icon(Icons.stop_rounded, size: 16),
              label: const Text('Detener'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _buildSignalBars(),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _handleConnectionTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _ros2Connected
                    ? AppColors.blueLt
                    : const Color(0xFFFFF2F2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _ros2Connected ? AppColors.greenOk : AppColors.red,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _ros2Connected ? 'Conectado' : 'Desconectado',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _ros2Connected ? AppColors.blue : AppColors.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  // WIDGET DE BARRAS DE SEÑAL 
  // Si esta conectado, todas las barras son azules, si no, las dos primeras son grises
  Widget _buildSignalBars() {
    final heights = [4.0, 7.0, 10.0, 14.0];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(
        4,
        (i) => Container(
          width: 3,
          height: heights[i],
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: _ros2Connected? 
                AppColors.blue : (i < 2 ? AppColors.gray2 : AppColors.gray2.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
  // BARRA INFERIOR, NAVEGACIÓN ENTRE PÁGINAS
  Widget _buildNavBar() {
    const labels = ['Inicio', 'Mapa', 'Sensores', 'Operación', 'Config'];
    const icons = [
      Icons.home_rounded,
      Icons.map_rounded,
      Icons.sensors_rounded,
      Icons.tune_rounded,
      Icons.settings_rounded,
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.gray2)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(labels.length, (i) {
            final active = _navIndex == i;
            final isMapIcon = i == 1;
            // El ícono de Mapa parpadea con FadeTransition cuando campo potencial activo
            Widget iconWidget = Icon(
              icons[i],
              size: 24,
              color: active ? AppColors.blue : AppColors.gray3,
            );
            if (isMapIcon && _campoPotencial) {
              iconWidget = FadeTransition(
                opacity: _mapBlinkAnimation,
                child: Icon(icons[i], size: 24, color: AppColors.blue),
              );
            }
            return Expanded(
              child: GestureDetector(
                onTap: () => _goToPage(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconWidget,
                      const SizedBox(height: 2),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: active ? AppColors.blue : AppColors.gray3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? AppColors.blue : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
  // ══════════════════════════════════════════════════════
  // PAGE: INICIO
  // Eventos + Bateria y duracion + Transmision de video
  // ══════════════════════════════════════════════════════
  Widget _buildPageHome() {
    return HomeTab(
      connected: _ros2Connected,
      debugMode: _debugMode,
      batteryLevel: _batteryLevel,
      corteMinutos: _corteMinutos,
      duracionCorteMin: _duracionCorteMin,
      events: _events,
      robotState: _robotState,
      visionEnabled: _visionEnabled,
      eventColor: _eventColor,
      onVisionChanged: _setVisionEnabled,
      onClearEvents: () => setState(() => _events.clear()),
    );
  }
  // ══════════════════════════════════════════════════════
  // PAGE: OPERACIÓN
  // Widget de modo + tarjeta informativa del modo activo +
  // joystick si Manual + botón corte
  // ══════════════════════════════════════════════════════
  Widget _buildPageOperacion() {
    return OperationTab(
      modes: kModos,
      modeInfo: kModoInfo,
      modeIndex: _modeIndex,
      campoPotencial: _campoPotencial,
      cutting: _moving,
      manualControlActive: _manualControlActive,
      trimmerActive: _trimmerActive,
      brushlessActive: _brushlessManualButtonActive,
      imuCalibrated: _imuCalibrated,
      robot: _robot,
      onModeChanged: _setMode,
      onCampoPotencialChanged: _setCampoPotencial,
      onToggleMove: _toggleMove,
      onEvent: _addEvent,
      onManualControlActiveChanged: _setManualControlActive,
      onTrimmerChanged: _setTrimmerActive,
      onBrushlessChanged: _setBrushlessActive,
    );
  }
  // ══════════════════════════════════════════════════════
  // PAGE: MAPA
  // Mapa + Cerco virtual + Información de navegación
  // ══════════════════════════════════════════════════════
  Widget _buildPageMapa() {
    final mapEnabled = AppConfig.simulationEnabled || _ros2Connected;
    return MapTab(
      mapEnabled: mapEnabled,
      campoPotencial: _campoPotencial,
      definingFence: _definingFence,
      fenceSaved: _fenceSaved,
      fenceSent: _fenceSent,
      fencePoints: _fencePoints,
      draftFencePoints: _draftFencePoints,
      robotGpsTrackPoints: _robotGpsTrackPoints,
      navigationStatusText: _navigationStatusText,
      navigationFenceInfo: _navigationFenceInfo,
      gpsLat: _gpsLat,
      gpsLon: _gpsLon,
      mapGpsLabel: _mapGpsLabel,
      robotPosition: _robotMapPosition,
      mapController: _mapController,
      onStartFenceDefinition: _startFenceDefinition,
      onCancelFenceDefinition: _cancelFenceDefinition,
      onClearDraftFencePoints: _clearDraftFencePoints,
      onSaveFenceDefinition: _saveFenceDefinition,
      onSendFenceToRobot: _sendFenceToRobot,
      onDeleteCurrentFence: _deleteCurrentFence,
      onCenterMapOnRobot: _centerMapOnRobot,
      onAddDraftFencePoint: _addDraftFencePoint,
    );
  }
  // ══════════════════════════════════════════════════════
  // PAGE: SENSORES
  // Sensores generales + IMU + GPS + Ultrasonido + Bumpers + Lift
  // ══════════════════════════════════════════════════════
  Widget _buildPageSensores() {
    return SensorsTab(
      batteryVoltage: _batteryVoltage,
      batteryLevel: _batteryLevel,
      imuInclination: _imuInc,
      imuHeading: _imuHead,
      imuRoll: _imuRoll,
      imuPitch: _imuPitch,
      imuYaw: _imuYaw,
      imuCalibrated: _imuCalibrated,
      gpsLat: _gpsLat,
      gpsLon: _gpsLon,
      gpsSatellites: _gpsSats,
      usLeftCm: _usLeftCm,
      usFrontCm: _usFrontCm,
      usRightCm: _usRightCm,
      usDiagonalRightCm: _usDiagonalRightCm,
      usDiagonalLeftCm: _usDiagonalLeftCm,
      usRearRightCm: _usRearRightCm,
      bumperLeft: _bumperLeft,
      bumperRight: _bumperRight,
      bumperBack: _bumperBack,
      bumperFrontLeft: _bumperFrontLeft,
      bumperFrontRight: _bumperFrontRight,
      liftDetected: _liftDetected,
      robot: _robot,
      onEvent: _addEvent,
    );
  }
  // ══════════════════════════════════════════════════════
  // PAGE: CONFIG
  // Campos editables — cada uno abre un diálogo al tocar.
  // ══════════════════════════════════════════════════════
  Widget _buildPageConfig() {
    return ConfigTab(
      robotIp: _ipController.text,
      rosPort: _portController.text,
      obstacleCameraUrl: AppConfig.obstacleCameraStreamUrl,
      grassCameraUrl: AppConfig.grassCameraStreamUrl,
      cutDurationMin: _duracionCorteMin,
      estimatedRuntimeMin: _estimatedRuntimeMin,
      debugMode: _debugMode,
      connectionConfigChanged: _connectionConfigChanged,
      onApplyConnectionConfig: _connectionConfigChanged? 
          _applyConnectionConfig : null,
      onDebugModeChanged: _handleDebugModeChanged,
      onEditField: _showEditDialog,
      onRobotIpChanged: (v) => setState(() => _ipController.text = v),
      onRosPortChanged: (v) => setState(() => _portController.text = v),
      onCutDurationChanged: (minutes) {
        setState(() => _duracionCorteMin = minutes);
        _addEvent('Duración de corte: $minutes min', 'info');
      },
      onInvalidCutDuration: () =>
          _addEvent('Duración de corte inválida', 'warn'),
      validateIp: _validateIp,
      validatePort: _validatePort,
      validateCutDuration: _validateCutDuration,
      connectionProfiles: AppConfig.connectionProfiles,
      onApplyConnectionProfile: _applyConnectionProfile,
      onSaveCurrentConnectionProfile: _saveCurrentConnectionProfile,
      onDeleteConnectionProfile: _deleteConnectionProfile,
    );
  }
}