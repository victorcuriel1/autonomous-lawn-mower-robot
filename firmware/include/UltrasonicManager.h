#pragma once
#include <Arduino.h>

class UltrasonicManager {
public:
  // Orden de sensores (el mismo de la linea serial ULTRASONICOS):
  // left, center, right, diag_right, diag_left, back_right
  static constexpr int SENSOR_COUNT = 6;

  void begin();
  void update();       // muestrea un sensor por ciclo, llamar en cada loop()
  void printStatus();  // emite la linea ULTRASONICOS,... con la ultima lectura

private:
  struct UsFilterState {
    bool    initialized = false;
    float   filtered    = -1.0f; // valor de salida actual (-1 = sin objeto)
    float   pendingRaw  = 0.0f;  // candidato a salto esperando confirmacion
    bool    hasPending  = false;
    uint8_t jumpStreak  = 0;     // saltos seguidos sin confirmar
  };

  float filterCm(UsFilterState &state, float raw);
  float collectCm(int index);
  void  triggerPulse();

  UsFilterState _filters[SENSOR_COUNT];
  float         _lastCm[SENSOR_COUNT] = {-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f};

  uint8_t       _step       = 0;     // sensor cuya medicion esta en curso
  bool          _measuring  = false; // hay una medicion pendiente de recoger
  unsigned long _lastStepMs = 0;
};
