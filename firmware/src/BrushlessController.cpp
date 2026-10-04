#include "BrushlessController.h"
#include "pinmap.h"

static constexpr int      BRUSHLESS_RAMP_STEP      = 1;
static constexpr uint32_t BRUSHLESS_RAMP_PERIOD_MS = 50;
static constexpr int      PWM_MAX                  = 255;

void BrushlessController::begin() {
  ledcSetup(BRUSHLESS_VR_PWM_CH, BRUSHLESS_PWM_FREQ, BRUSHLESS_PWM_RES);
  ledcAttachPin(BRUSHLESS_VR_PIN, BRUSHLESS_VR_PWM_CH);
  ledcWrite(BRUSHLESS_VR_PWM_CH, 0);
}

void BrushlessController::on() {
  int target = constrain(BRUSHLESS_RUN_PERCENT, 0, BRUSHLESS_TEST_MAX_PERCENT);
  _enabled       = true;
  _targetPercent = target;
}

void BrushlessController::off() {
  // _enabled se apaga cuando la rampa llega a 0 (en update)
  _targetPercent = 0;
}

void BrushlessController::forceOff() {
  _targetPercent  = 0;
  _currentPercent = 0;
  _enabled        = false;
  ledcWrite(BRUSHLESS_VR_PWM_CH, 0);
}

bool BrushlessController::isEnabled() const {
  return _enabled;
}

int BrushlessController::getState() const {
  return _enabled ? 1 : 0;
}

void BrushlessController::writePwm(int percent) {
  percent = constrain(percent, 0, 100);

  if (percent > BRUSHLESS_TEST_MAX_PERCENT) {
    percent = BRUSHLESS_TEST_MAX_PERCENT;
  }

  if (!_enabled || percent <= 0) {
    ledcWrite(BRUSHLESS_VR_PWM_CH, 0);
    return;
  }

  int pwm = map(percent, 0, 100, 0, PWM_MAX);
  ledcWrite(BRUSHLESS_VR_PWM_CH, pwm);
}

void BrushlessController::update() {
  if (millis() - _lastRampMs < BRUSHLESS_RAMP_PERIOD_MS) return;
  _lastRampMs = millis();

  if (_currentPercent < _targetPercent) {
    _currentPercent += BRUSHLESS_RAMP_STEP;
    if (_currentPercent > _targetPercent) _currentPercent = _targetPercent;
  }
  else if (_currentPercent > _targetPercent) {
    _currentPercent -= BRUSHLESS_RAMP_STEP;
    if (_currentPercent < _targetPercent) _currentPercent = _targetPercent;
  }

  if (_currentPercent == 0 && _targetPercent == 0) {
    ledcWrite(BRUSHLESS_VR_PWM_CH, 0);
    _enabled = false;
    return;
  }

  writePwm(_currentPercent);
}
