#pragma once
#include <Arduino.h>

class SafetyManager {
public:
  void activateEstop();
  void resetEstop();
  bool isEstop() const;
  void printStatus() const;

private:
  bool _estop = false;
};
