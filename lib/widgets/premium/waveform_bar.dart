import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/aurora_theme.dart';
import '../../utils/haptics.dart';

/// Animated pseudo-waveform driven by playback progress (no audio analysis).
class WaveformProgressBar extends StatelessWidget {
  const WaveformProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.barCount = 40,
    this.height = 52,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final int barCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final progress = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => AppHaptics.selection(),
          onHorizontalDragUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(d.globalPosition);
            final p = (local.dx / w).clamp(0.0, 1.0);
            onSeek(Duration(milliseconds: (p * totalMs).round()));
          },
          onTapDown: (d) {
            AppHaptics.selection();
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local = box.globalToLocal(d.globalPosition);
            final p = (local.dx / w).clamp(0.0, 1.0);
            onSeek(Duration(milliseconds: (p * totalMs).round()));
          },
          child: SizedBox(
            height: height,
            width: w,
            child: CustomPaint(
              painter: _WaveformPainter(
                progress: progress,
                barCount: barCount,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: 0.18),
                accent: AuroraTheme.auroraMagenta.withValues(alpha: 0.85),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.barCount,
    required this.activeColor,
    required this.inactiveColor,
    required this.accent,
  });

  final double progress;
  final int barCount;
  final Color activeColor;
  final Color inactiveColor;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 2.0;
    final totalGap = gap * (barCount - 1);
    final barW = (size.width - totalGap) / barCount;
    final mid = size.height * 0.5;
    final fillPx = size.width * progress;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barW + gap);
      final seed = (i + 1) * 9973;
      final norm = (math.sin(seed * 0.01) * 0.5 + 0.5);
      final h = 8.0 + norm * (size.height - 12);
      final top = mid - h / 2;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barW, h),
        const Radius.circular(4),
      );
      final active = x + barW <= fillPx;
      final paint = Paint()
        ..color = active
            ? Color.lerp(accent, activeColor, (i / barCount) * 0.35)!
            : inactiveColor;
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.barCount != barCount;
  }
}
