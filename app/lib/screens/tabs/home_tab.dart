import 'package:flutter/material.dart';
import '../../services/robot_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/camera_status.dart';

class HomeTab extends StatelessWidget {
  // ---------------------------------------------------------------------------
  // PARAMETROS RECIBIDOS DESDE HOME SCREEN
  // ---------------------------------------------------------------------------
  final bool connected;                           // Estado de conexion
  final bool debugMode;                           // Modo debug
  final double batteryLevel;                      // Nivel de batería
  final int corteMinutos;                         // Minutos de corte acumulados en esta sesión
  final int duracionCorteMin;                     // Duración estimada del corte en minutos
  final List<Map<String, String>> events;         // Lista de eventos recientes
  final RobotState? robotState;
  final bool visionEnabled;                       // Habilita que ROS controle el brushless con visión
  final Color Function(String type) eventColor;   // Función para obtener el color de un evento según su tipo
  final ValueChanged<bool> onVisionChanged;       // Publica /app/vision_enable al cambiar el switch
  final VoidCallback onClearEvents;               // Callback para limpiar eventos (se llama desde el modal de eventos)

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const HomeTab({
    super.key,
    required this.connected,
    required this.debugMode,
    required this.batteryLevel,
    required this.corteMinutos,
    required this.duracionCorteMin,
    required this.events,
    required this.robotState,
    required this.visionEnabled,
    required this.eventColor,
    required this.onVisionChanged,
    required this.onClearEvents,
  });

  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  // Interfaz principal, muestra la barra de batería (junto a esta la duracion de corte), el estado de la cámara y los eventos
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBatteryBar(),
          const SizedBox(height: 16),
          CameraStatusWidget(connected: connected, debugMode: debugMode),
          const SizedBox(height: 12),
          _buildVisionSwitch(),
          const SizedBox(height: 16),
          _buildEventsWidget(context),
          const SizedBox(height: 16),
          _buildNavigationRuntimeCard(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // SWITCH DE VISIÓN
  // ON  -> 1 en /app/vision_enable; el bridge lo reexpone como /vision/enabled
  // OFF -> 0, blade_node apaga una vez y libera el brushless para pruebas manuales
  Widget _buildVisionSwitch() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: visionEnabled ? AppColors.blueLt : AppColors.gray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.visibility_rounded,
              color: visionEnabled ? AppColors.blue : AppColors.text3,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visionEnabled ? 'Visión activada' : 'Visión desactivada',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Control automático del brushless por detección de pasto',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.text2,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: visionEnabled,
            onChanged: onVisionChanged,
            activeThumbColor: AppColors.blue,
          ),
        ],
      ),
    );
  }

  // WIDGET DE BARRA DE BATERÍA Y DURACIÓN DE CORTE
  // Los valores vienen de batteryLevel y corteMinutos.
  Widget _buildBatteryBar() {
    // Calcula el porcentaje de progreso para visualizar en un circulo
    final corteProg = (corteMinutos / duracionCorteMin).clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('batteryBar'),
      color: AppColors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE0F7FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  _buildBatteryIcon(batteryLevel),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(batteryLevel * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const Text(
                        'Batería',
                        style: TextStyle(fontSize: 11, color: AppColors.text3),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 36, color: const Color(0xFFB2EBF2)),
            const SizedBox(width: 16),
            Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: corteProg,
                        strokeWidth: 4,
                        backgroundColor: const Color(0xFFB2EBF2),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.blue,
                        ),
                      ),
                      Text(
                        '$corteMinutos',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Duración',
                      style: TextStyle(fontSize: 11, color: AppColors.text3),
                    ),
                    Text(
                      'de $duracionCorteMin min',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  // WIDGET DEL ÍCONO DE BATERÍA, DEPENDIENDO DEL NIVEL, CAMBIA EL COLOR
  Widget _buildBatteryIcon(double level) {
    Color fillColor;
    if (level > 0.6) {
      fillColor = AppColors.greenOk;
    } else if (level > 0.3) {
      fillColor = AppColors.amber;
    } else {
      fillColor = AppColors.red;
    }
    return Container(
      width: 28,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.text3, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      padding: const EdgeInsets.all(1.5),
      child: FractionallySizedBox(
        widthFactor: level,
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  // WIDGET DE ESTADO DE NAVEGACION Y DEBUG
  Widget _buildNavigationRuntimeCard() {
    final statusText = robotState?.navigationRuntimeStatusText.trim() ?? '';
    final debugEvents = robotState?.navigationDebugEvents ?? const <String>[];
    final statusData = _parseNavigationStatus(statusText);
    final estado = _navigationStateLabel(statusData, statusText);

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ESTADO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            estado.isEmpty ? 'Sin estado de navegación recibido' : estado,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatusPill(
                'OBJETIVO',
                _formatNavigationValue(
                  statusData['orientacion_objetivo'],
                  suffix: '°',
                ),
              ),
              _buildStatusPill(
                'ACTUAL',
                _formatNavigationValue(
                  statusData['orientacion_actual'],
                  suffix: '°',
                ),
              ),
              _buildStatusPill(
                'GIRO',
                _formatNavigationValue(statusData['giro']),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.gray),
          const SizedBox(height: 8),
          const Text(
            'DEBUG',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          if (debugEvents.isEmpty)
            const Text(
              'Sin eventos recientes',
              style: TextStyle(fontSize: 11, color: AppColors.text2),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: debugEvents.take(4).map((event) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    event,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text2,
                      height: 1.25,
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.blueLt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blue.withOpacity(0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: AppColors.text3,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, String> _parseNavigationStatus(String rawStatus) {
    final result = <String, String>{};

    for (final part in rawStatus.split(',')) {
      final cleanPart = part.trim();
      if (cleanPart.isEmpty) continue;

      final separatorIndex = cleanPart.indexOf('=');
      if (separatorIndex < 0) {
        result.putIfAbsent('estado', () => cleanPart);
        continue;
      }

      final key = cleanPart.substring(0, separatorIndex).trim();
      final value = cleanPart.substring(separatorIndex + 1).trim();
      if (key.isNotEmpty) result[key] = value;
    }

    return result;
  }

  String _navigationStateLabel(
    Map<String, String> statusData,
    String rawStatus,
  ) {
    final estado = statusData['estado']?.trim() ?? '';
    if (estado.isNotEmpty) return estado;

    final firstPart = rawStatus.split(',').first.trim();
    return firstPart.contains('=') ? '' : firstPart;
  }

  String _formatNavigationValue(String? value, {String suffix = ''}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'S/D';

    final normalized = text.toLowerCase();
    if (normalized == 'none' || normalized == 'null') return 'S/D';

    return suffix.isEmpty ? text : '$text$suffix';
  }

  // WIDGET DE EVENTOS
  Widget _buildEventsWidget(BuildContext context) {
    final last = events.isNotEmpty ? events.last : null;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Eventos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                if (last != null)
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: eventColor(last['type']!), // Color segun tipo
                        ),
                      ),
                      Text(
                        last['time']!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.text3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          last['msg']!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Sin eventos aún',
                    style: TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showEventsModal(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.blueLt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Ver todos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.blue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  // MODAL DE EVENTOS
  // Widget del historial completo de eventos
  void _showEventsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.gray2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Historial de Eventos',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      onClearEvents();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Limpiar',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.gray2),
            Expanded(
              child: events.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay eventos registrados',
                        style: TextStyle(fontSize: 14, color: AppColors.text3),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      itemCount: events.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.gray),
                      itemBuilder: (_, i) {
                        final e = events[events.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: eventColor(e['type']!),
                                ),
                              ),
                              Text(
                                e['time']!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text3,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e['msg']!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}