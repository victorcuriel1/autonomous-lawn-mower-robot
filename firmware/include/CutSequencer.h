#pragma once
#include <Arduino.h>
#include "TrimmerController.h"
#include "BrushlessController.h"

// Espera desde que arrancan las ruedas hasta habilitar el brushless (ms)
static const uint32_t CUT_DELAY_AFTER_WHEELS_MS        = 1000;
// Espera desde que arranca el brushless hasta habilitar el trimmer (ms)
static const uint32_t TRIMMER_DELAY_AFTER_BRUSHLESS_MS = 2000;

class CutSequencer {
public:
  enum State { IDLE, WAIT_WHEELS, WAIT_BRUSHLESS, RUNNING };

  void begin(TrimmerController* trimmer, BrushlessController* brushless);

  // Estado pedido de cada motor de corte
  void request(bool trimmerWanted, bool brushlessWanted);

  // Avisa que CMD_MOTORES puso RPM distinto de cero
  void notifyWheelsStarted();

  // Apaga todo y resetea la secuencia (para CMD_ESTOP)
  void cancelAll();

  // Llamar en cada loop()
  void update();

private:
  TrimmerController*   _trimmer   = nullptr;
  BrushlessController* _brushless = nullptr;

  State    _state            = IDLE;
  bool     _trimmerWanted    = false;
  bool     _brushlessWanted  = false;
  uint32_t _lastWheelStartMs = 0;
  bool     _wheelsStarted    = false;
  uint32_t _stateStartMs     = 0;

  void _startBrushless();
  void _startTrimmer();
  void _stopAll(bool force);
};
