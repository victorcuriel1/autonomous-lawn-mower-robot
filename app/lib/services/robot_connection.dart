// ══════════════════════════════════════════════════════════════════════════════
// ROBOT CONNECTION — Comunicación WebSocket con rosbridge
//
// Varias clases con distintas responsabilidades, trabajan juntas para gestionar la conexión,
// suscripciones, interpretación de mensajes y publicación de comandos hacia ROS2.
//
//   RobotConnection       -> conecta, desconecta y reconecta el WebSocket.
//   RobotSubscriptions    -> define a qué topics se suscribe la app.
//   RobotMessageParser    -> interpreta mensajes recibidos y actualiza estado.
//   RobotCommandPublisher -> publica comandos hacia ROS2.
//
// Uso:
//   final robot = RobotConnection('ws://192.168.1.100:8080', robotState);
//   robot.connect();
//   robot.sendMotorRpm(leftRpm: 20.0, rightRpm: 20.0);
//   robot.disconnect();
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:latlong2/latlong.dart';
import 'robot_state.dart';

// Función en forma de variable para pasar entre clases y permitir que RobotSubscriptions
// y RobotCommandPublisher envíen datos a través del WebSocket de RobotConnection
typedef RosSender = void Function(Map<String, dynamic> data);

class RobotConnection {
  final String url;
  final RobotState state;

  // WebSocket channel y reconexión automática
  IOWebSocketChannel?
  _channel; // _channel es la conexión WebSocket, inicialmente nula hasta que se conecta.
  bool _shouldReconnect =
      true; // La app debería intentar reconectar automáticamente si la conexión se pierde.
  Timer?
  _reconnectTimer; // Timer para programar intentos de reconexión después de desconexiones o errores.

  // Objetos para suscribirse, parsear mensajes y publicar comandos desde la clase principal: RobotConnection.
  late final RobotSubscriptions _subscriptions;
  late final RobotMessageParser _parser;
  late final RobotCommandPublisher _commands;

  // Constructor: inicializa las clases de suscripción, parseo y publicación, pasando la función de envío.
  RobotConnection(this.url, this.state) {
    _subscriptions = RobotSubscriptions(_send);
    _parser = RobotMessageParser(state);
    _commands = RobotCommandPublisher(_send);
  }

  //----------------------------------------------------------------
  // LOGICA DE CONECTIVIDAD

