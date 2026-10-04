import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'screens/loading_screen.dart';
import 'services/robot_connection.dart';
import 'services/robot_state.dart';
import 'theme/app_theme.dart';

// Punto de entrada de la app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();

  final robotState = RobotState();
  final RobotConnection? robot = AppConfig.simulationEnabled? null : RobotConnection(AppConfig.robotWebSocketUrl, robotState);

  if (robot != null) {
    robot.connect();
  }

  runApp(MyApp(robotState: robotState, robot: robot));
}

// Widget que configura tema y pantalla inicial
// StatelessWidget porque la configuración global no cambia
class MyApp extends StatelessWidget {
  final RobotState robotState;
  final RobotConnection? robot;

  const MyApp({super.key, required this.robotState, required this.robot});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Captain Pingui',

      // Oculta el banner rojo de DEBUG en la esquina
      debugShowCheckedModeBanner: false,

      // Tema centralizado — Todos los estilos de la app se definen en AppTheme
      theme: AppTheme.theme,

      // Pantalla inicial: loading → home
      home: LoadingScreen(robotState: robotState, robot: robot),
    );
  }
}
