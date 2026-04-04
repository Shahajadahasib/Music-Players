import 'package:flutter/services.dart';

/// Central place for playback / UI haptics (no-ops on unsupported platforms).
abstract final class AppHaptics {
  static void light() => HapticFeedback.lightImpact();

  static void selection() => HapticFeedback.selectionClick();

  static void medium() => HapticFeedback.mediumImpact();
}
