import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/player_stream_providers.dart';
import '../../screens/lyrics_screen.dart';
import '../../theme/aurora_theme.dart';
import '../../utils/haptics.dart';
import '../artwork_image.dart';
import 'waveform_bar.dart';

/// Premium now-playing layout with ambient artwork background.
class NowPlayingPanel extends ConsumerWidget {
  const NowPlayingPanel({
    super.key,
    required this.onShowAddToPlaylist,
    required this.errorBanner,
  });

  final void Function(BuildContext context, WidgetRef ref, Song song)
      onShowAddToPlaylist;
  final Widget? errorBanner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();

    final controller = ref.read(playerControllerProvider.notifier);
    final position = ref.watch(playerPositionProvider);
    final duration = ref.watch(playerDurationProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    final queue = ref.watch(queueProvider);
    final isFavorite = ref.watch(
      favoritesProvider.select((ids) => ids.contains(song.id)),
    );

    final currentIndex = queue.indexWhere((item) => item.id == song.id);
    final hasPrevious = currentIndex > 0;
    final hasNext =
        currentIndex >= 0 && currentIndex < queue.length - 1;

    final safeDuration = duration > Duration.zero
        ? duration
        : (song.duration ?? Duration.zero);
    final total = safeDuration.inMilliseconds <= 0
        ? Duration.zero
        : safeDuration;

    final w = MediaQuery.sizeOf(context).width;
    final artSize = (w - 56).clamp(240.0, 320.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        _ArtworkBackground(coverUrl: song.coverUrl),
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (errorBanner != null) ...[
                errorBanner!,
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 28),
              _AlbumArtwork(size: artSize, song: song),
              const SizedBox(height: 28),
              _SongInfo(song: song),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundGlassIcon(
                    icon: isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: isFavorite
                        ? Colors.pinkAccent.shade100
                        : Colors.white.withValues(alpha: 0.85),
                    onPressed: () {
                      AppHaptics.selection();
                      controller.toggleFavorite(song);
                    },
                  ),
                  const SizedBox(width: 16),
                  _RoundGlassIcon(
                    icon: Icons.playlist_add_rounded,
                    onPressed: () {
                      AppHaptics.light();
                      onShowAddToPlaylist(context, ref, song);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
              WaveformProgress(
                position: position,
                duration: total,
                onSeek: controller.seek,
              ),
              const SizedBox(height: 36),
              PlaybackControls(
                hasPrevious: hasPrevious,
                hasNext: hasNext,
                onPrevious: hasPrevious ? controller.previous : null,
                onNext: hasNext ? controller.next : null,
                onPlayPause: isBuffering
                    ? null
                    : () {
                        if (isPlaying) {
                          controller.pause();
                        } else {
                          controller.resume();
                        }
                      },
                isPlaying: isPlaying,
                isBuffering: isBuffering,
              ),
              const SizedBox(height: 32),
              const LyricsButton(),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Ambient artwork background ─────────────────────────────────────────────

class _ArtworkBackground extends StatelessWidget {
  const _ArtworkBackground({required this.coverUrl});

  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            child: Transform.scale(
              scale: 1.4,
              child: CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.35),
                AuroraTheme.deepSpace.withValues(alpha: 0.75),
                AuroraTheme.deepSpace.withValues(alpha: 0.92),
              ],
              stops: const [0.0, 0.45, 0.85],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Circular album artwork ────────────────────────────────────────────────

class _AlbumArtwork extends StatelessWidget {
  const _AlbumArtwork({required this.size, required this.song});

  final double size;
  final Song song;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AuroraTheme.auroraViolet.withValues(alpha: 0.3),
              blurRadius: 48,
              spreadRadius: 4,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 40,
              offset: const Offset(0, 26),
            ),
          ],
        ),
        child: ClipOval(
          child: Hero(
            tag: 'cover-${song.id}',
            child: ArtworkImage(
              imageUrl: song.coverUrl,
              size: size,
              borderRadius: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Song info ─────────────────────────────────────────────────────────────

class _SongInfo extends StatelessWidget {
  const _SongInfo({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
              child: child,
            ),
          ),
        );
      },
      child: Column(
        key: ValueKey(song.id),
        children: [
          Text(
            song.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: AuroraTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            song.artist,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: GoogleFonts.plusJakartaSans(
              color: AuroraTheme.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Waveform progress ────────────────────────────────────────────────────

class WaveformProgress extends StatelessWidget {
  const WaveformProgress({super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WaveformProgressBar(
          position: position,
          duration: duration,
          onSeek: onSeek,
          barCount: 44,
          height: 50,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              formatTrackDuration(position),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AuroraTheme.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
            Text(
              formatTrackDuration(
                duration > Duration.zero ? duration : Duration.zero,
              ),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AuroraTheme.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Playback controls ───────────────────────────────────────────────────

class PlaybackControls extends StatelessWidget {
  const PlaybackControls({super.key,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
    required this.isPlaying,
    required this.isBuffering,
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onPlayPause;
  final bool isPlaying;
  final bool isBuffering;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _NavOrb(
          icon: Icons.skip_previous_rounded,
          enabled: hasPrevious,
          onPressed: onPrevious,
        ),
        const SizedBox(width: 28),
        _MainPlayOrb(
          isPlaying: isPlaying,
          isBuffering: isBuffering,
          onPressed: onPlayPause,
        ),
        const SizedBox(width: 28),
        _NavOrb(
          icon: Icons.skip_next_rounded,
          enabled: hasNext,
          onPressed: onNext,
        ),
      ],
    );
  }
}

// ─── Lyrics button ───────────────────────────────────────────────────────

class LyricsButton extends StatelessWidget {
  const LyricsButton();

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () {
        AppHaptics.light();
        Navigator.of(context).push<void>(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => const LyricsScreen(),
            transitionsBuilder: (_, anim, _, child) {
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            transitionDuration: const Duration(milliseconds: 380),
          ),
        );
      },
      icon: const Icon(Icons.lyrics_outlined, size: 22),
      label: const Text('Lyrics'),
      style: TextButton.styleFrom(
        foregroundColor: AuroraTheme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
  }
}

// ─── Round Glass Icon ─────────────────────────────────────────────────────

class _RoundGlassIcon extends StatefulWidget {
  const _RoundGlassIcon({
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  State<_RoundGlassIcon> createState() => _RoundGlassIconState();
}

class _RoundGlassIconState extends State<_RoundGlassIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onPressed,
          child: Ink(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: AuroraTheme.glassBorder),
            ),
            child: Icon(
              widget.icon,
              color: widget.color ?? Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Nav Orb ──────────────────────────────────────────────────────────────

class _NavOrb extends StatefulWidget {
  const _NavOrb({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  State<_NavOrb> createState() => _NavOrbState();
}

class _NavOrbState extends State<_NavOrb> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.35,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed == null
                ? null
                : () {
                    AppHaptics.light();
                    widget.onPressed!();
                  },
            customBorder: const CircleBorder(),
            onTapDown: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: widget.onPressed == null
                ? null
                : () => setState(() => _pressed = false),
            child: Ink(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(widget.icon, size: 32, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Main Play Orb ────────────────────────────────────────────────────────

class _MainPlayOrb extends StatefulWidget {
  const _MainPlayOrb({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback? onPressed;

  @override
  State<_MainPlayOrb> createState() => _MainPlayOrbState();
}

class _MainPlayOrbState extends State<_MainPlayOrb> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AuroraTheme.playButtonGlow,
          boxShadow: [
            BoxShadow(
              color: AuroraTheme.auroraBlue.withValues(alpha: 0.5),
              blurRadius: 28,
              spreadRadius: 2,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed == null
                ? null
                : () {
                    AppHaptics.medium();
                    widget.onPressed!();
                  },
            onTapDown: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = true),
            onTapUp: widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = false),
            onTapCancel: widget.onPressed == null
                ? null
                : () => setState(() => _pressed = false),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.isBuffering
                    ? const SizedBox(
                        key: ValueKey('buf'),
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        widget.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey(widget.isPlaying),
                        size: 44,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
