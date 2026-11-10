import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Central error/crash reporting.
///
/// Privacy-first default: errors are logged locally (debug console + an
/// in-memory ring buffer) and never leave the device. To use a crash service
/// (Sentry, Firebase Crashlytics, …) assign [sink] at startup — see
/// docs/ARCHITECTURE.md → "Crash reporting". Only send stack traces and app
/// state, never search terms or file names (they can be personal data).
abstract final class ErrorReporter {
  /// Optional remote sink. Must not throw.
  static void Function(Object error, StackTrace? stack, {String? context})? sink;

  static final Queue<String> _recent = Queue();
  static List<String> get recent => List.unmodifiable(_recent);

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      report(details.exception, details.stack, context: 'flutter');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack, context: 'platform');
      return true; // handled: keep the app running
    };
  }

  static void report(Object error, StackTrace? stack, {String? context}) {
    final line = '[${DateTime.now().toIso8601String()}] ${context ?? 'app'}: $error';
    _recent.addLast(line);
    while (_recent.length > 50) {
      _recent.removeFirst();
    }
    debugPrint(line);
    try {
      sink?.call(error, stack, context: context);
    } catch (_) {}
  }
}
