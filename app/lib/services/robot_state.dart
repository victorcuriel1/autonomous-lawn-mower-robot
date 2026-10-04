// ══════════════════════════════════════════════════════════════════════════════
// ROBOT STATE — Estado centralizado del robot
//
// Extiende ChangeNotifier, es decir, notifica a los widgets que lo escuchan cada
// vez que se actualiza por los datos que llegan de ROS2, para que puedan
// reconstruirse con la información más reciente.
//
// Uso en un widget:
//   final state = context.watch<RobotState>(); // se reconstruye con cada cambio
//   final state = context.read<RobotState>();  // solo lee, no se reconstruye
// Basicamente, en los widgets que muestran datos del robot, se usa
// context.watch<RobotState>() para obtener el estado actual y reconstruirse
// cuando hay cambios. En los widgets que solo necesitan enviar comandos al robot,
// se usa context.read<RobotState>() para obtener el estado sin reconstruirse.
//
// Como se llama desde robot_connection.dart:
//   robotState.updateBattery(0.85);
//   robotState.updateGps(-25.28, -57.64, fixed: true);
// ══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class RobotState extends ChangeNotifier {
  // Conexión
  bool connected = false; // true = WebSocket con rosbridge activo

  // Batería
  double batteryVoltage = 0.0; // voltaje actual de la batería
  double batteryLevel = 0.0; // Porcentaje de batería (0.0 a 1.0)
  bool batteryLow = false; // true si < 20% -> Sujeto a cambios

  // GPS
  double gpsLat = 0.0;
  double gpsLon = 0.0;
  int gpsSatellites = 0; // cantidad de satélites visibles
  bool gpsFixed = false; // true si hay fix válido
  List<LatLng> robotGpsTrackPoints =
      const []; // Recorrido GPS real publicado por ROS para dibujarlo en el mapa

  // IMU
  double imuInclination = 0.0; // grados de inclinación (volcamiento)
  double imuHeading = 0.0; // orientación estimada en grados (0-360)
  double imuRoll = 0.0; // inclinación lateral en grados
  double imuPitch = 0.0; // inclinación adelante/atrás en grados
  double imuYaw = 0.0; // orientación relativa en grados
  bool imuCalibrated = false; // true si el ESP32 cargó/guardó calibración
  double imuAccelMagnitude = 0.0; // magnitud de aceleración
  double imuGyroMagnitude = 0.0; // magnitud de velocidad angular
  bool imuMoving = false; // true = el IMU detecta movimiento

  // Ultrasonidos
  // Distancias en centímetros
  // [izq, frente, derecha, diagonal derecha, diagonal izquierda, trasero derecha]
  double usLeft = 0.0;
  double usFront = 0.0;
  double usRight = 0.0;
  double usDiagonalRight = 0.0;
  double usDiagonalLeft = 0.0;
  double usRearRight = 0.0;

  // Bumpers / finales de carrera
  // true = presionado, hay contacto
  // [left, right, back, center left, center right, down]
  bool bumperLeft = false;
  bool bumperRight = false;
  bool bumperBack = false;
  bool bumperFrontLeft = false;
  bool bumperFrontRight = false;
  // Final de carrera inferior
  // true = presionado por el suelo, si se libera, el robot fue levantado.
  bool supportSwitchPressed = true;

  // Seguridad
  bool liftDetected = false; // true = robot levantado del suelo
  bool tiltDetected = false; // true = robot volcado (IMU)
  bool estopActive = false; // true = parada de emergencia activa

  // Corte
  bool mowing = false; // true = cuchilla activa
  bool trimmerActive = false;
  bool brushlessActive = false;
  String navigationStatusText = '';
  String navigationRuntimeStatusText = '';
  List<String> navigationDebugEvents = const [];
  bool? robotInsideFence;
  int mowingMinutes = 0; // minutos de corte transcurridos

  // Métodos de actualización
  // Cada método actualiza los valores y llama notifyListeners()
  // para que los widgets que escuchan este estado se reconstruyan.

  void updateConnection(bool isConnected) {
    connected = isConnected;
    notifyListeners();
  }

  void updateBattery({required double voltage, required double level}) {
    batteryVoltage = voltage;
    batteryLevel = level.clamp(0.0, 1.0);
    batteryLow = batteryLevel < 0.27;
    notifyListeners();
  }

  void updateGps(
    double lat,
    double lon, {
    bool fixed = false,
    int? satellites,
  }) {
    gpsLat = lat;
    gpsLon = lon;
    if (satellites != null) gpsSatellites = satellites;
    gpsFixed = fixed;
    notifyListeners();
  }

  void updateRobotGpsTrack(List<LatLng> points) {
    robotGpsTrackPoints = List.unmodifiable(points);
    notifyListeners();
  }

  void updateImu(double inclination, double heading) {
    imuInclination = inclination;
    imuHeading = heading;
    tiltDetected = inclination.abs() > 30.0; // alarma si inclina > 30°
    notifyListeners();
  }

  void updateImuAngles({
    required double roll,
    required double pitch,
    required double yaw,
    bool? calibrated,
  }) {
    imuRoll = roll;
    imuPitch = pitch;
    imuYaw = yaw;
    imuInclination = roll.abs() > pitch.abs() ? roll.abs() : pitch.abs();
    imuHeading = (yaw % 360.0 + 360.0) % 360.0;
    if (calibrated != null) imuCalibrated = calibrated;
    tiltDetected = imuInclination.abs() > 30.0;
    notifyListeners();
  }

  void updateImuMotion({
    double? accelMagnitude,
    double? gyroMagnitude,
    bool? moving,
  }) {
    if (accelMagnitude != null) imuAccelMagnitude = accelMagnitude;
    if (gyroMagnitude != null) imuGyroMagnitude = gyroMagnitude;
    if (moving != null) imuMoving = moving;
    notifyListeners();
  }

  void updateUltrasonics({
    required double left,
    required double front,
    required double right,
    required double diagonalRight,
    required double diagonalLeft,
    required double rearRight,
  }) {
    usLeft = left;
    usFront = front;
    usRight = right;
    usDiagonalRight = diagonalRight;
    usDiagonalLeft = diagonalLeft;
    usRearRight = rearRight;
    notifyListeners();
  }

  void updateBumpers({
    required bool left,
    required bool right,
    required bool back,
    required bool frontLeft,
    required bool frontRight,
    required bool supportPressed,
  }) {
    bumperLeft = left;
    bumperRight = right;
    bumperBack = back;
    bumperFrontLeft = frontLeft;
    bumperFrontRight = frontRight;
    supportSwitchPressed = supportPressed;
    liftDetected = !supportSwitchPressed;
    notifyListeners();
  }

  void updateLift(bool lifted) {
    liftDetected = lifted;
    notifyListeners();
  }

  void updateEstop(bool active) {
    estopActive = active;
    notifyListeners();
  }

  void updateMowing(bool active, {int minutes = 0}) {
    mowing = active;
    mowingMinutes = minutes;
    notifyListeners();
  }

  void updateNavigationStatus(String status) {
    navigationStatusText = status;
    notifyListeners();
  }

  void updateNavigationRuntimeStatus(String status) {
    navigationRuntimeStatusText = status;
    notifyListeners();
  }

  void addNavigationDebugEvent(String event) {
    final text = event.trim();
    if (text.isEmpty) return;

    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    navigationDebugEvents = List.unmodifiable(
      ['[$time] $text', ...navigationDebugEvents].take(20),
    );
    notifyListeners();
  }

  void updateRobotInsideFence(bool? inside) {
    robotInsideFence = inside;
    notifyListeners();
  }

  void updateTrimmer(bool active) {
    trimmerActive = active;
    mowing = trimmerActive || brushlessActive;
    notifyListeners();
  }

  void updateBrushless(bool active) {
    brushlessActive = active;
    mowing = trimmerActive || brushlessActive;
    notifyListeners();
  }
}