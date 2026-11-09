import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_provider.dart';
import '../../theme/aurora_theme.dart';
import '../../utils/haptics.dart';
import '../navigation.dart';
import 'artwork_image.dart';

/// Compact player docked above the navigation bar.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerControllerProvider.select((s) => s.currentSong));
    if (song == null) return const SizedBox.shrink();
    final p = context.palette;
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.isPlaying));
    final busy = ref.watch(playerControllerProvider.select((s) => s.isBuffering || s.isResolving));
    final controller = ref.read(playerControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Material(
        color: p.surfaceRaised,
        elevation: 0,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openNowPlaying(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                child: Row(
                  children: [
                    ArtworkImage(
                      imageUrl: song.coverUrl,
                      size: 44,
                      borderRadius: 9,
                      seed: song.title,
                      heroTag: 'artwork-mini',
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: context.text.titleMedium?.copyWith(fontSize: 14.5)),
                          Text(
                            song.isPreview ? 'Preview · ${song.artist}' : song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                      )
                    else
                      IconButton(
                        tooltip: isPlaying ? 'Pause' : 'Play',
                        iconSize: 32,
                        icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        onPressed: () {
                          AppHaptics.light();
                          controller.togglePlayPause();
                        },
                      ),
                    IconButton(
                      tooltip: 'Next',
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: controller.next,
                    ),
                  ],
                ),
              ),
              const _MiniProgress(),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerControllerProvider.select((s) => s.position));
    final duration = ref.watch(playerControllerProvider.select((s) => s.duration));
    final v = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: LinearProgressIndicator(
        value: v,
        minHeight: 2.5,
        backgroundColor: Colors.transparent,
        color: context.palette.accent,
      ),
    );
  }
}
