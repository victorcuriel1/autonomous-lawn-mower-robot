#include "UltrasonicManager.h"
#include "pinmap.h"

// Filtro de ruido: umbral de salto relativo a la distancia
// (mas sensible cerca, mas tolerante lejos)
static constexpr float US_JUMP_REL_FRACTION = 0.3f;
static constexpr float US_JUMP_MIN_CM       = 15.0f;
static constexpr float US_JUMP_MAX_CM       = 60.0f;
static constexpr uint8_t US_STUCK_LIMIT     = 3;
static constexpr float US_ALPHA             = 0.5f;

// Pines ECHO en el mismo orden de la linea serial ULTRASONICOS
static const int US_ECHO_PINS[UltrasonicManager::SENSOR_COUNT] = {
  US_LEFT_ECHO_PIN,
  US_CENTER_ECHO_PIN,
  US_RIGHT_ECHO_PIN,
  US_DIAG_RIGHT_ECHO_PIN,
  US_DIAG_LEFT_ECHO_PIN,
  US_BACK_RIGHT_ECHO_PIN,
};

// El ECHO se mide por interrupciones: la ISR captura con micros()
// el flanco de subida y el de bajada, y el loop recoge el resultado
// en el ciclo siguiente, sin bloquear.

static volatile uint32_t s_echoRiseUs[UltrasonicManager::SENSOR_COUNT]     = {0};
static volatile uint32_t s_echoDurationUs[UltrasonicManager::SENSOR_COUNT] = {0};
static volatile bool     s_echoDone[UltrasonicManager::SENSOR_COUNT]       = {false};

static void IRAM_ATTR echoIsr(void *arg) {
  int idx = (int)(intptr_t)arg;

  if (digitalRead(US_ECHO_PINS[idx])) {
    s_echoRiseUs[idx] = micros();
    s_echoDone[idx]   = false;
  } else {
    s_echoDurationUs[idx] = micros() - s_echoRiseUs[idx];
    s_echoDone[idx]       = true;
  }
}

void UltrasonicManager::begin() {
  pinMode(US_TRIG_PIN, OUTPUT);
  digitalWrite(US_TRIG_PIN, LOW);

  for (int i = 0; i < SENSOR_COUNT; i++) {
    pinMode(US_ECHO_PINS[i], INPUT);
    attachInterruptArg(US_ECHO_PINS[i], echoIsr, (void *)(intptr_t)i, CHANGE);
  }
}

// Pulso TRIG compartido por todos los sensores: 2us LOW + 10us HIGH
void UltrasonicManager::triggerPulse() {
  digitalWrite(US_TRIG_PIN, LOW);
  delayMicroseconds(2);

  digitalWrite(US_TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(US_TRIG_PIN, LOW);
}

// Recoge la medicion capturada por la ISR. -1 si no llego eco
// o si el pulso supera US_TIMEOUT_US (fuera de rango).
float UltrasonicManager::collectCm(int index) {
  noInterrupts();
  bool     done     = s_echoDone[index];
  uint32_t duration = s_echoDurationUs[index];
  interrupts();

  if (!done || duration == 0 || duration > US_TIMEOUT_US) return -1.0f;

  // velocidad del sonido 0.0343 cm/us, dividido 2 por ida y vuelta
  return (duration * 0.0343f) / 2.0f;
}

// Rechazo de outliers con confirmacion + EMA. Un salto se descarta
// la primera vez (probable eco fantasma); si se repite en la lectura
// siguiente se acepta como cambio real. Si el salto persiste varios
// ciclos sin confirmarse, se fuerza el valor crudo para no quedar
// pegado a una lectura vieja.
float UltrasonicManager::filterCm(UsFilterState &state, float raw) {
  if (!state.initialized) {
    state.initialized = true;
    state.filtered = raw;
    return state.filtered;
  }

  bool rawHasObject = raw >= 0;
  bool refHasObject  = state.filtered >= 0;

  float jumpThreshold = US_JUMP_MIN_CM;
  if (refHasObject) {
    jumpThreshold = constrain(state.filtered * US_JUMP_REL_FRACTION, US_JUMP_MIN_CM, US_JUMP_MAX_CM);
  }

  bool isJump = (rawHasObject != refHasObject) ||
                (rawHasObject && refHasObject &&
                 fabsf(raw - state.filtered) > jumpThreshold);

  if (!isJump) {
    state.jumpStreak = 0;
    state.hasPending = false;
    if (rawHasObject) {
      state.filtered = US_ALPHA * raw + (1.0f - US_ALPHA) * state.filtered;
    } else {
      state.filtered = -1.0f;
    }
    return state.filtered;
  }

  state.jumpStreak++;

  bool pendingMatches = state.hasPending &&
                        (rawHasObject == (state.pendingRaw >= 0)) &&
                        (!rawHasObject || fabsf(raw - state.pendingRaw) <= jumpThreshold);

  if (pendingMatches || state.jumpStreak >= US_STUCK_LIMIT) {
    state.hasPending = false;
    state.jumpStreak = 0;
    state.filtered = raw;
    return state.filtered;
  }

  state.pendingRaw = raw;
  state.hasPending = true;
  return state.filtered;
}

// Cada 40ms recoge el resultado de la medicion disparada en el tick
// anterior y dispara la del sensor siguiente.
void UltrasonicManager::update() {
  unsigned long now = millis();
  if (now - _lastStepMs < 40) return;
  _lastStepMs = now;

  if (_measuring) {
    _lastCm[_step] = filterCm(_filters[_step], collectCm(_step));
    _step = (_step + 1) % SENSOR_COUNT;
  }

  noInterrupts();
  s_echoDone[_step]       = false;
  s_echoDurationUs[_step] = 0;
  interrupts();

  triggerPulse();
  _measuring = true;
}

void UltrasonicManager::printStatus() {
  Serial.print("ULTRASONICOS");

  for (int i = 0; i < SENSOR_COUNT; i++) {
    Serial.print(",");
    if (_lastCm[i] < 0) {
      Serial.print("-1");
    } else {
      Serial.print(_lastCm[i], 1);
    }
  }

  Serial.println();
}
