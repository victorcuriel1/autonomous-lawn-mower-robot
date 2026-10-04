#pragma once
#include <Arduino.h>

class BatteryManager {
public:
  void  begin();
  void  update();  // toma 1 muestra ADC por ciclo, llamar en cada loop()
  float readBatteryVoltage();
  void  printStatus();

private:
  static constexpr int SAMPLE_COUNT  = 500;
  static constexpr int HISTORY_SIZE  = 5;  // tandas para la mediana (impar)

  int   _raw         = 0;
  float _batteryV    = 0.0f;
  bool  _hasFiltered = false;

  long  _sampleSum   = 0;
  int   _sampleCount = 0;

  float _history[HISTORY_SIZE] = {0};
  int   _historyIndex  = 0;
  int   _historyFilled = 0;

  float medianOfHistory() const;
};
