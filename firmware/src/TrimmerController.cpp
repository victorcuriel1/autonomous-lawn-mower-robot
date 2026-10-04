#include "TrimmerController.h"
#include "pinmap.h"

static constexpr int      RAMP_STEP      = 3;
static constexpr uint32_t RAMP_PERIOD_MS = 20;
static constexpr int      PWM_MAX        = 255;

void TrimmerController::begin() {
  pinMode(TRIMMER_DIR_PIN, OUTPUT);
  digitalWrite(TRIMMER_DIR_PIN, LOW);

  ledcSetup(TRIMMER_PWM_CH, PWM_FREQ, PWM_RES);
  ledcAttachPin(TRIMMER_PWM_PIN, TRIMMER_PWM_CH);
  ledcWrite(TRIMMER_PWM_CH, 0);
}

void TrimmerController::on() {
  _enabled       = true;
  _targetPercent = TRIMMER_RUN_PERCENT;
}

void TrimmerController::off() {
  // _enabled se apaga cuando la rampa llega a 0 (en update)
  _targetPercent = 0;
}

void TrimmerController::forceOff() {
  _targetPercent  = 0;
  _currentPercent = 0;
  _enabled        = false;
  ledcWrite(TRIMMER_PWM_CH, 0);
}

bool TrimmerController::isEnabled() const {
  return _enabled;
}

int TrimmerController::getState() const {
  return _enabled ? 1 : 0;
}

void TrimmerController::applyOutput(int percent) {
  percent = constrain(percent, -100, 100);

  if (!_enabled || percent == 0) {
    ledcWrite(TRIMMER_PWM_CH, 0);
    return;
  }

  bool direction = (percent >= 0) ? !INVERT_TRIMMER_MOTOR : INVERT_TRIMMER_MOTOR;
  digitalWrite(TRIMMER_DIR_PIN, direction ? HIGH : LOW);

  int magnitude = abs(percent);
  int pwm       = map(magnitude, 0, 100, 0, PWM_MAX);
  ledcWrite(TRIMMER_PWM_CH, pwm);
}

void TrimmerController::update() {
  if (millis() - _lastRampMs < RAMP_PERIOD_MS) return;
  _lastRampMs = millis();

  if (_currentPercent < _targetPercent) {
    _currentPercent += RAMP_STEP;
    if (_currentPercent > _targetPercent) _currentPercent = _targetPercent;
  }
  else if (_currentPercent > _targetPercent) {
    _currentPercent -= RAMP_STEP;
    if (_currentPercent < _targetPercent) _currentPercent = _targetPercent;
  }

  if (_currentPercent == 0 && _targetPercent == 0) {
    ledcWrite(TRIMMER_PWM_CH, 0);
    _enabled = false;
    return;
  }

  applyOutput(_currentPercent);
}
