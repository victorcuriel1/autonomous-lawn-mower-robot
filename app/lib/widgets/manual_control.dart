import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/robot_connection.dart';
import '../theme/app_theme.dart';
import 'app_widgets.dart';

// Control manual del robot
// Mantiene estado propio para velocidad y joystick.
// Los actuadores NO viven aca: vienen desde HomeScreen/RobotState para no perderse al cambiar de pestaña.
class ManualControl extends StatefulWidget {
  final Function(String, String)onEvent;             // Recibe la funcion para reportar eventos
  final RobotConnection? robot;                      // Clase RobotConnection, usada para enviar comandos
  final bool trimmerActive;                          // Estado actual del trimmer guardado fuera de este widget
  final bool brushlessActive;                        // Estado actual de la cuchilla/brushless guardado fuera de este widget
  final ValueChanged<bool> onTrimmerChanged;         // Pide a HomeScreen prender/apagar el trimmer
  final ValueChanged<bool> onBrushlessChanged;       // Pide a HomeScreen prender/apagar la cuchilla/brushless
  final ValueChanged<bool>? onControlActiveChanged;  // Callback para avisar cuando el control se activa/desactiva

  const ManualControl({
    super.key,
    required this.onEvent,
    this.robot,
    required this.trimmerActive,
    required this.brushlessActive,
    required this.onTrimmerChanged,
    required this.onBrushlessChanged,
    this.onControlActiveChanged,
  });

  @override
  State<ManualControl> createState() => _ManualControlState();
}

class _ManualControlState extends State<ManualControl> {
  // Parámetros físicos del robot para convertir RPM a m/s y calcular velocidades
  //static const double _manualWheelRadiusM = 0.10;
  //static const double _manualWheelBaseM = 0.32;
  static const double _manualMinWheelRpm = 90.0;
  static const double _manualMaxWheelRpm = 150.0;

  double _speed = 0.5;
  Offset _knobOffset = Offset.zero;
  Timer? _commandTimer;
  double _lastLeftRpm = 0.0;
  double _lastRightRpm = 0.0;
  double get _maxRadius => 38.0;

