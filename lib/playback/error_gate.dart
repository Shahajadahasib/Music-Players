import 'dart:async';

/// Runs playback-error recovery one at a time **without losing errors**.
///
/// While a recovery is running (retrying, switching sources), a new error —
/// typically the replacement stream failing to load — is remembered and
/// handled as soon as the current recovery finishes, instead of being
/// dropped. Only the latest pending error is kept; the recovery logic itself
/// (FallbackPlanner attempt caps, single same-source retry) guarantees the
/// chain terminates.
class SerialErrorGate<T> {
  SerialErrorGate(this._handle);

  final Future<void> Function(T error) _handle;
  bool _running = false;
  T? _pending;
  bool _hasPending = false;

  bool get isRunning => _running;

  Future<void> report(T error) async {
    if (_running) {
      _pending = error;
      _hasPending = true;
      return;
    }
    _running = true;
    try {
      await _handle(error);
    } finally {
      _running = false;
    }
    if (_hasPending) {
      final next = _pending as T;
      _pending = null;
      _hasPending = false;
      await report(next);
    }
  }
}
