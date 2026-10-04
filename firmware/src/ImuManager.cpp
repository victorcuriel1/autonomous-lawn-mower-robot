#include "ImuManager.h"
#include "pinmap.h"
#include <Wire.h>
#include <math.h>

// Wire.begin() ya fue llamado en main.cpp
bool ImuManager::begin() {
  delay(100);

  // Despertar el MPU6050 (PWR_MGMT_1 = 0)
  if (!writeRegister(0x6B, 0x00)) {
    _ready = false;
    return false;
  }

  delay(100);

  writeRegister(0x1C, 0x00);  // acelerometro en ±2g
  writeRegister(0x1B, 0x00);  // giroscopio en ±250 °/s
  writeRegister(0x1A, 0x03);  // filtro digital

  loadCalibration();
  _ready = true;
  _lastUpdateMicros = micros();
  update();
  return true;
}

bool ImuManager::writeRegister(uint8_t reg, uint8_t value) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(reg);
  Wire.write(value);
  return Wire.endTransmission() == 0;
}

bool ImuManager::readRaw(int16_t &ax, int16_t &ay, int16_t &az,
                          int16_t &gx, int16_t &gy, int16_t &gz) {
  Wire.beginTransmission(MPU6050_ADDR);
  Wire.write(0x3B);  // primer registro del acelerometro

  if (Wire.endTransmission(false) != 0) return false;

  int bytesRead = Wire.requestFrom(MPU6050_ADDR, (uint8_t)14);

  if (bytesRead != 14) return false;

  ax = (Wire.read() << 8) | Wire.read();
  ay = (Wire.read() << 8) | Wire.read();
  az = (Wire.read() << 8) | Wire.read();

  // temperatura, no se usa
  Wire.read();
  Wire.read();

  gx = (Wire.read() << 8) | Wire.read();
  gy = (Wire.read() << 8) | Wire.read();
  gz = (Wire.read() << 8) | Wire.read();

  return true;
}

bool ImuManager::readValues(float &ax, float &ay, float &az,
                             float &gx, float &gy, float &gz) {
  int16_t rawAx, rawAy, rawAz, rawGx, rawGy, rawGz;

  if (!readRaw(rawAx, rawAy, rawAz, rawGx, rawGy, rawGz)) return false;

  // ±2g -> 16384 LSB/g, ±250 °/s -> 131 LSB/(°/s)
  ax = rawAx / 16384.0f;
  ay = rawAy / 16384.0f;
  az = rawAz / 16384.0f;

  gx = rawGx / 131.0f;
  gy = rawGy / 131.0f;
  gz = rawGz / 131.0f;

  return true;
}

// Calibracion persistente en NVS

void ImuManager::loadCalibration() {
  Preferences prefs;
  prefs.begin("imu", true);
  _accelOffsetX = prefs.getFloat("aox", 0.0f);
  _accelOffsetY = prefs.getFloat("aoy", 0.0f);
  _accelOffsetZ = prefs.getFloat("aoz", 0.0f);
  _gyroOffsetX = prefs.getFloat("gox", 0.0f);
  _gyroOffsetY = prefs.getFloat("goy", 0.0f);
  _gyroOffsetZ = prefs.getFloat("goz", 0.0f);
  _calibrated = prefs.getBool("cal", false);
  prefs.end();
}

void ImuManager::saveCalibration() {
  Preferences prefs;
  prefs.begin("imu", false);
  prefs.putFloat("aox", _accelOffsetX);
  prefs.putFloat("aoy", _accelOffsetY);
  prefs.putFloat("aoz", _accelOffsetZ);
  prefs.putFloat("gox", _gyroOffsetX);
  prefs.putFloat("goy", _gyroOffsetY);
  prefs.putFloat("goz", _gyroOffsetZ);
  prefs.putBool("cal", _calibrated);
  prefs.end();
}

void ImuManager::applyCalibration(float &ax, float &ay, float &az,
                                  float &gx, float &gy, float &gz) {
  ax -= _accelOffsetX;
  ay -= _accelOffsetY;
  az -= _accelOffsetZ;
  gx -= _gyroOffsetX;
  gy -= _gyroOffsetY;
  gz -= _gyroOffsetZ;
}

