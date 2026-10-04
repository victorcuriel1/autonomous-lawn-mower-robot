#pragma once
#include <Arduino.h>

class TrimmerController {
public:
  void begin();
  void update();
  void on();
  void off();
  void forceOff();   // apagado inmediato sin rampa (para emergencia)
  bool isEnabled() const;
  int  getState()  const;  // 0 o 1 para STATUS

private:
  void applyOutput(int percent);

  bool     _enabled        = false;
  int      _targetPercent  = 0;
  int      _currentPercent = 0;
  uint32_t _lastRampMs     = 0;
};
