#include "SerialProtocol.h"
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
#include "CutSequencer.h"

// Instancias definidas en main.cpp
extern DriveBase         driveBase;
extern TrimmerController trimmer;
extern BrushlessController brushless;
extern UltrasonicManager   ultrasonics;
extern BuzzerController    buzzer;
extern DisplayController   display;
extern ImuManager          imu;
extern BatteryManager      battery;
extern SafetyManager       safety;
extern CutSequencer        cutSequencer;
extern bool isStartupInhibitActive();

static String s_buffer = "";

// Estado solicitado de cada motor de corte
static bool s_trimmerRequested   = false;
static bool s_brushlessRequested = false;

static void normalizeCommand(String &line) {
  line.trim();

  while (line.indexOf("  ") >= 0) {
    line.replace("  ", " ");
  }
}

// Apaga todo y activa el flag de emergencia
static void activateEstop() {
  safety.activateEstop();
  driveBase.stop();
  cutSequencer.cancelAll();
  trimmer.forceOff();
  brushless.forceOff();
}

static void processCommand(String line) {
  normalizeCommand(line);

  String upper = line;
  upper.toUpperCase();

  if (upper == "PING") {
    Serial.println("PONG");
    return;
  }

  if (upper == "STATUS") {
    ultrasonics.printStatus();
    driveBase.printStatus();

    Serial.print("TRIMMER,");
    Serial.println(trimmer.getState());
    Serial.print("BRUSHLESS,");
    Serial.println(brushless.getState());

    buzzer.printStatus();
    display.printStatus();
    imu.printStatus();
    imu.printAnglesStatus();
    battery.printStatus();
    safety.printStatus();
    return;
  }

  // Calibrar con el robot quieto, plano y apoyado
  if (upper == "IMU_CALIBRATE") {
    if (imu.calibrate()) {
      Serial.println("ACK IMU_CALIBRATE");
      imu.printStatus();
      imu.printAnglesStatus();
    } else {
      Serial.println("ERR IMU_CALIBRATE");
    }
    return;
  }

  if (upper == "IMU_RESET_YAW") {
    imu.resetYaw();
    Serial.println("ACK IMU_RESET_YAW");
    imu.printStatus();
    imu.printAnglesStatus();
    return;
  }

  if (upper == "RESET_ENCODERS") {
    driveBase.resetEncoders();
    Serial.println("ACK RESET_ENCODERS");
    return;
  }

  if (upper == "CMD_ESTOP") {
    activateEstop();
    Serial.println("ACK CMD_ESTOP");
    return;
  }

  // El chequeo de estado normal antes de resetear es
  // responsabilidad de ROS2, que lee los finales de carrera
  if (upper == "CMD_RESET_ESTOP") {
    safety.resetEstop();
    Serial.println("ACK CMD_RESET_ESTOP");
    return;
  }

  if (upper.startsWith("CMD_DISPLAY,")) {
    String text = line.substring(String("CMD_DISPLAY,").length());
    display.setText(text);
    Serial.print("ACK CMD_DISPLAY,");
    Serial.println(display.getText());
    return;
  }

  if (upper.startsWith("CMD_BUZZER,")) {
    String text = line.substring(String("CMD_BUZZER,").length());
    buzzer.play(text);
    Serial.print("ACK CMD_BUZZER,");
    Serial.println(text);
    return;
  }

  // Comandos de movimiento bloqueados en emergencia o arranque
  if (upper.startsWith("CMD_MOTORES,") || upper.startsWith("CMD_TRIMMER,") || upper.startsWith("CMD_BRUSHLESS,")) {
    if (isStartupInhibitActive()) {
      Serial.println("ERR STARTUP_INHIBIT");
      return;
    }

    if (safety.isEstop()) {
      Serial.println("ERR ESTOP_ACTIVE");
      return;
    }
  }

  // CMD_MOTORES,left_rpm,right_rpm
  if (upper.startsWith("CMD_MOTORES,")) {
    String values = line.substring(String("CMD_MOTORES,").length());
    values.trim();

    int comma = values.indexOf(',');
    if (comma < 0) {
      Serial.println("ERR CMD_MOTORES_FORMAT");
      return;
    }

    float leftRPM  = values.substring(0, comma).toFloat();
    float rightRPM = values.substring(comma + 1).toFloat();

    driveBase.setTargetRPM(leftRPM, rightRPM);

    if (leftRPM != 0.0f || rightRPM != 0.0f) {
      cutSequencer.notifyWheelsStarted();
    }

    Serial.print("ACK CMD_MOTORES,");
    Serial.print(leftRPM);
    Serial.print(",");
    Serial.println(rightRPM);
    return;
  }

  // CMD_TRIMMER,0/1
  if (upper.startsWith("CMD_TRIMMER,")) {
    String values = line.substring(String("CMD_TRIMMER,").length());
    values.trim();
    s_trimmerRequested = (values.toInt() == 1);
    cutSequencer.request(s_trimmerRequested, s_brushlessRequested);
    Serial.print("ACK CMD_TRIMMER,");
    Serial.println(s_trimmerRequested ? 1 : 0);
    return;
  }

  // CMD_BRUSHLESS,0/1
  if (upper.startsWith("CMD_BRUSHLESS,")) {
    String values = line.substring(String("CMD_BRUSHLESS,").length());
    values.trim();
    s_brushlessRequested = (values.toInt() == 1);
    cutSequencer.request(s_trimmerRequested, s_brushlessRequested);
    Serial.print("ACK CMD_BRUSHLESS,");
    Serial.println(s_brushlessRequested ? 1 : 0);
    return;
  }

  Serial.print("ERR UNKNOWN_CMD ");
  Serial.println(line);
}

void serialProtocolBegin() {
  Serial.println("ACK FIRMWARE_READY");
  Serial.println("CMD_AVAILABLE PING|STATUS|IMU_CALIBRATE|IMU_RESET_YAW|RESET_ENCODERS|CMD_MOTORES,left_rpm,right_rpm|CMD_TRIMMER,0/1|CMD_BRUSHLESS,0/1|CMD_DISPLAY,text_modo|CMD_BUZZER,text|CMD_ESTOP|CMD_RESET_ESTOP");
}

void serialProtocolUpdate() {
  while (Serial.available()) {
    char c = Serial.read();

    if (c == '\n') {
      processCommand(s_buffer);
      s_buffer = "";
    } else if (c != '\r') {
      s_buffer += c;
    }
  }
}
