#include "BuzzerController.h"
#include "pinmap.h"

// Patrones de tonos: {frecuencia_hz, duracion_ms}, frecuencia 0 = silencio

static ToneStep toneListo[] = {
  {523,  90},
  {0,    25},
  {659,  90},
  {0,    25},
  {784,  90},
  {0,    25},
  {1047, 380}
};

static ToneStep toneModoManual[] = {
  {1400,  80},
  {0,     50},
  {1400,  80},
  {0,     80},
  {900,  220}
};

static ToneStep toneModoAleatorio[] = {
  {900,   70},
  {1600,  60},
  {600,   70},
  {1400,  60},
  {800,   70},
  {1700, 130}
};

static ToneStep toneModoParalelo[] = {
  {1050, 110},
  {0,     45},
  {1050, 110},
  {0,    130},
  {1050, 110},
  {0,     45},
  {1050, 110}
};

static ToneStep toneModoPerimetral[] = {
  {523,   80},
  {659,   80},
  {784,   80},
  {1047,  80},
  {1319,  80},
  {1047,  80},
  {784,   80},
  {659,   80},
  {523,  150}
};

static ToneStep toneBateriaLow[] = {
  {550, 90},
  {0,    70},
  {550, 90},
  {0,    70},
  {550, 90},
  {0,   350},

  {550, 90},
  {0,    70},
  {550, 90},
  {0,    70},
  {550, 90},
  {0,   350},

  {550, 90},
  {0,    70},
  {550, 90},
  {0,    70},
  {550, 90},
  {0,   350},

};

static ToneStep toneEstop[] = {
  {1800,  55},
  {0,     30},
  {1800,  55},
  {0,     30},
  {1800,  55},
  {0,     30},
  {1800,  55},
  {0,     30},
  {1800,  55},
  {0,     30},
  {1800,  55}
};

static ToneStep toneStop[] = {
  {1200, 170},
  {800,  170},
  {1200, 170},
  {800,  170},
  {1200, 170}
};

static ToneStep toneStartCorte[] = {
  {350,  150},
  {550,  120},
  {850,  100},
  {1200, 100},
  {1600, 380}
};

static ToneStep toneDespegue[] = {
  {1500, 250},
  {700,  400},
  {1500, 250},
  {700,  400},
  {1500, 250},
  {700,  400},
  {1500, 250}
};

void BuzzerController::begin() {
  ledcSetup(BUZZER_PWM_CH, 2000, BUZZER_PWM_RES);
  ledcAttachPin(BUZZER_PIN, BUZZER_PWM_CH);
  buzzerOff();
}

void BuzzerController::buzzerOff() {
  ledcWriteTone(BUZZER_PWM_CH, 0);
  ledcWrite(BUZZER_PWM_CH, 0);
}

void BuzzerController::buzzerTone(int frequency) {
  if (frequency <= 0) {
    buzzerOff();
    return;
  }

  ledcWriteTone(BUZZER_PWM_CH, frequency);
  ledcWrite(BUZZER_PWM_CH, BUZZER_DUTY);
}

void BuzzerController::startPattern(ToneStep* pattern, int length, const String& text) {
  _currentPattern       = pattern;
  _currentPatternLength = length;
  _currentStepIndex     = 0;
  _playing              = true;
  _stepStartMs          = millis();
  _buzzerText           = text;

  buzzerTone(_currentPattern[0].frequency);
}

void BuzzerController::stopPattern() {
  _playing              = false;
  _currentPattern       = nullptr;
  _currentPatternLength = 0;
  _currentStepIndex     = 0;
  _buzzerText           = "OFF";

  buzzerOff();
}

void BuzzerController::update() {
  if (!_playing || _currentPattern == nullptr) return;

  uint32_t nowMs   = millis();
  int      duration = _currentPattern[_currentStepIndex].durationMs;

  if ((nowMs - _stepStartMs) < (uint32_t)duration) return;

  _currentStepIndex++;

  if (_currentStepIndex >= _currentPatternLength) {
    stopPattern();
    return;
  }

  _stepStartMs = nowMs;
  buzzerTone(_currentPattern[_currentStepIndex].frequency);
}

void BuzzerController::play(String text) {
  text.trim();
  text.toUpperCase();

  if (text == "LISTO") {
    startPattern(toneListo, sizeof(toneListo) / sizeof(toneListo[0]), "LISTO");
  }
  else if (text == "MODOMANUAL") {
    startPattern(toneModoManual, sizeof(toneModoManual) / sizeof(toneModoManual[0]), "MODOMANUAL");
  }
  else if (text == "MODOALEATORIO") {
    startPattern(toneModoAleatorio, sizeof(toneModoAleatorio) / sizeof(toneModoAleatorio[0]), "MODOALEATORIO");
  }
  else if (text == "MODOPARALELO") {
    startPattern(toneModoParalelo, sizeof(toneModoParalelo) / sizeof(toneModoParalelo[0]), "MODOPARALELO");
  }
  else if (text == "MODOPERIMETRAL") {
    startPattern(toneModoPerimetral, sizeof(toneModoPerimetral) / sizeof(toneModoPerimetral[0]), "MODOPERIMETRAL");
  }
  else if (text == "BATERIABAJA") {
    startPattern(toneBateriaLow, sizeof(toneBateriaLow) / sizeof(toneBateriaLow[0]), "BATERIABAJA");
  }
  else if (text == "ESTOP") {
    startPattern(toneEstop, sizeof(toneEstop) / sizeof(toneEstop[0]), "ESTOP");
  }
  else if (text == "STOP") {
    startPattern(toneStop, sizeof(toneStop) / sizeof(toneStop[0]), "STOP");
  }
  else if (text == "STARTCORTE") {
    startPattern(toneStartCorte, sizeof(toneStartCorte) / sizeof(toneStartCorte[0]), "STARTCORTE");
  }
  else if (text == "DESPEGUE") {
    startPattern(toneDespegue, sizeof(toneDespegue) / sizeof(toneDespegue[0]), "DESPEGUE");
  }
  else if (text == "OFF") {
    stopPattern();
  }
}

String BuzzerController::getBuzzerText() const {
  return _buzzerText;
}

void BuzzerController::printStatus() const {
  Serial.print("BUZZER,");
  Serial.println(_buzzerText);
}
