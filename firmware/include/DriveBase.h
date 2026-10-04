#pragma once
#include <Arduino.h>

struct PIDState {
  float    e_prev    = 0.0f;
  float    integral  = 0.0f;
  float    d_filt    = 0.0f;
  uint32_t t_prev_us = 0;
};

class DriveBase {
public:
  void begin();
  void update();
  void setTargetRPM(float leftRPM, float rightRPM);
  void stop();
  void resetEncoders();
  void printStatus();

  // ISR handlers - deben ser static para poder usarse en attachInterrupt
  static void IRAM_ATTR isrLeftA();
  static void IRAM_ATTR isrLeftB();
  static void IRAM_ATTR isrRightA();
  static void IRAM_ATTR isrRightB();

private:
  bool  updateRPM();
  float runPID(PIDState &pid, float refRPM, float measRPM);
  void  setMotorPWM(int dirPin, int pwmCh, float controlSignal,
                    float &pwmFiltered, bool inverted);

  PIDState _leftPID, _rightPID;

  float _leftRefRPM       = 0.0f;
  float _rightRefRPM      = 0.0f;
  float _leftRPMFiltered  = 0.0f;
  float _rightRPMFiltered = 0.0f;
  float _leftPWMFiltered  = 0.0f;
  float _rightPWMFiltered = 0.0f;
  uint32_t _lastTargetMs  = 0;
};
