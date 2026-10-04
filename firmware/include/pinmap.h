#pragma once
#include <Arduino.h>

// Configuracion general

constexpr uint32_t SERIAL_BAUD = 115200;

// PWM de los drivers MD13S (ruedas y trimmer)
constexpr int PWM_FREQ = 20000;   // 20 kHz
constexpr int PWM_RES  = 8;       // 0 a 255

// Rueda izquierda
constexpr int LEFT_DIR_PIN = 26;
constexpr int LEFT_PWM_PIN = 25;
constexpr int LEFT_ENC_A   = 32;
constexpr int LEFT_ENC_B   = 39;
constexpr int LEFT_PWM_CH  = 0;
constexpr bool INVERT_LEFT_MOTOR = true;

// Rueda derecha
constexpr int RIGHT_DIR_PIN = 18;
constexpr int RIGHT_PWM_PIN = 19;
constexpr int RIGHT_ENC_A   = 5;
constexpr int RIGHT_ENC_B   = 23;
constexpr int RIGHT_PWM_CH  = 1;
constexpr bool INVERT_RIGHT_MOTOR = false;

// Encoders: 11 PPR del motor, reduccion 1/72, cuadratura x4
constexpr float PPR_MOTOR  = 11.0f;
constexpr float GEAR_RATIO = 72.0f;
constexpr float CPR = PPR_MOTOR * GEAR_RATIO * 4.0f;

// Trimmer (motor DC con MD13S, sin encoder)
constexpr int TRIMMER_DIR_PIN = 14;
constexpr int TRIMMER_PWM_PIN = 27;
constexpr int TRIMMER_PWM_CH  = 2;
constexpr bool INVERT_TRIMMER_MOTOR = false;

constexpr int TRIMMER_RUN_PERCENT      = 40;  // velocidad fija de trabajo
constexpr int TRIMMER_TEST_MAX_PERCENT = 60;  // limite de seguridad

// Brushless: el ESP32 manda PWM al pin VR del driver
constexpr int BRUSHLESS_VR_PIN    = 13;
constexpr int BRUSHLESS_VR_PWM_CH = 3;

constexpr int BRUSHLESS_PWM_FREQ = 1000;
constexpr int BRUSHLESS_PWM_RES  = 8;

constexpr int BRUSHLESS_RUN_PERCENT      = 60;  // velocidad fija de trabajo
constexpr int BRUSHLESS_TEST_MAX_PERCENT = 80;  // limite de seguridad

// Ultrasonicos HC-SR04: los sensores comparten el TRIG y cada
// uno tiene su ECHO (con divisor de tension, el ECHO sale a 5V).
// Orden: left, center, right, diag_right, diag_left, back_right.
// GPIO2 y GPIO12 son strapping pins: no ponerles pull-up externo
// porque el ESP32 no arranca.
constexpr int US_TRIG_PIN = 4;

constexpr int US_LEFT_ECHO_PIN       = 2;
constexpr int US_CENTER_ECHO_PIN     = 34;
constexpr int US_RIGHT_ECHO_PIN      = 35;
constexpr int US_DIAG_RIGHT_ECHO_PIN = 17;
constexpr int US_DIAG_LEFT_ECHO_PIN  = 16;
constexpr int US_BACK_RIGHT_ECHO_PIN = 12;

// Duracion maxima valida del pulso ECHO (~2 m); ecos mas largos
// se descartan como fuera de rango (-1)
constexpr uint32_t US_TIMEOUT_US = 12000;

// Buzzer pasivo
constexpr int BUZZER_PIN     = 15;
constexpr int BUZZER_PWM_CH  = 4;
constexpr int BUZZER_PWM_RES = 8;
constexpr int BUZZER_DUTY    = 128;

// Bus I2C compartido por IMU y display.
// A 100 kHz por el ruido electrico del driver brushless.
constexpr int I2C_SDA_PIN = 21;
constexpr int I2C_SCL_PIN = 22;
constexpr uint32_t I2C_CLOCK_HZ = 100000;

// IMU MPU6050 (AD0 a GND -> 0x68)
constexpr uint8_t MPU6050_ADDR = 0x68;

// Display OLED SSD1309 I2C
constexpr int DISPLAY_WIDTH  = 128;
constexpr int DISPLAY_HEIGHT = 64;
constexpr uint8_t DISPLAY_I2C_ADDR = 0x3C;

// Sensor de bateria: modulo divisor de tension (VCC < 25V),
// divide aprox. por 5. battery_v = raw * 3.3 / 4095 * 5
constexpr int PIN_BATTERY_SENSOR = 33;

constexpr float BATTERY_VREF    = 3.3f;
constexpr float BATTERY_CAL     = 1.0f;   // calibracion: real/medido
constexpr float BATTERY_DIVISOR = 5.0f;
