#include "DisplayController.h"
#include <Wire.h>

DisplayController::DisplayController()
  : _display(DISPLAY_WIDTH, DISPLAY_HEIGHT, &Wire, -1, I2C_CLOCK_HZ, I2C_CLOCK_HZ) {
}

// Wire.begin() ya fue llamado en main.cpp
bool DisplayController::begin() {
  Wire.setClock(I2C_CLOCK_HZ);
  delay(100);

  bool ok = _display.begin(SSD1306_SWITCHCAPVCC, DISPLAY_I2C_ADDR);

  if (!ok) {
    _ready = false;
    return false;
  }

  _ready = true;
  _mode  = "--";

  draw();
  return true;
}

void DisplayController::draw() {
  if (!_ready) return;

  _display.clearDisplay();
  _display.setTextColor(SSD1306_WHITE);

  _display.setTextSize(1);
  int16_t xLabel = (DISPLAY_WIDTH - 18 * 6) / 2;  // "Modo de operacion:" = 18 caracteres
  _display.setCursor(xLabel, 18);
  _display.print("Modo de operacion:");

  _display.setTextSize(2);
  int16_t xMode = (DISPLAY_WIDTH - (int16_t)_mode.length() * 12) / 2;
  if (xMode < 0) xMode = 0;
  _display.setCursor(xMode, 34);
  _display.print(_mode);

  _display.display();
}

void DisplayController::clear() {
  if (!_ready) return;
  _display.clearDisplay();
  _display.display();
}

void DisplayController::setText(const String& raw) {
  String text = raw;
  text.trim();

  if (text.length() == 0 || text.equalsIgnoreCase("OFF")) {
    _mode = "--";
    clear();
    return;
  }

  _mode = text;
  draw();
}

String DisplayController::getText() const {
  return _mode;
}

void DisplayController::printStatus() const {
  Serial.print("DISPLAY,");
  Serial.println(_mode);
}