  //Convierte RPM a m/s: v = ω * r, ω = 2π * RPM / 60
  /*double _rpmToMps(double rpm) {
    return rpm * (2.0 * math.pi * _manualWheelRadiusM) / 60.0;
  }*/
  // Inicia un timer que envía comandos de velocidad cada 100ms mientras el joystick esté activo
  void _startCommandTimer() {
    _commandTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => widget.robot?.sendMotorRpm(leftRpm: _lastLeftRpm, rightRpm: _lastRightRpm),
    );
  }
  // Detiene el timer de comandos
  void _stopCommandTimer() {
    _commandTimer?.cancel();
    _commandTimer = null;
  }
  // Envia la velocidad al robot si inmediato es true, o actualiza los últimos valores para el timer
  void _sendJoystickCommand({required double leftRpm, required double rightRpm, bool immediate = false,}) {
    _lastLeftRpm = leftRpm;
    _lastRightRpm = rightRpm;
    if (immediate) widget.robot?.sendMotorRpm(leftRpm: leftRpm, rightRpm: rightRpm);
  }
  // Se eejecuta cuando el usuario arrastre el joystick y recibe el drag del mismo y el RenderBox para calcular la posición relativa del joystick
  void _onPanUpdate(DragUpdateDetails d, RenderBox box) {
    // Iniciar el timer para mandar comandos y calcular el offset del joystick respecto al centro del área de control
    _startCommandTimer();
    var delta = box.globalToLocal(d.globalPosition) - box.size.center(Offset.zero,); // delta: Posicion del dedo respecto al centro = Posicion del dedo dentro del ciruclo del Joystick - Centro del joystick
    // Evita que el knob se mueva fuera del área del joystick (delta.distance es el modulo del vector)
    if (delta.distance > _maxRadius) delta = delta / delta.distance * _maxRadius;
    // Redibuja el knob en la posición del dedo
    setState(() => _knobOffset = delta);
    // Componentes normalizados del joystick
    final forward = (-delta.dy / _maxRadius).clamp(-1.0, 1.0);
    final turn = (-delta.dx / _maxRadius).clamp(-1.0, 1.0);
    // La velocidad objetivo es un porcentaje de la velocidad máxima
    final targetMaxRpm = _manualMinWheelRpm + _speed * (_manualMaxWheelRpm - _manualMinWheelRpm);
    // Diferencial: La velocidad de cada rueda se calcula sumando o restando el componente de giro al componente de avance
    // Avance: turn 0 y avance 1 => leftRatio = 1, rightRatio = 1 (avanza recto)
    // Giro: turn 1 y avance 0 => leftRatio = -1, rightRatio = 1 (gira en el lugar a la derecha)
    var leftRatio = forward - turn;
    var rightRatio = forward + turn;
    // Normaliza los ratios para que ninguno exceda 1.0, manteniendo la proporción entre avance y giro
    final maxRatio = math.max(leftRatio.abs(), rightRatio.abs());
    if (maxRatio > 1.0) {
      leftRatio /= maxRatio;
      rightRatio /= maxRatio;
    }
    // Envia la velocidad al robot
    // Convierte los ratios a velocidad en rpm (xtargetMaxRpm) con el target y luego convertimos a m/s
    _sendJoystickCommand(leftRpm: leftRatio * targetMaxRpm, rightRpm: rightRatio * targetMaxRpm);
  }
  // Se ejecuta cuando el usuario suelta o se cancela el joystick.
  // Detiene el robot y resetea el estado visual del joystick.
  void _stopManualControl() {
    widget.onControlActiveChanged?.call(false);
    setState(() => _knobOffset = Offset.zero);
    _stopCommandTimer();
    _sendJoystickCommand(leftRpm: 0.0, rightRpm: 0.0, immediate: true);
  }
  // Cuando el widget se destruye, se asegura de detener el robot y limpiar el timer
  @override
  void dispose() {
    _stopCommandTimer();
    widget.robot?.sendMotorRpm(leftRpm: 0.0, rightRpm: 0.0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final joySize = 130.0;
    final joyHeight = 180.0;
    final knobSize = 46.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Velocidad', padding: EdgeInsets.zero),
        const SizedBox(height: 8),
        AppCard(
          child: Row(
            children: [
              const Text(
                'Vel.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _speed,
                  onChanged: (v) => setState(() => _speed = v),
                  activeColor: AppColors.blue,
                  inactiveColor: AppColors.gray2,
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '${(_speed * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionLabel('Joystick', padding: EdgeInsets.zero),
        const SizedBox(height: 8),
        AppCard(
          child: SizedBox(
            height: joyHeight,
            child: Center(
              child: LayoutBuilder(
                builder: (ctx, _) {
                  return Listener(
                    onPointerDown: (_) {
                      widget.onControlActiveChanged?.call(true);
                      _startCommandTimer();
                    },
                    onPointerUp: (_) =>
                        widget.onControlActiveChanged?.call(false),
                    onPointerCancel: (_) => _stopManualControl(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: (d) =>
                          _onPanUpdate(d, ctx.findRenderObject() as RenderBox),
                      onPanEnd: (_) => _stopManualControl(),
                      onPanCancel: _stopManualControl,
                      child: Container(
                        width: joySize,
                        height: joySize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.gray,
                          border: Border.all(color: AppColors.gray2, width: 2),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Positioned(
                              top: 12,
                              child: Text(
                                '▲',
                                style: TextStyle(
                                  color: AppColors.gray3,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Positioned(
                              bottom: 12,
                              child: Text(
                                '▼',
                                style: TextStyle(
                                  color: AppColors.gray3,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Positioned(
                              left: 12,
                              child: Text(
                                '◄',
                                style: TextStyle(
                                  color: AppColors.gray3,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Positioned(
                              right: 12,
                              child: Text(
                                '►',
                                style: TextStyle(
                                  color: AppColors.gray3,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: _knobOffset,
                              child: Container(
                                width: knobSize,
                                height: knobSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.black,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SectionLabel('Actuadores', padding: EdgeInsets.zero),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _actuatorCard(
                imagePath: 'assets/images/blade.png',
                name: 'Cuchilla',
                active: widget.brushlessActive,
                onTap: () {
                  // Invertimos el estado visible y delegamos el cambio a HomeScreen.
                  // Asi el boton queda sincronizado aunque salgas y vuelvas a esta pestaña.
                  widget.onBrushlessChanged(!widget.brushlessActive);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actuatorCard(
                imagePath: 'assets/images/trimmer.png',
                name: 'Trimmer',
                active: widget.trimmerActive,
                onTap: () {
                  // Mismo criterio que la cuchilla: el estado real vive fuera de ManualControl.
                  widget.onTrimmerChanged(!widget.trimmerActive);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actuatorCard({
    required String imagePath,
    required String name,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? AppColors.blueLt : AppColors.white,
          border: Border.all(
            color: active ? AppColors.blue : AppColors.gray2,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: active ? 0.38 : 0.22,
                    child: Image.asset(
                      imagePath,
                      height: 58,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? AppColors.blue.withOpacity(0.18)
                          : Colors.white.withOpacity(0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              active ? 'Activo' : 'Detenido',
              style: TextStyle(
                fontSize: 10,
                color: active ? AppColors.blue : AppColors.text3,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}