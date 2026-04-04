import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../theme/aurora_theme.dart';
import '../utils/haptics.dart';
import '../widgets/premium/glass.dart';

List<String> _placeholderLyrics(Song song) {
  return <String>[
    '♪ ${song.title}',
    '',
    'Lights down low, the city hums',
    'Every heartbeat like a drum',
    '${song.artist.isNotEmpty ? song.artist : 'The artist'} holds the room',
    '',
    'We ride the wave, we chase the sound',
    'Feet on ground but mind unbound',
    '',
    '[ Chorus ]',
    'Turn it up — let the night begin',
    'Lose yourself and breathe it in',
    '',
    '[ Verse ]',
    'Melodies that paint the sky',
    'No goodbyes, we amplify',
    '',
    '[ Bridge ]',
    'Hold the moment, slow the time',
    'Yours and mine, in stereo line',
    '',
    '[ Outro ]',
    'Streaming discovery via Audius',
    'Thanks for listening ♥',
  ];
}

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scroll = ScrollController();
  static const double _lineExtent = 44;
  int _lastActiveLine = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  int _activeLine(Duration position, Duration total, int lineCount) {
    if (lineCount <= 0) return 0;
    if (total.inMilliseconds <= 0) return 0;
    final t = position.inMilliseconds / total.inMilliseconds;
    return (t * lineCount).floor().clamp(0, lineCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final lyrics = _placeholderLyrics(song);
    final position = ref.watch(playerPositionProvider);
    final duration = ref.watch(playerDurationProvider);
    final total = duration > Duration.zero
        ? duration
        : (song.duration ?? const Duration(minutes: 3));
    final active = _activeLine(position, total, lyrics.length);

    if (active != _lastActiveLine) {
      _lastActiveLine = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final h = MediaQuery.sizeOf(context).height;
        final target = (active * _lineExtent - h * 0.28)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      });
    }

    final controller = ref.read(playerControllerProvider.notifier);
    final isPlaying = ref.watch(isPlayingProvider);
    final isBuffering = ref.watch(isBufferingProvider);

    return Scaffold(
      backgroundColor: AuroraTheme.deepSpace,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () {
            AppHaptics.light();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Lyrics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Transform.scale(
                scale: 1.2,
                child: CachedNetworkImage(
                  imageUrl: song.coverUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AuroraTheme.backgroundGradient,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AuroraTheme.deepSpace.withValues(alpha: 0.25),
                    AuroraTheme.deepSpace.withValues(alpha: 0.88),
                    AuroraTheme.deepSpace,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                    itemCount: lyrics.length,
                    itemBuilder: (context, i) {
                      final line = lyrics[i];
                      final isActive = i == active && line.isNotEmpty;
                      return SizedBox(
                        height: _lineExtent,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          style:
                              Theme.of(context).textTheme.titleMedium!.copyWith(
                                    height: 1.35,
                                    fontWeight: isActive
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    fontSize: isActive ? 20 : 16,
                                    color: isActive
                                        ? Colors.white
                                        : Colors.white.withValues(
                                            alpha: line.isEmpty ? 0.2 : 0.42,
                                          ),
                                    shadows: isActive
                                        ? [
                                            Shadow(
                                              color: AuroraTheme.auroraViolet
                                                  .withValues(alpha: 0.65),
                                              blurRadius: 18,
                                            ),
                                          ]
                                        : null,
                                  ),
                          child: Center(
                            child: Text(
                              line.isEmpty ? ' ' : line,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GlassPanel(
                    borderRadius: 28,
                    blurSigma: 24,
                    opacity: 0.1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            AppHaptics.light();
                            controller.previous();
                          },
                          icon: const Icon(Icons.skip_previous_rounded),
                          color: Colors.white,
                          iconSize: 32,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        _LyricsPlayButton(
                          isPlaying: isPlaying,
                          isBuffering: isBuffering,
                          onPressed: isBuffering
                              ? null
                              : () {
                                  if (isPlaying) {
                                    controller.pause();
                                  } else {
                                    controller.resume();
                                  }
                                },
                        ),
                        IconButton(
                          onPressed: () {
                            AppHaptics.light();
                            controller.next();
                          },
                          icon: const Icon(Icons.skip_next_rounded),
                          color: Colors.white,
                          iconSize: 32,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsPlayButton extends StatefulWidget {
  const _LyricsPlayButton({
    required this.isPlaying,
    required this.isBuffering,
    required this.onPressed,
  });

  final bool isPlaying;
  final bool isBuffering;
  final VoidCallback? onPressed;

  @override
  State<_LyricsPlayButton> createState() => _LyricsPlayButtonState();
}

class _LyricsPlayButtonState extends State<_LyricsPlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.93 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: AuroraTheme.playButtonGlow,
          boxShadow: [
            BoxShadow(
              color: AuroraTheme.auroraViolet.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 8),
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
              child: widget.isBuffering
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      widget.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
