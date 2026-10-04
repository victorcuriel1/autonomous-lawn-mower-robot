import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../config/app_config.dart';

typedef ConfigEditCallback =
    void Function({
      required String label,
      required String current,
      required String hint,
      required ValueChanged<String> onSave,
      required TextInputType keyboardType,
      String? Function(String)? validator,
    });

class ConfigTab extends StatelessWidget {
// ---------------------------------------------------------------------------
// PARAMETROS Y CALLBACKS RECIBIDOS DESDE HOME SCREEN
// ---------------------------------------------------------------------------
// Parametros recibidos desde HomeScreen
  final String robotIp;                                 // IP del robot
  final String rosPort;                                 // Puerto ROS2
  final String obstacleCameraUrl;                       // URL fija del stream de obstaculos, armada con la IP actual
  final String grassCameraUrl;                          // URL fija del stream de pasto, armada con la IP actual
  final int cutDurationMin;                             // Duración de corte en minutos
  final int estimatedRuntimeMin;                        // Tiempo estimado de ejecución en minutos
  final bool debugMode;                                 // Indica si el modo debug está activado. En modo debug, la app simula datos sin conectarse al robot  
  final bool connectionConfigChanged;                   // Indica si la configuración de conexión ha cambiado
  final VoidCallback? onApplyConnectionConfig;          // Callback para aplicar la nueva configuración de conexión. Es nulo si no hay cambios o si la configuración es inválida
  final ValueChanged<bool> onDebugModeChanged;          // Recibe el nuevo valor del modo debug cuando el usuario lo cambia
  final ConfigEditCallback onEditField;                 // ConfigEditCallback es un type defindo arriba, esto ya que hay mandar un dialogo y tiene muchos parametros, para no tener que escribir todos estos, se define el type
  final ValueChanged<String> onRobotIpChanged;          // Recibe el nuevo valor de la IP del robot cuando el usuario lo cambia. Avisa a HomeScreen para actualizar el estado
  final ValueChanged<String> onRosPortChanged;          // Recibe el nuevo valor del puerto ROS2 cuando el usuario lo cambia. Avisa a HomeScreen para actualizar el estado
  final ValueChanged<int> onCutDurationChanged;         // Recibe el nuevo valor de la duración de corte en minutos cuando el usuario lo cambia. Avisa a HomeScreen para actualizar el estado
  final VoidCallback onInvalidCutDuration;              // Cuando el usuario ingresa una duración de corte inválida, se llama a este callback para mostrar un mensaje de error
  final String? Function(String) validateIp;
  final String? Function(String) validatePort;
  final String? Function(String) validateCutDuration;
  final List<RobotConnectionProfile> connectionProfiles;
  final ValueChanged<RobotConnectionProfile> onApplyConnectionProfile;
  final Future<void> Function(String label) onSaveCurrentConnectionProfile;
  final Future<void> Function(String label) onDeleteConnectionProfile;

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const ConfigTab({
    super.key,
    required this.robotIp,
    required this.rosPort,
    required this.obstacleCameraUrl,
    required this.grassCameraUrl,
    required this.cutDurationMin,
    required this.estimatedRuntimeMin,
    required this.debugMode,
    required this.connectionConfigChanged,
    required this.onApplyConnectionConfig,
    required this.onDebugModeChanged,
    required this.onEditField,
    required this.onRobotIpChanged,
    required this.onRosPortChanged,
    required this.onCutDurationChanged,
    required this.onInvalidCutDuration,
    required this.validateIp,
    required this.validatePort,
    required this.validateCutDuration,
    required this.connectionProfiles,
    required this.onApplyConnectionProfile,
    required this.onSaveCurrentConnectionProfile,
    required this.onDeleteConnectionProfile,
  });
  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  // Cnstruye toda la pantalla de configuracion. Usa SingleChildScrollView para permitir scroll si el contenido es muy largo
  // Aca se organizan todos los campos de tipo ConfigRow y StaticConfigRow
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Conexión con el Robot'),
          if (connectionProfiles.isNotEmpty) ...[
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: connectionProfiles.map((profile) {
                  return ListTile(
                    title: Text(profile.label),
                    subtitle: Text(profile.ip),
                    onTap: () => onApplyConnectionProfile(profile),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDeleteConnectionProfile(profile.label),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: () => _showSaveProfileDialog(context),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Guardar IP actual'),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildConfigRow(
                    label: 'IP del Robot',
                    value: robotIp,
                    hint: '192.168.1.100',
                    onSave: onRobotIpChanged,
                    validator: validateIp,
                    keyboardType: TextInputType.url,
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildConfigRow(
                    label: 'Puerto ROS2',
                    value: rosPort,
                    hint: '9090',
                    onSave: onRosPortChanged,
                    validator: validatePort,
                    keyboardType: TextInputType.number,
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildStaticConfigRow(
                    label: 'URL Obstáculo',
                    value: obstacleCameraUrl,
                    longValue: true,
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildStaticConfigRow(
                    label: 'URL Pasto',
                    value: grassCameraUrl,
                    longValue: true,
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildConfigRow(
                    label: 'Duración de corte',
                    value: '$cutDurationMin min',
                    editValue: '$cutDurationMin',
                    hint: '60',
                    onSave: (value) {
                      final minutes = int.tryParse(value);
                      if (minutes == null || minutes <= 0) {
                        onInvalidCutDuration();
                        return;
                      }
                      onCutDurationChanged(minutes);
                    },
                    validator: validateCutDuration,
                    keyboardType: TextInputType.number,
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildStaticConfigRow(
                    label: 'Autonomía estimada',
                    value: '$estimatedRuntimeMin min',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onApplyConnectionConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: connectionConfigChanged
                    ? AppColors.blue
                    : AppColors.gray2,
                disabledBackgroundColor: AppColors.gray2,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Guardar IP:Puerto y Reconectar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Desarrollo'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Modo Debug',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.text,
                                ),
                              ),
                              Text(
                                'Simula la app sin conexión con el robot',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Interruptor para el modo debug
                        Switch(
                          value: debugMode,
                          onChanged: onDebugModeChanged,
                          activeColor: AppColors.amber,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.gray),
                  _buildStaticConfigRow(label: 'Versión', value: '4.1'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  // ---------------------------------------------------------------------------
  // WIDGETS AUXILIARES DE FILAS DE CONFIGURACION
  // ---------------------------------------------------------------------------
  // Filas editables. Caundo el usuario toca la fila, se llama a onEditField que abre un diálogo de edición
  Future<void> _showSaveProfileDialog(BuildContext context) async {
    var profileLabel = '';

    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar IP actual'),
        content: TextField(
          autofocus: false,
          textInputAction: TextInputAction.done,
          onChanged: (value) => profileLabel = value,
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
          decoration: const InputDecoration(
            labelText: 'Etiqueta',
            hintText: 'Casa, Facultad, Hotspot...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(profileLabel.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    final trimmedLabel = label?.trim() ?? '';
    if (trimmedLabel.isEmpty) return;
    if (!context.mounted) return;

    await onSaveCurrentConnectionProfile(trimmedLabel);
  }

  Widget _buildConfigRow({
    required String label,
    required String value,
    required String hint,
    required ValueChanged<String> onSave,
    String? editValue,
    String? Function(String)? validator,
    bool longValue = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return GestureDetector(
      onTap: () => onEditField(
        label: label,
        current: editValue ?? value,
        hint: hint,
        keyboardType: keyboardType,
        validator: validator,
        onSave: onSave,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: longValue
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.text3,
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.text3,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.text3,
                  ),
                ],
              ),
      ),
    );
  }
  // Filas no editables, solo muestran información. No tienen interacción al tocarlas
  Widget _buildStaticConfigRow({
    required String label,
    required String value,
    bool longValue = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: longValue
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                    ),
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14, color: AppColors.text3),
                ),
              ],
            ),
    );
  }
}