bool ImuManager::calibrate(uint16_t samples) {
  if (!_ready || samples == 0) return false;

  float sumAx = 0.0f, sumAy = 0.0f, sumAz = 0.0f;
  float sumGx = 0.0f, sumGy = 0.0f, sumGz = 0.0f;
  uint16_t validSamples = 0;

  for (uint16_t i = 0; i < samples; i++) {
    float ax, ay, az, gx, gy, gz;
    if (readValues(ax, ay, az, gx, gy, gz)) {
      sumAx += ax;
      sumAy += ay;
      sumAz += az;
      sumGx += gx;
      sumGy += gy;
      sumGz += gz;
      validSamples++;
    }
    delay(3);
  }

  if (validSamples == 0) return false;

  _accelOffsetX = sumAx / validSamples;
  _accelOffsetY = sumAy / validSamples;
  _accelOffsetZ = (sumAz / validSamples) - 1.0f;  // en reposo az = 1g
  _gyroOffsetX = sumGx / validSamples;
  _gyroOffsetY = sumGy / validSamples;
  _gyroOffsetZ = sumGz / validSamples;
  _calibrated = true;

  _roll = 0.0f;
  _pitch = 0.0f;
  _yaw = 0.0f;
  _lastUpdateMicros = micros();

  saveCalibration();
  update();
  return true;
}

void ImuManager::resetYaw() {
  _yaw = 0.0f;
  _lastUpdateMicros = micros();
}

void ImuManager::update() {
  if (!_ready) return;

  float ax, ay, az, gx, gy, gz;
  if (!readValues(ax, ay, az, gx, gy, gz)) return;

  applyCalibration(ax, ay, az, gx, gy, gz);

  unsigned long now = micros();
  float dt = 0.0f;
  if (_lastUpdateMicros != 0) {
    dt = (now - _lastUpdateMicros) / 1000000.0f;
  }
  _lastUpdateMicros = now;

  if (dt < 0.0f || dt > 0.5f) {
    dt = 0.0f;
  }

  _ax = ax;
  _ay = ay;
  _az = az;
  _gx = gx;
  _gy = gy;
  _gz = gz;

  float rollAcc = atan2f(ay, az) * RAD_TO_DEG;
  float pitchAcc = atan2f(-ax, sqrtf((ay * ay) + (az * az))) * RAD_TO_DEG;

  // En reposo la magnitud del acelerometro es ~1g; con vibracion
  // se aleja de 1g y en esos ciclos no se corrige con acelerometro
  float accelMag = sqrtf((ax * ax) + (ay * ay) + (az * az));
  bool accelValid = (accelMag > 0.85f) && (accelMag < 1.15f);

  if (dt == 0.0f) {
    if (accelValid) {
      _roll = rollAcc;
      _pitch = pitchAcc;
    }
    return;
  }

  // Filtro complementario: gyro a corto plazo, acelerometro a largo plazo
  if (accelValid) {
    _roll = 0.98f * (_roll + gx * dt) + 0.02f * rollAcc;
    _pitch = 0.98f * (_pitch + gy * dt) + 0.02f * pitchAcc;
  } else {
    _roll += gx * dt;
    _pitch += gy * dt;
  }
  _yaw += gz * dt;

  if (_yaw > 180.0f) _yaw -= 360.0f;
  if (_yaw < -180.0f) _yaw += 360.0f;
}

void ImuManager::printStatus() {
  Serial.print("IMU,");
  Serial.print(_ax, 3); Serial.print(",");
  Serial.print(_ay, 3); Serial.print(",");
  Serial.print(_az, 3); Serial.print(",");
  Serial.print(_gx, 3); Serial.print(",");
  Serial.print(_gy, 3); Serial.print(",");
  Serial.println(_gz, 3);
}

void ImuManager::printAnglesStatus() {
  Serial.print("IMU_ANGLES,");
  Serial.print(_roll, 2); Serial.print(",");
  Serial.print(_pitch, 2); Serial.print(",");
  Serial.print(_yaw, 2); Serial.print(",");
  Serial.println(_calibrated ? 1 : 0);
}
