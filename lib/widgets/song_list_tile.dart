import 'package:flutter/material.dart';

import '../models/song.dart';
import 'artwork_image.dart';

class SongListTile extends StatelessWidget {
  const SongListTile({
    super.key,
    required this.song,
    required this.isCurrentSong,
    required this.isPlaying,
    required this.isFavorite,
    required this.onTap,
    required this.onFavorite,
  });

  final Song song;
  final bool isCurrentSong;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accent = colorScheme.primary;
    final subtitleColor = colorScheme.onSurfaceVariant.withValues(alpha: 0.85);

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isCurrentSong
                ? accent.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerLow,
            border: Border.all(
              color: isCurrentSong
                  ? accent.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              splashColor: accent.withValues(alpha: 0.12),
              highlightColor: accent.withValues(alpha: 0.06),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avoid Hero: mini-player + list can share screen with same song.
                    ArtworkImage(
                      imageUrl: song.coverUrl,
                      size: 56,
                      borderRadius: 12,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.15,
                              color: isCurrentSong
                                  ? accent.withValues(alpha: 0.95)
                                  : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.album.isNotEmpty
                                ? '${song.artist} · ${song.album}'
                                : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subtitleColor,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: isFavorite ? 'Remove favorite' : 'Add favorite',
                      onPressed: onFavorite,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: isFavorite
                            ? Colors.redAccent.withValues(alpha: 0.85)
                            : colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                      ),
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        size: 22,
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: isCurrentSong
                                ? Icon(
                                    isPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.music_note_rounded,
                                    key: ValueKey('${song.id}-$isPlaying'),
                                    color: accent.withValues(alpha: 0.9),
                                    size: 18,
                                  )
                                : const SizedBox(
                                    key: ValueKey('empty-indicator'),
                                    height: 18,
                                  ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(song.duration),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.75),
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration? value) {
    if (value == null) {
      return '--:--';
    }
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
