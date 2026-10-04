// ══════════════════════════════════════════════════════════════════════════════
// Configuracion global de la app.
//
// - simulationEnabled = false: cuando se pruebe con el robot real.
// Estos valores se guardan en shared_preferences para que Config y
// LoadingScreen mantengan el mismo modo al reiniciar la app, en el que se 
// encontraba antes de cerrar la app
// ══════════════════════════════════════════════════════════════════════════════
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AppConfig {
  static bool simulationEnabled = true;
  static bool debugCameraOnBoard = true;

  static const String defaultRobotIp = '192.168.0.10';
  static const String defaultRosPort = '9090';
  static const int cameraStreamPort = 8080;
  static const String obstacleCameraTopic = '/obstacle/debug_image';
  static const String grassCameraTopic = '/grass/debug_image';
  static const int defaultCutDurationMin = 60;
  static const int estimatedFullBatteryRuntimeMin = 120;

  static String robotIp = defaultRobotIp;
  static String rosPort = defaultRosPort;

  static String get robotWebSocketUrl => 'ws://$robotIp:$rosPort';

  // Las URLs de camara no se editan a mano: se arman siempre con la IP actual.
  static String get obstacleCameraStreamUrl => _cameraStreamUrl(obstacleCameraTopic);
  static String get grassCameraStreamUrl => _cameraStreamUrl(grassCameraTopic);
  static String get cameraStreamUrl => obstacleCameraStreamUrl;

  static String _cameraStreamUrl(String topic) =>
      'http://$robotIp:$cameraStreamPort/stream?topic=$topic';

  static List<RobotConnectionProfile> connectionProfiles = [];
  // Carga la configuración de la app desde shared_preferences, si no hay valores guardados, se usan los valores por defecto
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    simulationEnabled = prefs.getBool('simulationEnabled') ?? simulationEnabled;
    debugCameraOnBoard =
        prefs.getBool('debugCameraOnBoard') ?? debugCameraOnBoard;
    robotIp = prefs.getString('robotIp') ?? robotIp;
    rosPort = prefs.getString('rosPort') ?? rosPort;
    final profilesJson = prefs.getString('connectionProfiles');
    if (profilesJson != null) {
      final decoded = jsonDecode(profilesJson) as List;
      connectionProfiles = decoded.map((item) => RobotConnectionProfile.fromJson(item)).toList();
    }
  }
  // Guarda la configuración de la app en shared_preferences para que se mantenga al reiniciar la app
  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('simulationEnabled', simulationEnabled);
    await prefs.setBool('debugCameraOnBoard', debugCameraOnBoard);
    await prefs.setString('robotIp', robotIp);
    await prefs.setString('rosPort', rosPort);
    await prefs.setString('connectionProfiles', jsonEncode(connectionProfiles.map((p) => p.toJson()).toList()),);
  }
}

class RobotConnectionProfile {
  final String label;
  final String ip;

  const RobotConnectionProfile({
    required this.label,
    required this.ip,
  });
  // Convierte cierta configuración de conexión (recibida en la clase) a un mapa JSON para guardar
  Map<String, dynamic> toJson() => {
        'label': label,
        'ip': ip,
      };
  // Trae la configuración de conexión desde un mapa JSON guardado para usarla
  factory RobotConnectionProfile.fromJson(Map<String, dynamic> json) {
    return RobotConnectionProfile(
      label: json['label'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
    );
  }
}
