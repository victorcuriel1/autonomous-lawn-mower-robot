import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/robot_connection.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_widgets.dart';

class SensorsTab extends StatefulWidget {
  // ---------------------------------------------------------------------------
  // PARAMETROS RECIBIDOS DESDE HOME SCREEN
  // ---------------------------------------------------------------------------
  final double batteryVoltage;
  final double batteryLevel;
  final double imuInclination;
  final double imuHeading;
  final double imuRoll;
  final double imuPitch;
  final double imuYaw;
  final bool imuCalibrated;
  final double gpsLat;
  final double gpsLon;
  final int gpsSatellites;
  final double usLeftCm;
  final double usFrontCm;
  final double usRightCm;
  final double usDiagonalRightCm;
  final double usDiagonalLeftCm;
  final double usRearRightCm;
  final bool bumperLeft;
  final bool bumperRight;
  final bool bumperBack;
  final bool bumperFrontLeft;
  final bool bumperFrontRight;
  final bool liftDetected;
  final RobotConnection? robot;
  final void Function(String message, String type)? onEvent;

  // ---------------------------------------------------------------------------
  // CONSTRUCTOR
  // ---------------------------------------------------------------------------
  const SensorsTab({
    super.key,
    required this.batteryVoltage,
    required this.batteryLevel,
    required this.imuInclination,
    required this.imuHeading,
    required this.imuRoll,
    required this.imuPitch,
    required this.imuYaw,
    required this.imuCalibrated,
    required this.gpsLat,
    required this.gpsLon,
    required this.gpsSatellites,
    required this.usLeftCm,
    required this.usFrontCm,
    required this.usRightCm,
    required this.usDiagonalRightCm,
    required this.usDiagonalLeftCm,
    required this.usRearRightCm,
    required this.bumperLeft,
    required this.bumperRight,
    required this.bumperBack,
    required this.bumperFrontLeft,
    required this.bumperFrontRight,
    required this.liftDetected,
    required this.robot,
    required this.onEvent,
  });

  @override
  State<SensorsTab> createState() => _SensorsTabState();
}

class _SensorsTabState extends State<SensorsTab> {
  // ---------------------------------------------------------------------------
  // ESTADO INTERNO DE LA PESTANA
  // ---------------------------------------------------------------------------
  bool _showImuDetails = false;
  bool _calibrating = false;
  bool _yawResetFeedback = false;
  Timer? _calibrationFeedbackTimer;
  Timer? _yawFeedbackTimer;

