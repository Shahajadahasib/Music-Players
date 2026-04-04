import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../theme/aurora_theme.dart';
import '../utils/haptics.dart';

/// Compact floating mini-player — flush bottom with slim progress bar.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({
    super.key,
    required this.onTap,
    this.isPlayerRouteActive = false,
  });

  final VoidCallback onTap;
  final bool isPlayerRouteActive;

  static const double _barHeight = 72;
  static const double _artSize = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final isBottomSheetActive = ref.watch(bottomSheetActiveProvider);
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isBuffering = ref.watch(isBufferingProvider);

    if (currentSong == null || isPlayerRouteActive || isBottomSheetActive) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AuroraTheme.surfaceElevated.withValues(alpha: 0.95),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Slim progress bar at top edge.
              const _MiniProgressIndicator(),
              SizedBox(
                height: _barHeight,
                child: Row(
                  children: [
                    // Artwork + metadata (tappable area).
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            AppHaptics.light();
                            onTap();
                          },
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              8,
                              8,
                              8,
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: _artSize,
                                    height: _artSize,
                                    child: CachedNetworkImage(
                                      imageUrl: currentSong.coverUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 100,
                                      memCacheHeight: 100,
                                      fadeInDuration:
                                          const Duration(milliseconds: 160),
                                      placeholder: (_, _) => Container(
                                        color: Colors.white.withValues(
                                          alpha: 0.06,
                                        ),
                                      ),
                                      errorWidget: (_, _, _) => Container(
                                        color: AuroraTheme.textTertiary
                                            .withValues(alpha: 0.08),
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: AuroraTheme.textTertiary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentSong.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          letterSpacing: -0.2,
                                          color: Colors.white.withValues(
                                            alpha: 0.96,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        currentSong.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          fontSize: 12,
                                          height: 1.15,
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
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
                    // Play/Pause button.
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: isBuffering
                          ? const SizedBox(
                              width: 42,
                              height: 42,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : _MiniPlayButton(
                              isPlaying: isPlaying,
                              onTap: () {
                                AppHaptics.medium();
                                if (isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.resume();
                                }
                              },
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

/// Slim progress indicator showing current playback position.
class _MiniProgressIndicator extends ConsumerWidget {
  const _MiniProgressIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerPositionProvider);
    final duration = ref.watch(playerDurationProvider);

    if (duration <= Duration.zero) {
      return DecoratedBox(
        decoration:
            BoxDecoration(color: Colors.white.withValues(alpha: 0.06)),
        child: const SizedBox(height: 2),
      );
    }

    final progress = (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0.0, 1.0);

    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.white.withValues(alpha: 0.06)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AuroraTheme.playButtonGlow),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact play/pause icon button for the mini player.
class _MiniPlayButton extends StatefulWidget {
  const _MiniPlayButton({
    required this.isPlaying,
    required this.onTap,
  });

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  State<_MiniPlayButton> createState() => _MiniPlayButtonState();
}

class _MiniPlayButtonState extends State<_MiniPlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 80),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) {
            setState(() => _pressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _pressed = false),
          child: Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AuroraTheme.auroraBlue,
              shape: BoxShape.circle,
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                widget.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                key: ValueKey(widget.isPlaying),
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
