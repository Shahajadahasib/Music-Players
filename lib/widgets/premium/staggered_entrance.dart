import 'package:flutter/material.dart';

/// Subtle fade + slide when a list item first appears (cheap; skips deep indices).
class StaggeredListEntrance extends StatelessWidget {
  const StaggeredListEntrance({
    super.key,
    required this.index,
    required this.child,
    this.cap = 18,
    this.baseMs = 200,
    this.stepMs = 32,
    this.offsetY = 10,
  });

  final int index;
  final Widget child;
  final int cap;
  final int baseMs;
  final int stepMs;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    if (index > cap) return child;
    final ms = baseMs + (index.clamp(0, 12) * stepMs);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, offsetY * (1 - t)),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