  void connect() {
    _shouldReconnect = true;
    // channel se conecta al websocket con la url, luego escucha los mensajes del
    // canal y los maneja con _handleMessage, y también maneja la desconexión y
    // errores con _onDisconnected y _onError.
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      _channel!.stream.listen(
        _handleMessage,
        onDone: _onDisconnected,
        onError: _onError,
      );
      // cuando el canal esté listo, actualiza el estado de conexión a true
      // y refresca las suscripciones.
      _channel!.ready
          .then((_) {
            if (!_shouldReconnect) return;
            state.updateConnection(true);
            _refreshSubscriptions();
          })
          .catchError((e) {
            print('Error al abrir WebSocket: $e');
            state.updateConnection(false);
            if (_shouldReconnect) _scheduleReconnect();
          });
    } catch (e) {
      print('Error al conectar: $e');
      _scheduleReconnect();
    }
  }

  // Cierra la conexión WebSocket, cancela cualquier intento de reconexión
  // y actualiza el estado de conexión a false
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    state.updateConnection(false);
  }

  // Si la conexión se pierde, actualiza el estado a desconectado
  // e intenta reconectar si _shouldReconnect es true
  void _onDisconnected() {
    state.updateConnection(false);
    _channel = null;
    if (_shouldReconnect) _scheduleReconnect();
  }

  // Si ocurre un error en la conexión, imprime el error, actualiza el estado a
  // desconectado,  e intenta reconectar si _shouldReconnect es true
  void _onError(Object error) {
    print('Error WebSocket: $error');
    state.updateConnection(false);
    _channel = null;
    if (_shouldReconnect) _scheduleReconnect();
  }

  // Programa un intento de reconexión después de 5 segundos si la app debería
  // reconectar
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_shouldReconnect) connect();
    });
  }

  //----------------------------------------------------------------------
  // LOGICA DE PUBLICACION DE COMANDOS HACIA ROS2
  void sendMotorRpm({required double leftRpm, required double rightRpm}) {
    _commands.sendMotorRpm(leftRpm: leftRpm, rightRpm: rightRpm);
  }

  void sendMowCommand(bool on) {
    _commands.sendMowCommand(on);
  }

  void sendTrimmerCommand(bool enable) {
    _commands.sendTrimmerCommand(enable);
  }

  void sendBladeCommand(bool enable) {
    _commands.sendBladeCommand(enable);
  }

  void sendStartMoving(bool start) {
    _commands.sendStartMoving(start);
  }

  void sendGpsTrackEnable(bool enable) {
    _commands.sendGpsTrackEnable(enable);
  }

  void sendEmergencyStop() {
    _commands.sendEmergencyStop();
  }

  void sendResetEmergencyStop() {
    _commands.sendResetEmergencyStop();
  }

  void sendImuCalibrate() {
    _commands.sendImuCalibrate();
  }

  void sendImuResetYaw() {
    _commands.sendImuResetYaw();
  }

  void sendNavigationMode(String mode) {
    _commands.sendNavigationMode(mode);
  }

  void sendDisplayText(String text) {
    _commands.sendDisplayText(text);
  }

  void sendPotentialField(bool enable) {
    _commands.sendPotentialField(enable);
  }

  void sendVisionEnable(bool enable) {
    _commands.sendVisionEnable(enable);
  }

  void sendVisionManualBladeEnable(bool enable) {
    _commands.sendVisionManualBladeEnable(enable);
  }

  void sendFencePolygon(List<Map<String, double>> points) {
    _commands.sendFencePolygon(points);
  }

  void sendCommand(String topic, Map<String, dynamic> msg) {
    _commands.sendCommand(topic, msg);
  }

  void callService(String service, Map<String, dynamic> args) {
    _commands.callService(service, args);
  }

  //----------------------------------------------------------------------
  // LOGICA DE SUSCRIPCION A TOPICS
  void _refreshSubscriptions() {
    _subscriptions.subscribeToTopics();
    _commands.requestStatusSnapshot();

    Timer(const Duration(milliseconds: 500), () {
      if (!_shouldReconnect || !state.connected) return;
      _subscriptions.subscribeToTopics();
      _commands.requestStatusSnapshot();
    });
  }

  //----------------------------------------------------------------------
  // LOGICA DE PARSEO DE MENSAJES RECIBIDOS DESDE ROS2
  void _handleMessage(dynamic raw) {
    if (!state.connected) {
      state.updateConnection(true);
    }
    // Pasamos el mensaje crudo al parser
    _parser.handle(raw);
  }

  //----------------------------------------------------------------------
  // LOGICA DE ENVIO DE MENSAJES HACIA ROS2
  void _send(Map<String, dynamic> data) {
    if (_channel == null || !state.connected) {
      print('No se puede enviar: WebSocket desconectado');
      return;
    }
    // Convertimos a JSON el mensaje y lo enviamos por el canal
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      print('Error enviando: $e');
    }
  }
}

//----------------------------------------------------------------------
// CLASES AUXILIARES PARA ORGANIZAR LA LÓGICA DE SUSCRIPCIÓN, PARSEO Y PUBLICACIÓN
class RobotSubscriptions {
  final RosSender _send;

  RobotSubscriptions(this._send);

  void subscribeToTopics() {
    _subscribe('/battery/voltage', 'std_msgs/Float32');
    _subscribe('/gps/fix', 'sensor_msgs/NavSatFix');
    _subscribe('/gps/satellites', 'std_msgs/Int32');
    _subscribe('/robot/gps_track', 'std_msgs/Float64MultiArray');
    _subscribe('/imu/angles', 'std_msgs/Float32MultiArray');
    _subscribe('/sensors/ultrasonic', 'std_msgs/Float32MultiArray');
    _subscribe('/sensors/limit_switches', 'std_msgs/Int32MultiArray');
    _subscribe('/safety/estop', 'std_msgs/Bool');
    _subscribe('/actuators/trimmer_state', 'std_msgs/Bool');
    _subscribe('/actuators/brushless_state', 'std_msgs/Bool');
    _subscribe('/fencenode/status_text', 'std_msgs/String');
    _subscribe('/random/status', 'std_msgs/String');
    _subscribe('/random/debug', 'std_msgs/String');
    _subscribe('/parallel_lines/status', 'std_msgs/String');
    _subscribe('/parallel_lines/debug', 'std_msgs/String');
    _subscribe('/perimetral/status', 'std_msgs/String');
    _subscribe('/perimetral/debug', 'std_msgs/String');
    _subscribe('/fencenode/robot_dentro', 'std_msgs/Int32');
  }

