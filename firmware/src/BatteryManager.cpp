#include "BatteryManager.h"
#include "pinmap.h"
#include <algorithm>

void BatteryManager::begin() {
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BATTERY_SENSOR, ADC_11db);
}

// Acumula 1 muestra ADC por ciclo; cada SAMPLE_COUNT muestras
// calcula el promedio y lo pasa por mediana + EMA
void BatteryManager::update() {
  _sampleSum += analogRead(PIN_BATTERY_SENSOR);
  _sampleCount++;

  if (_sampleCount < SAMPLE_COUNT) return;

  _raw = (int)(_sampleSum / _sampleCount);
  _sampleSum   = 0;
  _sampleCount = 0;

  float vPin    = (_raw * BATTERY_VREF) / 4095.0f;
  float reading = vPin * BATTERY_CAL * BATTERY_DIVISOR;

  // Mediana de las ultimas tandas para descartar lecturas atipicas
  _history[_historyIndex] = reading;
  _historyIndex = (_historyIndex + 1) % HISTORY_SIZE;
  if (_historyFilled < HISTORY_SIZE) _historyFilled++;
  float filtered = medianOfHistory();

  if (!_hasFiltered) {
    _batteryV    = filtered;
    _hasFiltered = true;
  } else {
    _batteryV = _batteryV * 0.9f + filtered * 0.10f;
  }
}

float BatteryManager::medianOfHistory() const {
  float sorted[HISTORY_SIZE];
  for (int i = 0; i < _historyFilled; i++) sorted[i] = _history[i];
  std::sort(sorted, sorted + _historyFilled);
  return sorted[_historyFilled / 2];
}

float BatteryManager::readBatteryVoltage() {
  return _batteryV;
}

void BatteryManager::printStatus() {
  Serial.print("BATTERY,");
  Serial.println(_batteryV, 2);
}
