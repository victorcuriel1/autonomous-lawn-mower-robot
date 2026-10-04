import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
// Mapa con cerco virtual y posición del robot
class FenceMap extends StatelessWidget {
  final bool mapEnabled;
  final bool definingFence;
  final List<LatLng> fencePoints;
  final List<LatLng> draftFencePoints;
  final List<LatLng> robotGpsTrackPoints;
  final String mapGpsLabel;
  final LatLng robotPosition;
  final MapController mapController;
  final double? height;
  final double borderRadius;
  final VoidCallback onCenterMapOnRobot;
  final ValueChanged<LatLng> onAddDraftFencePoint;

  const FenceMap({
    super.key,
    required this.mapEnabled,
    required this.definingFence,
    required this.fencePoints,
    required this.draftFencePoints,
    required this.robotGpsTrackPoints,
    required this.mapGpsLabel,
    required this.robotPosition,
    required this.mapController,
    this.height = 320,
    this.borderRadius = 16,
    required this.onCenterMapOnRobot,
    required this.onAddDraftFencePoint,
  });
  
  @override
  Widget build(BuildContext context) {
    final canMarkFence = mapEnabled && definingFence;                           // Se puede marcar el cerco virtual solo si el mapa está habilitado y se está definiendo el cerco
    final visibleFencePoints = definingFence ? draftFencePoints : fencePoints;  // Se muestran los puntos del cerco virtual según si se está definiendo o no
    // Se construye el widget del mapa con cerco virtual y posición del robot
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.gray2),
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: robotPosition,
              initialZoom: 18,
              minZoom: 3,
              maxZoom: 20,
              interactionOptions: InteractionOptions(
                flags: mapEnabled ? InteractiveFlag.all : InteractiveFlag.none,
              ),
              onTap: canMarkFence
                  ? (_, latLng) => onAddDraftFencePoint(latLng)
                  : null,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.captainpingui.app',
              ),
              PolygonLayer(
                polygons: [
                  if (visibleFencePoints.length >= 3)
                    Polygon(
                      points: visibleFencePoints,
                      color: AppColors.blue.withOpacity(0.14),
                      borderColor: AppColors.blue,
                      borderStrokeWidth: 3,
                    ),
                ],
              ),
              PolylineLayer(
                polylines: [
                  if (robotGpsTrackPoints.length >= 2)
                    Polyline(
                      points: robotGpsTrackPoints,
                      color: AppColors.green,
                      strokeWidth: 4,
                    ),
                  if (visibleFencePoints.length == 2)
                    Polyline(
                      points: visibleFencePoints,
                      color: AppColors.blue,
                      strokeWidth: 3,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: robotPosition,
                    width: 30,
                    height: 30,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.green,
                        border: Border.all(color: AppColors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 5,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: AppColors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  ...List.generate(visibleFencePoints.length, (i) {
                    return Marker(
                      point: visibleFencePoints[i],
                      width: 30,
                      height: 30,
                      child: Container(
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.blue,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          if (!mapEnabled) Container(color: AppColors.white.withOpacity(0.62)),
          Positioned(
            left: 16,
            top: 14,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    mapEnabled
                        ? mapGpsLabel
                        : 'Mapa no disponible sin conexión al robot',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: mapEnabled ? AppColors.text : AppColors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: mapEnabled ? onCenterMapOnRobot : null,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: mapEnabled ? AppColors.blueLt : AppColors.gray,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.my_location_rounded,
                      size: 16,
                      color: mapEnabled ? AppColors.blue : AppColors.text3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: mapEnabled ? AppColors.blueLt : AppColors.gray,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${visibleFencePoints.length} pts',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: mapEnabled ? AppColors.blue : AppColors.text3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            bottom: 14,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                mapEnabled
                    ? (definingFence
                          ? 'Tocá el mapa para marcar el límite de operación.'
                          : 'Presioná + Definir cerco virtual para habilitar el marcado.')
                    : 'Activá Modo Debug o conectá el robot para usar el mapa.',
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}