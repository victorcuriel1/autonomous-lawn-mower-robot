import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mjpeg_view/mjpeg_view.dart';
import '../config/app_config.dart';

enum CameraFeed { obstacle, grass }

// Widget para mostrar el estado de la cámara y su stream
class CameraStatusWidget extends StatefulWidget {
  final bool connected;
  final bool debugMode;

  const CameraStatusWidget({
    super.key,
    required this.connected,
    this.debugMode = true,
  });

  @override
  State<CameraStatusWidget> createState() => _CameraStatusWidgetState();
}

class _CameraStatusWidgetState extends State<CameraStatusWidget> {
  OverlayEntry? _overlayEntry;    // Guarda la pantalla de cámara
  Timer? _streamRetryTimer;       // Para reintentar cargar el stream si falla
  int _streamVersion = 0;         // Para forzar recarga del stream al cambiar la URL o reintentar
  CameraFeed _selectedFeed = CameraFeed.obstacle; // Camara lógica seleccionada: obstaculos o pasto
  bool get _isOnBoard => widget.debugMode ? AppConfig.debugCameraOnBoard : widget.connected; // En modo debug se puede simular el estado de la cámara

  // URL actualmente visible. La IP viene de AppConfig.robotIp y el topic depende del boton elegido
  String get _selectedStreamUrl => _streamUrlForFeed(_selectedFeed);
  String get _selectedFeedLabel => _feedLabel(_selectedFeed);

  String _streamUrlForFeed(CameraFeed feed) {
    switch (feed) {
      case CameraFeed.obstacle:
        return AppConfig.obstacleCameraStreamUrl;
      case CameraFeed.grass:
        return AppConfig.grassCameraStreamUrl;
    }
  }

  String _feedLabel(CameraFeed feed) {
    switch (feed) {
      case CameraFeed.obstacle:
        return 'Obstáculo';
      case CameraFeed.grass:
        return 'Pasto';
    }
  }

  // Cambia de stream y fuerza la recarga del MJPEG para que no quede mostrando el stream anterior
  void _selectFeed(CameraFeed feed) {
    if (_selectedFeed == feed) return;
    setState(() {
      _selectedFeed = feed;
      _streamVersion++;
    });
  }

  // Funcion para refrescar el stream, basicamente anula la variable del refresh indicando que ya lo hizo, incrementa la version de recarga
  // la cual cada que cambia se rendereiza
  void _refreshStream() {
    _streamRetryTimer?.cancel();  // Si existe, se cancela, si no...
    _streamRetryTimer = null;     // Se hace nulo
    if (!mounted) return;         // Si el widget no está montado, no hace nada
    setState(() => _streamVersion++);   // Aumenta version para forzar recarga del stream
  }

  // Programa un reintento para cargar el stream después de un error
  // Si hay un timer activo, sale de la funcion, si no, programa uno para dentro de 2 segundos
  void _scheduleStreamRetry() {
    if (_streamRetryTimer?.isActive ?? false) return;
    _streamRetryTimer = Timer(const Duration(seconds: 2), () {
      // Cuando el timer se dispara, se anula el timer y si el widget sigue montado y la cámara está on board
      // se incrementa la versión para reintentar cargar el stream
      _streamRetryTimer = null;
      if (mounted && _isOnBoard) {
        setState(() => _streamVersion++);
      }
    });
  }
  // Entra en modo pantalla completa para la cámara
  void _enterFullscreen() {
    // Si ya hay una pantalla de cámara abierta, sale
    if (_overlayEntry != null) return;
    // Cambia la orientación a horizontal 
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Crea una nueva pantalla de cámara y la inserta en el overlay
    _overlayEntry = OverlayEntry(
      builder: (_) => _FullscreenCamera(
        isOnBoard: _isOnBoard,
        streamUrl: _selectedStreamUrl,
        feedLabel: _selectedFeedLabel,
        onClose: _exitFullscreen,
      ),
    );
    // Inserta la pantalla en el overlay para mostrarla
    Overlay.of(context).insert(_overlayEntry!);
  }

