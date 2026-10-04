#include "CutSequencer.h"

void CutSequencer::begin(TrimmerController* trimmer, BrushlessController* brushless) {
  _trimmer   = trimmer;
  _brushless = brushless;
}

void CutSequencer::notifyWheelsStarted() {
  _lastWheelStartMs = millis();
  _wheelsStarted    = true;
}

void CutSequencer::cancelAll() {
  _trimmerWanted   = false;
  _brushlessWanted = false;
  _state           = IDLE;
  if (_trimmer)   _trimmer->forceOff();
  if (_brushless) _brushless->forceOff();
}

void CutSequencer::_startBrushless() {
  if (_brushless) _brushless->on();
}

void CutSequencer::_startTrimmer() {
  if (_trimmer) _trimmer->on();
}

void CutSequencer::_stopAll(bool force) {
  if (force) {
    if (_trimmer)   _trimmer->forceOff();
    if (_brushless) _brushless->forceOff();
  } else {
    if (_trimmer)   _trimmer->off();
    if (_brushless) _brushless->off();
  }
}

void CutSequencer::request(bool trimmerWanted, bool brushlessWanted) {
  // Mismo pedido con la secuencia ya activa: no hacer nada
  if (_state != IDLE &&
      _trimmerWanted  == trimmerWanted &&
      _brushlessWanted == brushlessWanted) {
    return;
  }

  _trimmerWanted   = trimmerWanted;
  _brushlessWanted = brushlessWanted;

  // No se pide nada: apagar ambos con rampa y cancelar la secuencia
  if (!trimmerWanted && !brushlessWanted) {
    _stopAll(false);
    _state = IDLE;
    return;
  }

  // Solo trimmer: arranca directo, sin esperar al brushless
  if (trimmerWanted && !brushlessWanted) {
    if (_brushless) _brushless->off();
    _startTrimmer();
    _state = RUNNING;
    return;
  }

  // Se pide brushless (solo o con trimmer)

  if (!trimmerWanted) {
    if (_trimmer) _trimmer->off();
  }

  // Respetar la espera desde el arranque de ruedas
  bool needWheelWait = _wheelsStarted &&
                       (millis() - _lastWheelStartMs < CUT_DELAY_AFTER_WHEELS_MS);
  if (needWheelWait) {
    _state = WAIT_WHEELS;
    return;
  }

  _startBrushless();

  if (trimmerWanted) {
    _stateStartMs = millis();
    _state = WAIT_BRUSHLESS;
  } else {
    _state = RUNNING;
  }
}

void CutSequencer::update() {
  switch (_state) {
    case IDLE:
      break;

    case WAIT_WHEELS:
      if (millis() - _lastWheelStartMs >= CUT_DELAY_AFTER_WHEELS_MS) {
        _startBrushless();
        if (_trimmerWanted) {
          _stateStartMs = millis();
          _state = WAIT_BRUSHLESS;
        } else {
          _state = RUNNING;
        }
      }
      break;

    case WAIT_BRUSHLESS:
      if (millis() - _stateStartMs >= TRIMMER_DELAY_AFTER_BRUSHLESS_MS) {
        _startTrimmer();
        _state = RUNNING;
      }
      break;

    case RUNNING:
      break;
  }
}
