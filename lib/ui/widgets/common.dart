import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../search/matched_track.dart';
import '../../theme/aurora_theme.dart';

/// Section title with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.subtitle});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.text.bodySmall),
                  ),
              ],
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Pill showing what the app can do with a track — never ambiguous about
/// previews or unavailable tracks.
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.playability, this.compact = false});

  final Playability playability;
  final bool compact;

  factory AvailabilityBadge.forTrack(MatchedTrack t, {bool compact = false}) =>
      AvailabilityBadge(
        playability: t.hasFullTrack
            ? Playability.full
            : t.previewOnly
                ? Playability.preview
                : Playability.none,
        compact: compact,
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color, icon) = switch (playability) {
      Playability.full => ('Full track', p.success, Icons.graphic_eq_rounded),
      Playability.local => ('On device', p.accent, Icons.phone_iphone_rounded),
      Playability.preview => ('Preview', p.warning, Icons.timelapse_rounded),
      Playability.none => ('Not streamable', p.textTertiary, Icons.block_rounded),
    };
    if (compact && playability == Playability.full) return const SizedBox.shrink();
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Friendly empty / error state with optional action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 34, color: p.accent),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: context.text.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: context.text.bodyMedium),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Animated shimmer placeholder used while content loads.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(p.surfaceRaised, p.divider, _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Skeleton rows matching [SongTile] layout.
class SongTileSkeletonList extends StatelessWidget {
  const SongTileSkeletonList({super.key, this.count = 8});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Skeleton(width: 52, height: 52, radius: 10),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 120.0 + (i * 37 % 90), height: 13),
                      const SizedBox(height: 8),
                      Skeleton(width: 70.0 + (i * 23 % 60), height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small "Premium" lock chip for gated actions.
class PremiumChip extends StatelessWidget {
  const PremiumChip({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: p.brandGradient,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'PREMIUM',
        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6),
      ),
    );
  }
}

/// Animated equaliser bars marking the currently playing row.
class NowPlayingBars extends StatefulWidget {
  const NowPlayingBars({super.key, required this.playing, this.color});
  final bool playing;
  final Color? color;

  @override
  State<NowPlayingBars> createState() => _NowPlayingBarsState();
}

class _NowPlayingBarsState extends State<NowPlayingBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(NowPlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.palette.accent;
    return Semantics(
      label: widget.playing ? 'Now playing' : 'Paused',
      child: SizedBox(
        width: 16,
        height: 14,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final phase in const [0.0, 0.45, 0.8])
                Container(
                  width: 3.4,
                  height: 4 + 10 * (((_c.value + phase) % 1.0 - 0.5).abs() * 2),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
