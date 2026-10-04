#include <Arduino.h>
#include <Wire.h>

#include "pinmap.h"
#include "DriveBase.h"
#include "TrimmerController.h"
#include "BrushlessController.h"
#include "UltrasonicManager.h"
#include "BuzzerController.h"
#include "DisplayController.h"
#include "ImuManager.h"
#include "BatteryManager.h"
#include "SafetyManager.h"
#include "SerialProtocol.h"
#include "CutSequencer.h"

DriveBase          driveBase;
TrimmerController  trimmer;
BrushlessController brushless;
UltrasonicManager  ultrasonics;
BuzzerController   buzzer;
DisplayController  display;
ImuManager         imu;
BatteryManager     battery;
SafetyManager      safety;
CutSequencer       cutSequencer;

static constexpr uint32_t STARTUP_INHIBIT_MS = 2000;
static uint32_t startupInhibitStartMs = 0;
static bool startupInhibit = true;

bool isStartupInhibitActive() {
  return startupInhibit;
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(500);

  // Bus I2C compartido por la IMU y el display
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(I2C_CLOCK_HZ);

  driveBase.begin();
  driveBase.stop();
  driveBase.resetEncoders();
  startupInhibitStartMs = millis();
  startupInhibit = true;
  trimmer.begin();
  brushless.begin();
  ultrasonics.begin();
  buzzer.begin();

  bool displayOk = display.begin();
  bool imuOk     = imu.begin();
  battery.begin();

  cutSequencer.begin(&trimmer, &brushless);
  serialProtocolBegin();

  if (displayOk) {
    Serial.println("ACK DISPLAY_OK");
  } else {
    Serial.println("ERR DISPLAY_NOT_FOUND");
  }

  if (imuOk) {
    Serial.println("ACK IMU_OK");
  } else {
    Serial.println("ERR IMU_NOT_FOUND");
  }
}

void loop() {
  imu.update();
  ultrasonics.update();
  battery.update();
  buzzer.update();

  if (startupInhibit && (millis() - startupInhibitStartMs >= STARTUP_INHIBIT_MS)) {
    startupInhibit = false;
    driveBase.stop();
    driveBase.resetEncoders();
  }

  // PID de ruedas solo si no hay emergencia ni bloqueo de arranque
  if (!startupInhibit && !safety.isEstop()) {
    driveBase.update();
  } else {
    driveBase.stop();
  }

  trimmer.update();
  brushless.update();
  cutSequencer.update();

  // Los finales de carrera los lee la Raspberry Pi y la
  // emergencia llega desde ROS2 con CMD_ESTOP
  serialProtocolUpdate();
}
