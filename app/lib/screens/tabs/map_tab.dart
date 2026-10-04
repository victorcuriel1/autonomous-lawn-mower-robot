import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/fence_map.dart';

class MapTab extends StatelessWidget {
  // ---------------------------------------------------------------------------
  // PARAMETROS Y CALLBACKS RECIBIDOS DESDE HOME SCREEN
  // ---------------------------------------------------------------------------
  final bool mapEnabled;
  final bool campoPotencial;
  final bool definingFence;
  final bool fenceSaved;
  final bool fenceSent;
  final List<LatLng> fencePoints;
  final List<LatLng> draftFencePoints;
  final List<LatLng> robotGpsTrackPoints;
  final String navigationStatusText;
  final String navigationFenceInfo;
  final double gpsLat;
  final double gpsLon;
  final String mapGpsLabel;
  final LatLng robotPosition;
  final MapController mapController;
  final VoidCallback onStartFenceDefinition;
  final VoidCallback onCancelFenceDefinition;
  final VoidCallback onClearDraftFencePoints;
  final VoidCallback onSaveFenceDefinition;
  final VoidCallback onSendFenceToRobot;
  final VoidCallback onDeleteCurrentFence;
  final VoidCallback onCenterMapOnRobot;
  final ValueChanged<LatLng> onAddDraftFencePoint;

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const MapTab({
    super.key,
    required this.mapEnabled,
    required this.campoPotencial,
    required this.definingFence,
    required this.fenceSaved,
    required this.fenceSent,
    required this.fencePoints,
    required this.draftFencePoints,
    required this.robotGpsTrackPoints,
    required this.navigationStatusText,
    required this.navigationFenceInfo,
    required this.gpsLat,
    required this.gpsLon,
    required this.mapGpsLabel,
    required this.robotPosition,
    required this.mapController,
    required this.onStartFenceDefinition,
    required this.onCancelFenceDefinition,
    required this.onClearDraftFencePoints,
    required this.onSaveFenceDefinition,
    required this.onSendFenceToRobot,
    required this.onDeleteCurrentFence,
    required this.onCenterMapOnRobot,
    required this.onAddDraftFencePoint,
  });

  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height * 0.78;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: FenceMap(
                  mapEnabled: mapEnabled,
                  definingFence: definingFence,
                  fencePoints: fencePoints,
                  draftFencePoints: draftFencePoints,
                  robotGpsTrackPoints: robotGpsTrackPoints,
                  mapGpsLabel: mapGpsLabel,
                  robotPosition: robotPosition,
                  mapController: mapController,
                  height: null,
                  borderRadius: 0,
                  onCenterMapOnRobot: onCenterMapOnRobot,
                  onAddDraftFencePoint: onAddDraftFencePoint,
                ),
              ),
              DraggableScrollableSheet(
                minChildSize: 0.14,
                initialChildSize: 0.34,
                maxChildSize: 0.82,
                snap: true,
                snapSizes: const [0.14, 0.34, 0.82],
                builder: (context, scrollController) {
                  return _MapControlSheet(
                    scrollController: scrollController,
                    mapEnabled: mapEnabled,
                    campoPotencial: campoPotencial,
                    definingFence: definingFence,
                    fenceSaved: fenceSaved,
                    fenceSent: fenceSent,
                    draftFencePoints: draftFencePoints,
                      navigationStatusText: navigationStatusText,
                    navigationFenceInfo: navigationFenceInfo,
                    gpsLat: gpsLat,
                    gpsLon: gpsLon,
                    onStartFenceDefinition: onStartFenceDefinition,
                    onCancelFenceDefinition: onCancelFenceDefinition,
                    onClearDraftFencePoints: onClearDraftFencePoints,
                    onSaveFenceDefinition: onSaveFenceDefinition,
                    onSendFenceToRobot: onSendFenceToRobot,
                    onDeleteCurrentFence: onDeleteCurrentFence,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MapControlSheet extends StatelessWidget {
  // ---------------------------------------------------------------------------
  // PARAMETROS DEL PANEL INFERIOR DEL MAPA
  // ---------------------------------------------------------------------------
  final ScrollController scrollController;
  final bool mapEnabled;
  final bool campoPotencial;
  final bool definingFence;
  final bool fenceSaved;
  final bool fenceSent;
  final List<LatLng> draftFencePoints;
  final String navigationStatusText;
  final String navigationFenceInfo;
  final double gpsLat;
  final double gpsLon;
  final VoidCallback onStartFenceDefinition;
  final VoidCallback onCancelFenceDefinition;
  final VoidCallback onClearDraftFencePoints;
  final VoidCallback onSaveFenceDefinition;
  final VoidCallback onSendFenceToRobot;
  final VoidCallback onDeleteCurrentFence;

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const _MapControlSheet({
    required this.scrollController,
    required this.mapEnabled,
    required this.campoPotencial,
    required this.definingFence,
    required this.fenceSaved,
    required this.fenceSent,
    required this.draftFencePoints,
    required this.navigationStatusText,
    required this.navigationFenceInfo,
    required this.gpsLat,
    required this.gpsLon,
    required this.onStartFenceDefinition,
    required this.onCancelFenceDefinition,
    required this.onClearDraftFencePoints,
    required this.onSaveFenceDefinition,
    required this.onSendFenceToRobot,
    required this.onDeleteCurrentFence,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.gray2,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildFenceActions(),
          const SizedBox(height: 8),
          _buildFenceSentInfo(),
          _buildSendFenceButton(),
          const SizedBox(height: 16),
          if (campoPotencial) ...[
            _buildPotentialFieldBanner(),
            const SizedBox(height: 16),
          ],
          const SectionLabel('Informacion'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  InfoRow(label: 'Cerco actual', value: navigationFenceInfo),
                  InfoRow(
                    label: 'Posicion actual',
                    value:
                        '${gpsLat.toStringAsFixed(4)}, ${gpsLon.toStringAsFixed(4)}',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACCIONES DEL CERCO VIRTUAL
  // ---------------------------------------------------------------------------
  Widget _buildFenceActions() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) =>
          SizeTransition(sizeFactor: anim, child: child),
      child: definingFence
          ? Row(
              key: const ValueKey('fenceEditingButtons'),
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: mapEnabled
                        ? (draftFencePoints.isEmpty
                              ? onCancelFenceDefinition
                              : onClearDraftFencePoints)
                        : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.blue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      draftFencePoints.isEmpty ? 'Cancelar' : 'Limpiar puntos',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: mapEnabled ? onSaveFenceDefinition : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Guardar cerco',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SizedBox(
              key: const ValueKey('startFenceButton'),
              width: double.infinity,
              child: ElevatedButton(
                onPressed: mapEnabled ? onStartFenceDefinition : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  '+ Definir cerco virtual',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
    );
  }

  // ---------------------------------------------------------------------------
  // ESTADO DEL CERCO ENVIADO
  // ---------------------------------------------------------------------------
  Widget _buildFenceSentInfo() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: fenceSent
          ? Container(
              key: const ValueKey('fenceSentInfo'),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.greenLt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.green),
              ),
              child: const Text(
                'Cerco enviado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.green,
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('noFenceSentInfo')),
    );
  }

  Widget _buildSendFenceButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: mapEnabled && !definingFence
            ? (fenceSent
                  ? onDeleteCurrentFence
                  : (fenceSaved ? onSendFenceToRobot : null))
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: fenceSent ? AppColors.red : AppColors.green,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: Text(
          fenceSent ? 'Eliminar cerco actual' : 'Enviar cerco a CaptainP',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BANNER DE CAMPO POTENCIAL
  // ---------------------------------------------------------------------------
  Widget _buildPotentialFieldBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.blueLt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.blue,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Campo Potencial activo',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}