  // ---------------------------------------------------------------------------
  // CICLO DE VIDA
  // ---------------------------------------------------------------------------
  @override
  void didUpdateWidget(covariant SensorsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_calibrating && !oldWidget.imuCalibrated && widget.imuCalibrated) {
      _stopCalibratingFeedback();
    }
  }

  @override
  void dispose() {
    _calibrationFeedbackTimer?.cancel();
    _yawFeedbackTimer?.cancel();
    super.dispose();
  }
 
  // ---------------------------------------------------------------------------
  // HELPERS DE ESTADO VISUAL
  // ---------------------------------------------------------------------------
  Color _batteryColor(double level) {
    if (level < 0.20) return AppColors.red;
    if (level < 0.50) return AppColors.amber;
    return AppColors.greenOk;
  }

  String get _calibrationLabel {
    if (_calibrating) return 'Calibrando';
    return widget.imuCalibrated ? 'OK' : 'Sin calibrar';
  }

  Color get _calibrationColor {
    if (_calibrating) return AppColors.amber;
    return widget.imuCalibrated ? AppColors.greenOk : AppColors.text3;
  }

  // ---------------------------------------------------------------------------
  // ACCIONES DE IMU
  // ---------------------------------------------------------------------------
  void _handleCalibrate() {
    widget.robot!.sendImuCalibrate();
    widget.onEvent?.call('Calibrando IMU', 'warn');
    setState(() => _calibrating = true);
    _calibrationFeedbackTimer?.cancel();
    _calibrationFeedbackTimer = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      _stopCalibratingFeedback();
    });
  }

  void _handleResetYaw() {
    widget.robot!.sendImuResetYaw();
    widget.onEvent?.call('Yaw IMU reiniciado', 'ok');
    setState(() => _yawResetFeedback = true);
    _yawFeedbackTimer?.cancel();
    _yawFeedbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _yawResetFeedback = false);
    });
  }

  void _stopCalibratingFeedback() {
    _calibrationFeedbackTimer?.cancel();
    if (mounted) {
      setState(() => _calibrating = false);
    }
  }

  String _formatDistance(double cm) {
    // 0 indica que todavia no llego lectura valida desde ROS.
    if (cm <= 0) return '--';
    return '${cm.round()}';
  }
  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Estado General'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              _sensorCard(
                'BATERIA',
                '${(widget.batteryLevel * 100).round()}',
                '%',
                widget.batteryLevel,
                _batteryColor(widget.batteryLevel),
                subtitle: '${widget.batteryVoltage.toStringAsFixed(2)} V',
              ),
              _gpsCard(),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel('IMU'),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.4,
            children: [
              _sensorCard(
                'INCLINACION',
                widget.imuInclination.toStringAsFixed(1),
                '°',
                (widget.imuInclination.abs() / 90).clamp(0.0, 1.0),
                AppColors.blue,
              ),
              _sensorCard(
                'ORIENTACION',
                '${widget.imuHeading.round() % 360}',
                '°',
                widget.imuHeading / 360,
                AppColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(
                  label: 'Calibración',
                  value: _calibrationLabel,
                  valueColor: _calibrationColor,
                  showDivider: false,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _imuActionButton(
                        _calibrating ? 'Calibrando...' : 'Calibrar',
                        busy: _calibrating,
                        onTap: widget.robot == null || _calibrating
                            ? null
                            : _handleCalibrate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _imuActionButton(
                        _yawResetFeedback ? 'Yaw en 0' : 'Reset yaw',
                        activeFeedback: _yawResetFeedback,
                        onTap: widget.robot == null ? null : _handleResetYaw,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _moreInfoButton(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _showImuDetails
                      ? Padding(
                          key: const ValueKey('imuDetails'),
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            children: [
                              InfoRow(
                                label: 'Roll',
                                value: '${widget.imuRoll.toStringAsFixed(1)}°',
                              ),
                              InfoRow(
                                label: 'Pitch',
                                value: '${widget.imuPitch.toStringAsFixed(1)}°',
                              ),
                              InfoRow(
                                label: 'Yaw relativo',
                                value: '${widget.imuYaw.toStringAsFixed(1)}°',
                                showDivider: false,
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('noImuDetails')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Ultrasonidos'),
          Column(
            children: [
              // Distribucion fisica: fila frontal del robot.
              Row(
                children: [
                  Expanded(child: _usCard('DIAG IZQ', _formatDistance(widget.usDiagonalLeftCm))),
                  const SizedBox(width: 8),
                  Expanded(child: _usCard('FRENTE', _formatDistance(widget.usFrontCm))),
                  const SizedBox(width: 8),
                  Expanded(child: _usCard('DIAG DER', _formatDistance(widget.usDiagonalRightCm))),
                ],
              ),
              const SizedBox(height: 8),
              // Laterales del robot.
              Row(
                children: [
                  Expanded(child: _usCard('IZQ', _formatDistance(widget.usLeftCm))),
                  const SizedBox(width: 8),
                  Expanded(child: _usCard('DER', _formatDistance(widget.usRightCm))),
                ],
              ),
              const SizedBox(height: 8),
              // Parte trasera del robot.
              Row(
                children: [
                  Expanded(child: _usCard('TRAS DER', _formatDistance(widget.usRearRightCm))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel('Bumpers'),
          Column(
            children: [
              // Bumpers frontales.
              Row(
                children: [
                  Expanded(child: _bumperCard('FR. IZQ', !widget.bumperFrontLeft)),
                  const SizedBox(width: 8),
                  Expanded(child: _bumperCard('FR. DER', !widget.bumperFrontRight)),
                ],
              ),
              const SizedBox(height: 8),
              // Bumpers laterales y trasero.
              Row(
                children: [
                  Expanded(child: _bumperCard('IZQ', !widget.bumperLeft)),
                  const SizedBox(width: 8),
                  Expanded(child: _bumperCard('TRASERO', !widget.bumperBack)),
                  const SizedBox(width: 8),
                  Expanded(child: _bumperCard('DER', !widget.bumperRight)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const SectionLabel('Levantamiento'),
          Row(
            children: [
              Expanded(child: _liftCard('FC Base', widget.liftDetected)),
              const SizedBox(width: 8),
              Expanded(
                child: _liftCard(
                  'IMU Tilt',
                  widget.imuInclination.abs() > 30.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'OK = robot en suelo · ALERTA = robot levantado o volcado',
            style: TextStyle(fontSize: 10, color: AppColors.text3),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS DE ESTADO GENERAL E IMU
  // ---------------------------------------------------------------------------
  Widget _gpsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GPS',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'FIX·${widget.gpsSatellites}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.gpsLat.toStringAsFixed(4)}°, ${widget.gpsLon.toStringAsFixed(4)}°',
            style: const TextStyle(fontSize: 10, color: AppColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _sensorCard(
    String name,
    String val,
    String unit,
    double fill,
    Color fillColor, {
    String? subtitle,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              text: val,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
              children: [
                TextSpan(
                  text: unit,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.text3),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: fill,
              backgroundColor: AppColors.gray2,
              valueColor: AlwaysStoppedAnimation(fillColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moreInfoButton() {
    return GestureDetector(
      onTap: () => setState(() => _showImuDetails = !_showImuDetails),
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.gray,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          _showImuDetails ? 'Ocultar info' : 'Más info',
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // WIDGETS DE SENSORES DISCRETOS
  // ---------------------------------------------------------------------------

  Widget _usCard(String label, String val) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            val,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const Text(
            'cm',
            style: TextStyle(fontSize: 10, color: AppColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _imuActionButton(
    String label, {
    VoidCallback? onTap,
    bool busy = false,
    bool activeFeedback = false,
  }) {
    final enabled = onTap != null;
    final color = activeFeedback
        ? AppColors.greenOk
        : busy
        ? AppColors.amber
        : enabled
        ? AppColors.blue
        : AppColors.gray2;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled || busy || activeFeedback
                ? AppColors.white
                : AppColors.text3,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _bumperCard(String label, bool ok) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ok ? 'OK' : 'HIT',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: ok ? AppColors.greenOk : AppColors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liftCard(String label, bool activated) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.text3,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            activated ? 'ALERTA' : 'OK',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: activated ? AppColors.red : AppColors.greenOk,
            ),
          ),
        ],
      ),
    );
  }
}




