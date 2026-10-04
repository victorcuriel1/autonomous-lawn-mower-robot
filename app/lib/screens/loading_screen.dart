import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import 'home_screen.dart';
import '../services/robot_connection.dart';
import '../services/robot_state.dart';

// Crea la clase como extension de otra cuyo widget puede cambiar
// Super.key es una forma de pasar la clave al constructor del widget padre, lo que ayuda a
// Flutter a identificar y gestionar correctamente los widgets en el árbol de widgets.
class LoadingScreen extends StatefulWidget {final RobotState robotState; final RobotConnection? robot;

  // Constructor de la clase LoadingScreen, que requiere un RobotState y un RobotConnection opcional
  const LoadingScreen({super.key, required this.robotState, required this.robot,});

  // override indica que este método está sobrescribiendo un método de la clase padre
  @override
  // createState es un método que devuelve un objeto (_LoadingScreenState) que maneja el
  // estado de este widget (LoadingScreen) y permite que el widget sea interactivo y pueda
  // actualizarse dinámicamente. Es una práctica común en Flutter
  State<LoadingScreen> createState() => _LoadingScreenState();
}

// La clase _LoadingScreenState la cual maneja el estado de LoadingScreen (es su extensión)
class _LoadingScreenState extends State<LoadingScreen> {
  // Variables para manejar el progreso de carga, si es una simulación y el texto de la pantalla de carga
  double _progress = 0.0;
  String _statusText = 'Preparando conexión...';
  bool _canEnterOffline = false;

  // Este metodo se llama siempre para iniciar el estado del widget, es decir, para configurar
  // lo que se necesita antes de mostrar la pantalla.
  @override
  void initState() {
    super.initState();
    // Fuerza orientación vertical para esta pantalla
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Si estamos en modo simulación, o si ya se inició la conexión, comienza el proceso de conexión
    _connectToRobot();
  }

  // Destruye loading y vuelve a permitir orientación vertical
  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  // Metodo para conectar al robot, que maneja tanto la simulación como la conexión real a ROS2
  Future<void> _connectToRobot() async {
    // Variable para permitir entrar sin conexión si la conexión falla, inicialmente se desactiva
    // y si no se logra conectar al robot, se activa para mostrar la opción al usuario.
    setState(() => _canEnterOffline = false);

    // Si estamos en modo simulación, simula una carga progresiva con diferentes mensajes
    if (AppConfig.simulationEnabled) {
      // Simulación: carga progresiva de 0 a 100% sin robot real. 
      for (var i = 0; i <= 100; i++) {
        await Future.delayed(const Duration(milliseconds: 30));
        // Pregunta si el wiget sigue vivo para evitar errores, ya que el usuario podría haber salido de la pantalla de carga antes de que termine la simulación.
        if (!mounted) return;
        // Si no se ha salido, actualiza el progreso y el texto de estado según el porcentaje de carga simulado.
        setState(() {
          _progress = i / 100;
          if (i < 30) {
            _statusText = 'Inicializando módulos...';
          } else if (i < 65) {
            _statusText = 'Simulando enlace ROS2...';
          } else if (i < 95) {
            _statusText = 'Cargando telemetría...';
          } else {
            _statusText = 'Listo';
          }
        });
      }
    } else {
      // Conexión real a ROS2
      setState(() {
        _progress = 0.15;
        _statusText = 'Conectando con rosbridge...';
        _progress = 0.30;
        _canEnterOffline = false;
      });

      // Espera a que RobotConnection marque la conexión como activa.
      var connected = false;
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        if (!mounted) return;
        // Widget es el objeto de la clase padre (LoadingScreen) al que esta clase tiene acceso, 
        // y robot es la instancia de RobotConnection que se le pasó a LoadingScreen. 
        if (widget.robotState.connected) {
          // Si se conecta
          setState(() {_progress = 0.75; _statusText = 'Validando respuesta del robot...';});
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
          setState(() {_progress = 1.0;  _statusText = 'Robot conectado';});
          connected = true;
          break;
        }

        // Si no se conecta, actualiza el progreso para dar alusion a que esta intentando conectar
        setState(() {_progress = 0.15 + (i / 40) * 0.45;});
      }

      // Si después de intentar durante un tiempo no se conecta, muestra el mensaje de error 
      // y la opción para entrar sin conexión o reintentar.
      if (!connected) {
        setState(() {  _statusText = 'No se pudo conectar al robot';  _canEnterOffline = true;});
        _showConnectionRecoveryDialog();
        return;
      }
    }

    // mounted verifica que la pantalla siga activa antes de navegar al home, es la entrada de
    // exitosa a la app
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(robotState: widget.robotState, robot: widget.robot),
        ),
      );
    }
  }

  // Método para reintentar la conexión (Cuando el usuario presiona reintentar)
  void _retryConnection() {
    // Reinicia el estado de carga y pone en false la opcion de entrar sin conexion
    setState(() {
      _progress = 0.0;
      _statusText = 'Preparando conexión...';
      _canEnterOffline = false;
    });

    // Si no estamos en simulación, desconecta y vuelve a conectar el robot
    // para intentar restablecer la conexión.
    if (!AppConfig.simulationEnabled) {
      widget.robot?.disconnect();
      widget.robot?.connect();
    }
    // Intenta el flujo de conexion de nuevo
    _connectToRobot();
  }

  // Punto de entrada en la app para configurar cuando falla la conexion
  void _openConnectionConfig() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(initialIndex: 4, robotState: widget.robotState, robot: widget.robot,),
      ),
    );
  }

  // Funcion para mostrar un dialogo de error cuando no se puede conectar
  void _showConnectionRecoveryDialog() {
    // Corroboramos que no haya salido de la app, evita errores
    if (!mounted) return;

    // Luego de que se cargue todo la pantalla, muestra un dialogo, antes vuelve a
    // corroborar que no haya salido de la app
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // showDialog es una función de Flutter que muestra un cuadro de diálogo 
      // de alerta, ya tiene parametros para configurar el contexto, la forma, 
      // si se puede cerrar tocando fuera del dialogo, y el contenido del dialogo
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),),
          title: const Text('No se pudo conectar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),),
          content: const Text('¿Deseás reintentar la conexión o cambiar la configuración del robot?', style: TextStyle(fontSize: 14),),
          actions: [
            // Dos botones, uno para configurar (que lleva a la pantalla de configuracion) y
            // otro para reintentar (que vuelve a intentar conectar al robot)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openConnectionConfig();
              },
              child: const Text('Configurar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _retryConnection();
              },
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    });
  }

  // Entra a la app en modo offline (desde el widget cuando expira el tiempo de conexion y se pone
  // entrar sin conexion)
  void _enterOffline() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomeScreen(robotState: widget.robotState, robot: widget.robot),
      ),
    );
  }
 //-------------------------------------------------------------------------------------------------------
 //                                     BUILD PRINCIPAL
 //-------------------------------------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Sin AppBar — pantalla completa
      body: Stack(
        children: [
          // Imagen de fondo que llena toda la pantalla
          Positioned.fill(
            child: Image.asset(
              'assets/images/loadingScreen.png',
              fit: BoxFit.contain, // mantiene proporción y no recorta
            ),
          ),

          // Gradiente oscuro abajo para que el texto sea legible
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 160,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
              ),
            ),
          ),

          // Barra de progreso y texto pegados al fondo
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SizedBox(
                  width: 220,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 7,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${(_progress * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
                if (_canEnterOffline) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _enterOffline,
                    child: const Text(
                      'Entrar sin conexión',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}