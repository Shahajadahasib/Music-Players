import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/aurora_theme.dart';

/// Frosted glass surface with soft border and depth.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 24,
    this.blurSigma = 28,
    this.opacity = 0.12,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double blurSigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: opacity + 0.06),
                Colors.white.withValues(alpha: opacity * 0.35),
              ],
            ),
            border: Border.all(
              color: AuroraTheme.glassBorder,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 32,
                offset: const Offset(0, 18),
                spreadRadius: -8,
              ),
              BoxShadow(
                color: AuroraTheme.auroraViolet.withValues(alpha: 0.12),
                blurRadius: 40,
                spreadRadius: -12,
              ),
            ],
          ),
          child: Padding(
            padding: padding ?? EdgeInsets.zero,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Full-screen gradient used behind scrollable content.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AuroraTheme.backgroundGradient),
      child: child,
    );
  }
}
