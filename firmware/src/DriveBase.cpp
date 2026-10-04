#include "DriveBase.h"
#include "pinmap.h"
#include <math.h>

// Constantes del PID de velocidad
static constexpr float KP                  = 2.5f;
static constexpr float KI                  = 0.4f;
static constexpr float KD                  = 0.02f;
static constexpr float INTEGRAL_LIMIT      = 220.0f;
static constexpr float ALPHA_D             = 0.25f;
static constexpr float ALPHA_PWM           = 0.15f;
static constexpr float ALPHA_RPM           = 0.4f;
static constexpr int   PWM_STATIC          = 28;
static constexpr float PWM_STATIC_THRESHOLD = 5.0f;
static constexpr int   PWM_MAX             = 255;
static constexpr float RPM_DEADBAND        = 2.0f;
static constexpr uint32_t MOTOR_CMD_TIMEOUT_MS = 500;

static volatile long g_leftEncCount  = 0;
static volatile long g_rightEncCount = 0;

static int s_leftEncSign  = 1;
static int s_rightEncSign = -1;

// ISRs de encoder en cuadratura

void IRAM_ATTR DriveBase::isrLeftA() {
  bool a = digitalRead(LEFT_ENC_A), b = digitalRead(LEFT_ENC_B);
  g_leftEncCount += (a == b) ? s_leftEncSign : -s_leftEncSign;
}

void IRAM_ATTR DriveBase::isrLeftB() {
  bool a = digitalRead(LEFT_ENC_A), b = digitalRead(LEFT_ENC_B);
  g_leftEncCount += (a != b) ? s_leftEncSign : -s_leftEncSign;
}

void IRAM_ATTR DriveBase::isrRightA() {
  bool a = digitalRead(RIGHT_ENC_A), b = digitalRead(RIGHT_ENC_B);
  g_rightEncCount += (a == b) ? s_rightEncSign : -s_rightEncSign;
}

void IRAM_ATTR DriveBase::isrRightB() {
  bool a = digitalRead(RIGHT_ENC_A), b = digitalRead(RIGHT_ENC_B);
  g_rightEncCount += (a != b) ? s_rightEncSign : -s_rightEncSign;
}

void DriveBase::begin() {
  s_leftEncSign  = INVERT_LEFT_MOTOR  ? -1 : 1;
  s_rightEncSign = INVERT_RIGHT_MOTOR ? -1 : 1;

  pinMode(LEFT_DIR_PIN,  OUTPUT);
  pinMode(RIGHT_DIR_PIN, OUTPUT);
  digitalWrite(LEFT_DIR_PIN, LOW);
  digitalWrite(RIGHT_DIR_PIN, LOW);

  ledcSetup(LEFT_PWM_CH,  PWM_FREQ, PWM_RES);
  ledcAttachPin(LEFT_PWM_PIN,  LEFT_PWM_CH);
  ledcWrite(LEFT_PWM_CH, 0);

  ledcSetup(RIGHT_PWM_CH, PWM_FREQ, PWM_RES);
  ledcAttachPin(RIGHT_PWM_PIN, RIGHT_PWM_CH);
  ledcWrite(RIGHT_PWM_CH, 0);

  pinMode(LEFT_ENC_A,  INPUT);
  pinMode(LEFT_ENC_B,  INPUT);
  pinMode(RIGHT_ENC_A, INPUT);
  pinMode(RIGHT_ENC_B, INPUT);

  attachInterrupt(LEFT_ENC_A,  isrLeftA,  CHANGE);
  attachInterrupt(LEFT_ENC_B,  isrLeftB,  CHANGE);
  attachInterrupt(RIGHT_ENC_A, isrRightA, CHANGE);
  attachInterrupt(RIGHT_ENC_B, isrRightB, CHANGE);

  _leftPID.t_prev_us = _rightPID.t_prev_us = micros();
  stop();
}

void DriveBase::update() {
  if (!updateRPM()) return;

  if (_lastTargetMs != 0 && (millis() - _lastTargetMs > MOTOR_CMD_TIMEOUT_MS)) {
    stop();
    return;
  }

  if (fabs(_leftRefRPM) < RPM_DEADBAND && fabs(_rightRefRPM) < RPM_DEADBAND) {
    stop();
    return;
  }

  float leftU  = runPID(_leftPID,  _leftRefRPM,  _leftRPMFiltered);
  float rightU = runPID(_rightPID, _rightRefRPM, _rightRPMFiltered);

  setMotorPWM(LEFT_DIR_PIN,  LEFT_PWM_CH,  leftU,  _leftPWMFiltered,  INVERT_LEFT_MOTOR);
  setMotorPWM(RIGHT_DIR_PIN, RIGHT_PWM_CH, rightU, _rightPWMFiltered, INVERT_RIGHT_MOTOR);
}

