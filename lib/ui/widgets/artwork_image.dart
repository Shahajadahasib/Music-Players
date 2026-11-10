import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../theme/aurora_theme.dart';

/// Cover art with memory + disk cache. Missing / broken artwork falls back to
/// a generated gradient tile (deterministic per [seed]) rather than a grey box.
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.imageUrl,
    required this.size,
    this.borderRadius = 12,
    this.heroTag,
    this.seed = '',
    this.icon = Icons.music_note_rounded,
  });

  final String imageUrl;
  final double size;
  final double borderRadius;
  final String? heroTag;
  final String seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final fallback = _Fallback(size: size, seed: seed, icon: icon);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round();

    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: imageUrl.startsWith('http')
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 160),
              memCacheWidth: px,
              memCacheHeight: px,
              maxWidthDiskCache: 1000,
              maxHeightDiskCache: 1000,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            )
          : fallback,
    );
    image = RepaintBoundary(child: image);
    if (heroTag != null) image = Hero(tag: heroTag!, child: image);
    return Semantics(image: true, label: 'Artwork', child: image);
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size, required this.seed, required this.icon});
  final double size;
  final String seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = [p.accent, p.accentAlt, p.accentWarm];
    final h = seed.hashCode.abs();
    final a = colors[h % 3], b = colors[(h ~/ 3 + 1) % 3];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [a.withValues(alpha: 0.85), b.withValues(alpha: 0.55)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: size * 0.38),
    );
  }
}