  void _subscribe(String topic, [String? type]) {
    // La estructura del mensaje de suscripción es {'op': 'subscribe', 'topic': topic,
    // 'type': type}, type es opcional, por eso el signo "?"
    final content = {'op': 'subscribe', 'topic': topic};
    if (type != null) content['type'] = type;
    _send(content);
  }
}

class RobotMessageParser {
  final RobotState state;
  RobotMessageParser(this.state);

  // Los mensajes crudos son decodificados aqui, los datos extraidos se envian
  // a la funcion que maneja cada caso segun el topic
  void handle(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final topic = data['topic'] as String?;
      final msg = data['msg'] as Map<String, dynamic>?;

      if (topic == null || msg == null) return;
      _handleTopicMessage(topic, msg);
    } catch (e) {
      print('Error parseando mensaje: $e');
    }
  }

  void _handleTopicMessage(String topic, Map<String, dynamic> msg) {
    switch (topic) {
      case '/battery/voltage':
        final voltage = _readFloatData(msg);
        state.updateBattery(
          voltage: voltage,
          level: _batteryVoltageToLevel(voltage),
        );
        break;

      case '/gps/fix':
        final lat = _readDouble(msg['latitude'], 0.0);
        final lon = _readDouble(msg['longitude'], 0.0);
        final status = _readInt(msg['status']?['status'], -1);
        state.updateGps(lat, lon, fixed: status >= 0);
        break;

      case '/gps/satellites':
        state.updateGps(
          state.gpsLat,
          state.gpsLon,
          fixed: state.gpsFixed,
          satellites: _readInt(msg['data'], 0),
        );
        break;

      case '/robot/gps_track':
        final values = _readDoubleList(msg['data']);
        if (values.length < 2 || values.length.isOdd) return;

        final points = <LatLng>[];
        for (var i = 0; i < values.length; i += 2) {
          points.add(LatLng(values[i], values[i + 1]));
        }
        state.updateRobotGpsTrack(points);
        break;

      case '/imu/angles':
        final values = _readDoubleList(msg['data']);
        if (values.length < 3) return;

        state.updateImuAngles(
          roll: values[0],
          pitch: values[1],
          yaw: values[2],
          calibrated: values.length >= 4 ? values[3] >= 0.5 : null,
        );
        break;

      case '/sensors/ultrasonic':
        final values = _readDoubleList(msg['data']);
        if (values.length < 6) return;

        // Orden ROS: [izq, frente, derecha, diagonal derecha, diagonal izquierda, trasero derecha]
        state.updateUltrasonics(
          left: values[0],
          front: values[1],
          right: values[2],
          diagonalRight: values[3],
          diagonalLeft: values[4],
          rearRight: values[5],
        );
        break;

      case '/fencenode/status_text':
        state.updateNavigationStatus(msg['data'] as String? ?? '');
        break;

      case '/random/status':
      case '/parallel_lines/status':
      case '/perimetral/status':
        state.updateNavigationRuntimeStatus(msg['data'] as String? ?? '');
        break;

      case '/random/debug':
      case '/parallel_lines/debug':
      case '/perimetral/debug':
        state.addNavigationDebugEvent(msg['data'] as String? ?? '');
        break;

      case '/fencenode/robot_dentro':
        final value = _readInt(msg['data'], -1);
        state.updateRobotInsideFence(
          value == 1
              ? true
              : value == 0
              ? false
              : null,
        );
        break;

      case '/sensors/limit_switches':
        final data = msg['data'];
        if (data is! List) return;

        final values = data.map((e) => _readInt(e, 0)).toList();
        if (values.length < 6) return;

        // Orden ROS: [left, right, back, center left, center right, down]
        state.updateBumpers(
          left: values[0] == 1,
          right: values[1] == 1,
          back: values[2] == 1,
          frontLeft: values[3] == 1,
          frontRight: values[4] == 1,
          supportPressed: values[5] == 1,
        );
        break;

      case '/safety/estop':
        state.updateEstop(msg['data'] as bool);
        break;

      case '/actuators/trimmer_state':
        state.updateTrimmer(msg['data'] as bool? ?? false);
        break;

      case '/actuators/brushless_state':
        state.updateBrushless(msg['data'] as bool? ?? false);
        break;
    }
  }

  // Funciones auxiliares para leer datos de mensajes de tipo:
  // Simple como std_msgs/Float32 -> {'data': 0.75} a double
  double _readFloatData(Map<String, dynamic> msg) {
    return _readDouble(msg['data'], 0.0);
  }

  double _batteryVoltageToLevel(double voltage) {
    const emptyVoltage = 10.2;
    const fullVoltage = 12.44;
    return ((voltage - emptyVoltage) / (fullVoltage - emptyVoltage))
        .clamp(0.0, 1.0)
        .toDouble();
  }

  List<double> _readDoubleList(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => _readDouble(e, 0.0)).toList();
  }

  // Int o String que representa un número, con fallback, a double
  double _readDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  // Int o String que representa un número, con fallback, a int
  int _readInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class RobotCommandPublisher {
  final RosSender _send;

  RobotCommandPublisher(this._send);

  void sendMotorRpm({required double leftRpm, required double rightRpm}) {
    _send({
      'op': 'publish',
      'topic': '/esp32/cmd_motores',
      'msg': {
        'data': [leftRpm, rightRpm],
      },
    });
  }

  void sendStartMoving(bool start) {
    _send({
      'op': 'publish',
      'topic': '/start',
      'msg': {'data': start},
    });
  }

  void sendGpsTrackEnable(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/robot/gps_track_enable',
      'msg': {'data': enable},
    });
  }

  void sendMowCommand(bool on) {
    sendTrimmerCommand(on);
    sendBladeCommand(on);
  }

  void sendTrimmerCommand(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/esp32/cmd_trimmer',
      'msg': {'data': enable},
    });
  }

  void sendBladeCommand(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/esp32/cmd_blade',
      'msg': {'data': enable},
    });
  }

  void sendEmergencyStop() {
    _send({'op': 'publish', 'topic': '/esp32/cmd_estop', 'msg': {}});
  }

  void sendResetEmergencyStop() {
    _send({'op': 'publish', 'topic': '/esp32/cmd_reset_estop', 'msg': {}});
  }

  void sendImuCalibrate() {
    _send({'op': 'publish', 'topic': '/esp32/cmd_imu_calibrate', 'msg': {}});
  }

  void sendImuResetYaw() {
    _send({'op': 'publish', 'topic': '/esp32/cmd_imu_reset_yaw', 'msg': {}});
  }

  void sendNavigationMode(String mode) {
    _send({
      'op': 'publish',
      'topic': '/navigation_app/mode',
      'msg': {'data': mode},
    });
  }

  void sendDisplayText(String text) {
    _send({
      'op': 'publish',
      'topic': '/esp32/cmd_display',
      'msg': {'data': text},
    });
  }

  void sendPotentialField(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/potential_field/enable',
      'msg': {'data': enable},
    });
  }

  void sendVisionEnable(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/app/vision_enable',
      'msg': {'data': enable ? 1 : 0},
    });
  }

  void sendVisionManualBladeEnable(bool enable) {
    _send({
      'op': 'publish',
      'topic': '/vision/manual_blade_enable',
      'msg': {'data': enable},
    });
  }

  void sendFencePolygon(List<Map<String, double>> points) {
    _send({
      'op': 'publish',
      'topic': '/fence/polygon',
      'msg': {
        'points': points
            .map((p) => {'x': p['lat'], 'y': p['lon'], 'z': 0.0})
            .toList(),
      },
    });
  }

  void sendCommand(String topic, Map<String, dynamic> msg) {
    _send({'op': 'publish', 'topic': topic, 'msg': msg});
  }

  void callService(String service, Map<String, dynamic> args) {
    _send({'op': 'call_service', 'service': service, 'args': args});
  }

  void requestStatusSnapshot() {
    _send({'op': 'publish', 'topic': '/esp32/cmd_status', 'msg': {}});
  }
}
