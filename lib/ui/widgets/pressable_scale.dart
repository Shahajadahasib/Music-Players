import 'package:flutter/material.dart';

import '../../utils/haptics.dart';

/// InkWell + subtle scale-down while pressed; optional light haptic on tap.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = BorderRadius.zero,
    this.pressedScale = 0.98,
    this.duration = const Duration(milliseconds: 110),
    this.hapticOnTap = true,
    this.splashColor,
    this.highlightColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final double pressedScale;
  final Duration duration;
  final bool hapticOnTap;
  final Color? splashColor;
  final Color? highlightColor;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1.0,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: widget.borderRadius,
          splashColor: widget.splashColor,
          highlightColor: widget.highlightColor,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            if (widget.hapticOnTap) AppHaptics.light();
            widget.onTap();
          },
          child: widget.child,
        ),
      ),
    );
  }
}
