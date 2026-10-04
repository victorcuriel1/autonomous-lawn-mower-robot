#pragma once
#include <Arduino.h>

struct ToneStep {
  int frequency;
  int durationMs;
};

class BuzzerController {
public:
  void   begin();
  void   update();
  void   play(String text);
  String getBuzzerText() const;
  void   printStatus() const;

private:
  void buzzerOff();
  void buzzerTone(int frequency);
  void startPattern(ToneStep* pattern, int length, const String& text);
  void stopPattern();

  ToneStep* _currentPattern      = nullptr;
  int       _currentPatternLength = 0;
  int       _currentStepIndex    = 0;
  bool      _playing             = false;
  uint32_t  _stepStartMs         = 0;
  String    _buzzerText          = "OFF";
};
