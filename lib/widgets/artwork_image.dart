import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network cover art with disk + memory cache via [CachedNetworkImage].
class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.imageUrl,
    required this.size,
    this.borderRadius = 12,
    this.heroTag,
  });

  final String imageUrl;
  final double size;
  final double borderRadius;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHigh;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final px = (size * dpr).round();

    Widget image = RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          cacheKey: imageUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 180),
          fadeOutDuration: const Duration(milliseconds: 120),
          memCacheWidth: px,
          memCacheHeight: px,
          maxWidthDiskCache: 1200,
          maxHeightDiskCache: 1200,
          filterQuality: FilterQuality.medium,
          placeholder: (context, url) => Container(
            width: size,
            height: size,
            color: surface.withValues(alpha: 0.65),
            alignment: Alignment.center,
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Container(
            width: size,
            height: size,
            color: surface.withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: Icon(
              Icons.music_note_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.45,
                  ),
              size: size * 0.36,
            ),
          ),
        ),
      ),
    );

    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }

    return image;
  }
}
