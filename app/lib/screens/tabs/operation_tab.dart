import 'package:flutter/material.dart';
import '../../services/robot_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/manual_control.dart';

class OperationTab extends StatelessWidget {
  // ---------------------------------------------------------------------------
  // PARAMETROS Y CALLBACKS RECIBIDOS DESDE HOME SCREEN
  // ---------------------------------------------------------------------------
  final List<String> modes;
  final Map<String, Map<String, String>> modeInfo;
  final int modeIndex;
  final bool campoPotencial;
  final bool cutting;
  final bool manualControlActive;
  final bool trimmerActive;       
  final bool brushlessActive;     
  final bool imuCalibrated;
  final RobotConnection? robot;
  final void Function(int index) onModeChanged;
  final ValueChanged<bool> onCampoPotencialChanged;
  final VoidCallback onToggleMove;
  final void Function(String message, String type) onEvent;
  final ValueChanged<bool> onManualControlActiveChanged;
  final ValueChanged<bool> onTrimmerChanged;    // Callback para cambiar trimmer desde ManualControl
  final ValueChanged<bool> onBrushlessChanged;  // Callback para cambiar cuchilla desde ManualControl

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const OperationTab({
    super.key,
    required this.modes,
    required this.modeInfo,
    required this.modeIndex,
    required this.campoPotencial,
    required this.cutting,
    required this.manualControlActive,
    required this.trimmerActive,
    required this.brushlessActive,
    required this.imuCalibrated,
    required this.robot,
    required this.onModeChanged,
    required this.onCampoPotencialChanged,
    required this.onToggleMove,
    required this.onEvent,
    required this.onManualControlActiveChanged,
    required this.onTrimmerChanged,
    required this.onBrushlessChanged,
  });

  // ---------------------------------------------------------------------------
  // GETTERS DERIVADOS
  // ---------------------------------------------------------------------------
  String get _activeMode => modes[modeIndex];
  bool get _isModeManual => _activeMode == 'Manual';
  bool get _campoPotencialDisponible => _activeMode == 'Aleatorio';

  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SingleChildScrollView(
          physics: manualControlActive
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildModeCard(),
              const SizedBox(height: 12),
              if (!imuCalibrated) ...[
                _buildImuWarningCard(),
                const SizedBox(height: 12),
              ],
              _buildModeInfoCard(),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, anim) =>
                    SizeTransition(sizeFactor: anim, child: child),
                child: _isModeManual
                    ? Column(
                        key: const ValueKey('manualWidget'),
                        children: [
                          ManualControl(
                            onEvent: onEvent,
                            robot: robot,
                            trimmerActive: trimmerActive,
                            brushlessActive: brushlessActive,
                            onTrimmerChanged: onTrimmerChanged,
                            onBrushlessChanged: onBrushlessChanged,
                            onControlActiveChanged:
                                onManualControlActiveChanged,
                          ),
                          const SizedBox(height: 16),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('noManual')),
              ),
            ],
          ),
        ),
        // El boton Iniciar/Detener tambien se muestra en Manual, pero en ese modo
        // HomeScreen publica /robot/gps_track_enable, no /start de navegacion.
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(child: _buildCutButton()),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS DE SELECCION DE MODO
  // ---------------------------------------------------------------------------
  Widget _buildModeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MODO ACTIVO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0x73FFFFFF),
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _activeMode,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.8,
            children: List.generate(modes.length, (i) {
              final isSelected = modeIndex == i;
              final isLocked = cutting && !isSelected;
              return GestureDetector(
                onTap: cutting ? null : () => onModeChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.blue
                        : isLocked
                        ? const Color(0x18FFFFFF)
                        : const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0x22FFFFFF), width: 1),
                  ),
                  child: Center(
                    child: Text(
                      modes[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : isLocked
                            ? const Color(0x55FFFFFF)
                            : const Color(0x99FFFFFF),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _campoPotencialDisponible
                ? Row(
                    key: const ValueKey('campoPotencial'),
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Campo Potencial',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              'Evitación por visión + ultrasonidos',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0x99FFFFFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: campoPotencial,
                        onChanged: onCampoPotencialChanged,
                        activeThumbColor: AppColors.blue,
                        inactiveThumbColor: Colors.white54,
                        inactiveTrackColor: Colors.white24,
                      ),
                    ],
                  )
                : Padding(
                    key: const ValueKey('noCampoPotencial'),
                    padding: EdgeInsets.zero,
                    child: Text( 'Campo potencial disponible solo en modo Aleatorio.', style: const TextStyle( fontSize: 11, color: Color(0x66FFFFFF),),),
                  ),
          ),
        ],
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // WIDGETS DE ESTADO Y ACCION
  // ---------------------------------------------------------------------------
  Widget _buildModeInfoCard() {
    final info = modeInfo[_activeMode]!;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info['icon']!, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeMode,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  info['desc']!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildCutButton() {
    return GestureDetector(
      onTap: onToggleMove,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: cutting ? AppColors.red : AppColors.blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: (cutting ? AppColors.red : AppColors.blue).withOpacity(
                0.4,
              ),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            cutting ? 'Detener' : 'Iniciar',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildImuWarningCard() {
  return AppCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Icon(Icons.warning_amber_rounded, color: AppColors.amber),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'IMU sin calibrar. La orientación puede ser incorrecta.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ),
      ],
    ),
  );
}