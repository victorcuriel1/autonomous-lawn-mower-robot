#pragma once
#include <Arduino.h>
#include <Adafruit_SSD1306.h>
#include "pinmap.h"

class DisplayController {
public:
  DisplayController();
  bool   begin();
  void   setText(const String& raw);
  String getText() const;
  void   printStatus() const;

private:
  void draw();
  void clear();

  Adafruit_SSD1306 _display;

  String _mode = "--";

  bool _ready = false;
};
