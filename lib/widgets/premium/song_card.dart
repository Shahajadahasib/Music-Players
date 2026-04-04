import 'package:flutter/material.dart';

import '../../models/song.dart';
import '../../theme/aurora_theme.dart';
import '../../utils/haptics.dart';
import '../artwork_image.dart';
import 'glass.dart';
import 'pressable_scale.dart';

/// Horizontal “vinyl-style” card for Recently played carousel.
class PremiumRecentSongCard extends StatelessWidget {
  const PremiumRecentSongCard({
    super.key,
    required this.song,
    required this.onTap,
    this.heroTag,
  });

  final Song song;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PressableScale(
      borderRadius: BorderRadius.circular(26),
      pressedScale: 0.97,
      splashColor: Colors.white.withValues(alpha: 0.12),
      highlightColor: Colors.white.withValues(alpha: 0.05),
      hapticOnTap: true,
      onTap: onTap,
      child: SizedBox(
        width: 138,
        height: 208,
        child: GlassPanel(
          borderRadius: 26,
          blurSigma: 22,
          opacity: 0.1,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: heroTag != null
                      ? Hero(
                          tag: heroTag!,
                          child: ArtworkImage(
                            imageUrl: song.coverUrl,
                            size: 118,
                            borderRadius: 0,
                          ),
                        )
                      : ArtworkImage(
                          imageUrl: song.coverUrl,
                          size: 118,
                          borderRadius: 0,
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Flexible(
                      child: Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                          letterSpacing: -0.2,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vertical list row: glass strip, artwork, metadata, play + favorite.
class PremiumDiscoverSongRow extends StatelessWidget {
  const PremiumDiscoverSongRow({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.isFavorite,
    required this.onPlay,
    required this.onFavorite,
    this.showFavorite = true,
  });

  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isCurrent
        ? AuroraTheme.auroraBlue
        : Colors.white.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        borderRadius: 22,
        blurSigma: 18,
        opacity: 0.08,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ArtworkImage(
                imageUrl: song.coverUrl,
                size: 56,
                borderRadius: 0,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accent,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (showFavorite)
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  AppHaptics.selection();
                  onFavorite();
                },
                icon: Icon(
                  isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFavorite
                      ? Colors.pinkAccent.shade100
                      : Colors.white.withValues(alpha: 0.45),
                  size: 22,
                ),
              ),
            _GradientPlayChip(
              isPlaying: isPlaying && isCurrent,
              onPressed: onPlay,
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientPlayChip extends StatelessWidget {
  const _GradientPlayChip({
    required this.isPlaying,
    required this.onPressed,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      borderRadius: BorderRadius.circular(999),
      pressedScale: 0.92,
      duration: const Duration(milliseconds: 95),
      splashColor: Colors.white.withValues(alpha: 0.22),
      highlightColor: Colors.white.withValues(alpha: 0.08),
      hapticOnTap: false,
      onTap: () {
        AppHaptics.medium();
        onPressed();
      },
      child: Ink(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AuroraTheme.playButtonGlow,
          boxShadow: [
            BoxShadow(
              color: AuroraTheme.auroraViolet.withValues(alpha: 0.45),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }
}