  // Sale del modo pantalla completa
  void _exitFullscreen() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Cuando el widget se destruye, se limpia la pantalla de cámara y se restablece la orientación
  @override
  void dispose() {
    _overlayEntry?.remove();
    _streamRetryTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade700, width: 1.5),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned.fill(
            child: _isOnBoard
                ? MjpegView(
                    key: ValueKey(
                      '$_selectedStreamUrl-$_streamVersion',
                    ),
                    uri: _selectedStreamUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_) {
                      _scheduleStreamRetry();
                      return const _CameraLoading(fontSize: 11);
                    },
                  )
                : _buildOffBoardView(),
          ),
          Positioned(
            top: 10,
            left: 12,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isOnBoard ? Colors.greenAccent : Colors.redAccent,
                    boxShadow: [
                      BoxShadow(
                        color: (_isOnBoard ? Colors.green : Colors.red)
                            .withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnBoard ? 'ON BOARD - $_selectedFeedLabel' : 'OFF BOARD',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Row(
              children: [
                _CameraIconButton(
                  icon: Icons.refresh_rounded,
                  onTap: _refreshStream,
                ),
                const SizedBox(width: 6),
                _CameraIconButton(
                  icon: Icons.open_in_full_rounded,
                  onTap: _enterFullscreen,
                ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              children: [
                Expanded(
                  child: _CameraFeedButton(
                    label: 'Obstáculo',
                    selected: _selectedFeed == CameraFeed.obstacle,
                    onTap: () => _selectFeed(CameraFeed.obstacle),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CameraFeedButton(
                    label: 'Pasto',
                    selected: _selectedFeed == CameraFeed.grass,
                    onTap: () => _selectFeed(CameraFeed.grass),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // Construye la vista para cuando la cámara está off board, mostrando la imagen del pinguino de fondo
  Widget _buildOffBoardView() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/offboard.png', fit: BoxFit.cover),
        Container(color: Colors.black38),
      ],
    );
  }
}
// Pantalla de cámara en modo pantalla completa
class _FullscreenCamera extends StatefulWidget {
  final bool isOnBoard;
  final String streamUrl;
  final String feedLabel;
  final VoidCallback onClose;

  const _FullscreenCamera({
    required this.isOnBoard,
    required this.streamUrl,
    required this.feedLabel,
    required this.onClose,
  });

  @override
  State<_FullscreenCamera> createState() => _FullscreenCameraState();
}

class _FullscreenCameraState extends State<_FullscreenCamera> {
  Timer? _streamRetryTimer;
  int _streamVersion = 0;

  void _refreshStream() {
    _streamRetryTimer?.cancel();
    _streamRetryTimer = null;
    if (!mounted) return;
    setState(() => _streamVersion++);
  }

  void _scheduleStreamRetry() {
    if (_streamRetryTimer?.isActive ?? false) return;
    _streamRetryTimer = Timer(const Duration(seconds: 2), () {
      _streamRetryTimer = null;
      if (mounted && widget.isOnBoard) {
        setState(() => _streamVersion++);
      }
    });
  }

  @override
  void dispose() {
    _streamRetryTimer?.cancel();
    super.dispose();
  }

  //---------------------------------------------------------------------
  //                      BUILD
  //---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.isOnBoard
                  ? MjpegView(
                      key: ValueKey(
                        '${widget.streamUrl}-fullscreen-$_streamVersion',
                      ),
                      uri: widget.streamUrl,
                      fit: BoxFit.contain,
                      errorWidget: (_) {
                        _scheduleStreamRetry();
                        return const _CameraLoading(
                          fontSize: 14,
                          showHint: true,
                        );
                      },
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          'assets/images/offboard.png',
                          fit: BoxFit.contain,
                        ),
                        Container(color: Colors.black54),
                      ],
                    ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.isOnBoard
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isOnBoard
                          ? 'ON BOARD - ${widget.feedLabel}'
                          : 'OFF BOARD',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    _CameraIconButton(
                      icon: Icons.refresh_rounded,
                      onTap: _refreshStream,
                    ),
                    const SizedBox(width: 8),
                    _CameraIconButton(
                      icon: Icons.close_fullscreen_rounded,
                      onTap: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Botón de ícono para acciones de la cámara (refrescar, pantalla completa, etc)
class _CameraIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CameraIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}
// Botón inferior para elegir qué stream ver dentro del mismo visor.
class _CameraFeedButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CameraFeedButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.black54,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
// Para mostrar un mensaje de carga mientras se conecta a la cámara
class _CameraLoading extends StatelessWidget {
  final double fontSize;
  final bool showHint;

  const _CameraLoading({required this.fontSize, this.showHint = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Colors.white38,
            strokeWidth: 2,
          ),
          const SizedBox(height: 10),
          Text(
            'Conectando camara...',
            style: TextStyle(color: Colors.white54, fontSize: fontSize),
          ),
          if (showHint) ...[
            const SizedBox(height: 6),
            const Text(
              'Verifica que el robot este encendido\ny en la misma red WiFi',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}