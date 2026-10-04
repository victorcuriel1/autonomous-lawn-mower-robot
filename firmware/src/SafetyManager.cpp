#include "SafetyManager.h"

void SafetyManager::activateEstop() {
  _estop = true;
}

void SafetyManager::resetEstop() {
  _estop = false;
}

bool SafetyManager::isEstop() const {
  return _estop;
}

void SafetyManager::printStatus() const {
  Serial.print("ESTADO,");
  Serial.println(_estop ? 1 : 0);
}
