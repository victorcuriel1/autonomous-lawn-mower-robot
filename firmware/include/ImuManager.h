#pragma once
#include <Arduino.h>
#include <Preferences.h>

class ImuManager {
public:
  bool begin();          // retorna false si MPU6050 no responde
  void update();
  void printStatus();
  void printAnglesStatus();
  bool calibrate(uint16_t samples = 1000);
  void resetYaw();
  bool isCalibrated() const { return _calibrated; }

private:
  bool writeRegister(uint8_t reg, uint8_t value);
  bool readRaw(int16_t &ax, int16_t &ay, int16_t &az,
               int16_t &gx, int16_t &gy, int16_t &gz);
  bool readValues(float &ax, float &ay, float &az,
                  float &gx, float &gy, float &gz);
  void loadCalibration();
  void saveCalibration();
  void applyCalibration(float &ax, float &ay, float &az,
                        float &gx, float &gy, float &gz);

  bool _ready = false;
  bool _calibrated = false;

  float _accelOffsetX = 0.0f;
  float _accelOffsetY = 0.0f;
  float _accelOffsetZ = 0.0f;
  float _gyroOffsetX = 0.0f;
  float _gyroOffsetY = 0.0f;
  float _gyroOffsetZ = 0.0f;

  float _ax = 0.0f;
  float _ay = 0.0f;
  float _az = 0.0f;
  float _gx = 0.0f;
  float _gy = 0.0f;
  float _gz = 0.0f;

  float _roll = 0.0f;
  float _pitch = 0.0f;
  float _yaw = 0.0f;

  unsigned long _lastUpdateMicros = 0;
};