void DriveBase::setTargetRPM(float leftRPM, float rightRPM) {
  _leftRefRPM  = leftRPM;
  _rightRefRPM = rightRPM;
  _lastTargetMs = millis();

  if (fabs(_leftRefRPM) < RPM_DEADBAND && fabs(_rightRefRPM) < RPM_DEADBAND) {
    stop();
  }
}

void DriveBase::stop() {
  _leftRefRPM  = 0.0f;
  _rightRefRPM = 0.0f;
  _lastTargetMs = 0;

  ledcWrite(LEFT_PWM_CH,  0);
  ledcWrite(RIGHT_PWM_CH, 0);
  digitalWrite(LEFT_DIR_PIN, LOW);
  digitalWrite(RIGHT_DIR_PIN, LOW);

  _leftPWMFiltered  = 0.0f;
  _rightPWMFiltered = 0.0f;

  _leftPID.integral  = 0.0f;
  _rightPID.integral = 0.0f;
  _leftPID.e_prev    = 0.0f;
  _rightPID.e_prev   = 0.0f;
}

void DriveBase::resetEncoders() {
  noInterrupts();
  g_leftEncCount  = 0;
  g_rightEncCount = 0;
  interrupts();

  _leftRPMFiltered  = 0.0f;
  _rightRPMFiltered = 0.0f;
}

void DriveBase::printStatus() {
  long leftTicks, rightTicks;

  noInterrupts();
  leftTicks  = g_leftEncCount;
  rightTicks = g_rightEncCount;
  interrupts();

  Serial.print("MOTORES,");
  Serial.print(millis());
  Serial.print(",");
  Serial.print(_leftRPMFiltered, 2);
  Serial.print(",");
  Serial.print(_rightRPMFiltered, 2);
  Serial.print(",");
  Serial.print(leftTicks);
  Serial.print(",");
  Serial.println(rightTicks);
}

bool DriveBase::updateRPM() {
  static uint32_t prevRPMus    = 0;
  static long     leftEncPrev  = 0;
  static long     rightEncPrev = 0;

  if (prevRPMus == 0) {
    prevRPMus = micros();
    return false;
  }

  uint32_t nowUs = micros();
  float    dt    = (nowUs - prevRPMus) * 1e-6f;

  if (dt < 0.01f) return false;

  prevRPMus = nowUs;

  long leftNow, rightNow;

  noInterrupts();
  leftNow  = g_leftEncCount;
  rightNow = g_rightEncCount;
  interrupts();

  float leftRPM  = ((float)(leftNow  - leftEncPrev)  / CPR) * (60.0f / dt);
  float rightRPM = ((float)(rightNow - rightEncPrev) / CPR) * (60.0f / dt);

  leftEncPrev  = leftNow;
  rightEncPrev = rightNow;

  _leftRPMFiltered  = ALPHA_RPM * leftRPM  + (1.0f - ALPHA_RPM) * _leftRPMFiltered;
  _rightRPMFiltered = ALPHA_RPM * rightRPM + (1.0f - ALPHA_RPM) * _rightRPMFiltered;

  return true;
}

float DriveBase::runPID(PIDState &pid, float refRPM, float measRPM) {
  uint32_t nowUs = micros();
  float    Ts    = (nowUs - pid.t_prev_us) * 1e-6f;

  pid.t_prev_us = nowUs;

  if (Ts <= 0.0f) Ts = 0.001f;

  // Si el PID estuvo un rato sin correr, el primer Ts puede ser enorme
  // y cargar la integral de golpe; se acota
  if (Ts > 0.05f) Ts = 0.05f;

  float e = refRPM - measRPM;

  if (fabs(refRPM) < RPM_DEADBAND && fabs(measRPM) < RPM_DEADBAND) {
    pid.integral = 0;
    pid.e_prev   = e;
    return 0;
  }

  pid.integral += KI * Ts * e;
  pid.integral  = constrain(pid.integral, -INTEGRAL_LIMIT, INTEGRAL_LIMIT);

  float d_raw = (e - pid.e_prev) / Ts;
  pid.d_filt  = ALPHA_D * d_raw + (1.0f - ALPHA_D) * pid.d_filt;

  pid.e_prev = e;

  return (KP * e) + pid.integral + (KD * pid.d_filt);
}

void DriveBase::setMotorPWM(int dirPin, int pwmCh, float controlSignal,
                             float &pwmFiltered, bool inverted) {
  if (fabs(controlSignal) < 1e-3f) {
    pwmFiltered = 0;
    ledcWrite(pwmCh, 0);
    return;
  }

  float mag = fabs(controlSignal);

  // Compensacion de friccion estatica
  if (mag > PWM_STATIC_THRESHOLD) {
    mag += PWM_STATIC;
  }

  mag = constrain(mag, 0, PWM_MAX);

  pwmFiltered = ALPHA_PWM * mag + (1.0f - ALPHA_PWM) * pwmFiltered;

  bool dir = (controlSignal >= 0) ? !inverted : inverted;

  digitalWrite(dirPin, dir ? HIGH : LOW);
  ledcWrite(pwmCh, (int)pwmFiltered);
}
