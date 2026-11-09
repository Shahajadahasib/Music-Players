import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../licensing/license_controller.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../theme/aurora_theme.dart';
import '../../utils/haptics.dart';
import '../navigation.dart';
import '../widgets/artwork_image.dart';
import '../widgets/common.dart';
import '../widgets/song_actions.dart';
import 'artist_screen.dart';
import 'queue_sheet.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerControllerProvider.select((s) => s.currentSong));
    final p = context.palette;
    if (song == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.music_off_rounded, title: 'Nothing is playing'),
      );
    }
    final tint = [p.accent, p.accentAlt, p.accentWarm][song.title.hashCode.abs() % 3];
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 840 && size.width > size.height;
    final art = (wide ? size.height * 0.55 : size.width - 56).clamp(160.0, 460.0);

    final artwork = Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 18))],
        ),
        child: ArtworkImage(
          imageUrl: song.coverUrl,
          size: art,
          borderRadius: 22,
          seed: song.title,
          heroTag: 'artwork-mini',
        ),
      ),
    );

    final controls = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleRow(song: song),
        if (song.isPreview) _PreviewBanner(song: song),
        const SizedBox(height: 14),
        const _SeekBar(),
        const SizedBox(height: 4),
        const _TransportControls(),
        const SizedBox(height: 10),
        const _VolumeRow(),
        const SizedBox(height: 6),
        _ActionRow(song: song),
        const SizedBox(height: 4),
        _Attribution(song: song),
      ],
    );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: p.ambient(tint)),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(song: song),
              Expanded(
                child: wide
                    ? Row(
                        children: [
                          Expanded(child: artwork),
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 520),
                                  child: controls,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            artwork,
                            const SizedBox(height: 26),
                            controls,
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceByIdProvider(song.sourceId));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text('PLAYING FROM', style: context.text.labelSmall?.copyWith(color: context.palette.textTertiary)),
                Text(
                  song.isLocal ? 'Your device' : (source?.info.displayName ?? song.sourceId),
                  style: context.text.titleMedium?.copyWith(fontSize: 14),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'More options',
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => showSongActions(context, ref, song),
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(playerControllerProvider.select((s) => s.favorites.contains(song.id)));
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: song.artist.isEmpty || song.isLocal
                    ? null
                    : () => pushPage(
                          context,
                          ArtistScreen(name: song.artist, sourceId: song.sourceId, artistId: song.artistId),
                        ),
                child: Text(song.artist.isEmpty ? 'Unknown artist' : song.artist,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: context.text.titleMedium?.copyWith(color: p.textSecondary, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isFav ? 'Remove from favourites' : 'Add to favourites',
          iconSize: 28,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(isFav),
              color: isFav ? p.accentWarm : p.textPrimary,
            ),
          ),
          onPressed: () {
            AppHaptics.light();
            ref.read(playerControllerProvider.notifier).toggleFavorite(song);
          },
        ),
      ],
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: p.warning.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.timelapse_rounded, size: 18, color: p.warning),
          const SizedBox(width: 8),
          const Expanded(child: Text('Short preview — the full track isn’t licensed for streaming here.')),
          if (song.externalUrl.isNotEmpty)
            TextButton(
              onPressed: () => openExternal(context, song.externalUrl),
              child: Text(song.sourceId == 'itunes' ? 'Apple Music' : 'Open'),
            ),
        ],
      ),
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(playerControllerProvider.select((s) => s.position));
    final buffered = ref.watch(playerControllerProvider.select((s) => s.bufferedPosition));
    final duration = ref.watch(playerControllerProvider.select((s) => s.duration));
    final max = duration.inMilliseconds.toDouble();
    final known = max > 0;
    final value = (_dragValue ?? position.inMilliseconds.toDouble()).clamp(0.0, known ? max : 1.0);
    final shown = Duration(milliseconds: value.round());

    return Column(
      children: [
        Slider(
          min: 0,
          max: known ? max : 1,
          value: known ? value : 0,
          secondaryTrackValue: known ? buffered.inMilliseconds.toDouble().clamp(0.0, max) : null,
          semanticFormatterCallback: (v) => '${formatTrackDuration(Duration(milliseconds: v.round()))} of ${formatTrackDuration(duration)}',
          onChanged: known ? (v) => setState(() => _dragValue = v) : null,
          onChangeEnd: known
              ? (v) {
                  ref.read(playerControllerProvider.notifier).seek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatTrackDuration(shown), style: context.text.bodySmall),
              Text(known ? '-${formatTrackDuration(duration - shown)}' : '--:--', style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransportControls extends ConsumerWidget {
  const _TransportControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(playerControllerProvider.notifier);
    final p = context.palette;
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.isPlaying));
    final busy = ref.watch(playerControllerProvider.select((s) => s.isBuffering || s.isResolving));
    final shuffle = ref.watch(playerControllerProvider.select((s) => s.isShuffle));
    final repeat = ref.watch(playerControllerProvider.select((s) => s.repeatMode));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          tooltip: shuffle ? 'Shuffle on' : 'Shuffle off',
          isSelected: shuffle,
          icon: Icon(Icons.shuffle_rounded, color: shuffle ? p.accent : p.textSecondary),
          onPressed: c.toggleShuffle,
        ),
        IconButton(
          tooltip: 'Previous',
          iconSize: 40,
          icon: const Icon(Icons.skip_previous_rounded),
          onPressed: c.previous,
        ),
        Semantics(
          button: true,
          label: busy ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
          child: GestureDetector(
            onTap: () {
              AppHaptics.medium();
              c.togglePlayPause();
            },
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: p.brandGradient,
                boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              alignment: Alignment.center,
              child: busy && !isPlaying
                  ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 44, color: Colors.white),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          iconSize: 40,
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: c.next,
        ),
        IconButton(
          tooltip: switch (repeat) {
            LoopMode.off => 'Repeat off',
            LoopMode.all => 'Repeat all',
            LoopMode.one => 'Repeat one',
          },
          icon: Icon(
            repeat == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            color: repeat == LoopMode.off ? p.textSecondary : p.accent,
          ),
          onPressed: c.toggleRepeat,
        ),
      ],
    );
  }
}

class _VolumeRow extends ConsumerWidget {
  const _VolumeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(playerControllerProvider.select((s) => s.volume));
    final p = context.palette;
    return Row(
      children: [
        Icon(Icons.volume_mute_rounded, size: 18, color: p.textTertiary),
        Expanded(
          child: Slider(
            value: volume,
            semanticFormatterCallback: (v) => 'Volume ${(v * 100).round()}%',
            onChanged: (v) => ref.read(playerControllerProvider.notifier).setVolume(v),
          ),
        ),
        Icon(Icons.volume_up_rounded, size: 18, color: p.textTertiary),
      ],
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sleepOn = ref.watch(playerControllerProvider.select((s) => s.sleepTimerActive));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        IconButton(
          tooltip: sleepOn ? 'Sleep timer on' : 'Sleep timer',
          icon: Icon(Icons.bedtime_rounded, color: sleepOn ? p.accent : p.textSecondary),
          onPressed: () {
            if (!requirePremium(context, ref, PremiumFeature.sleepTimer)) return;
            showSleepTimerSheet(context, ref);
          },
        ),
        IconButton(
          tooltip: 'Add to playlist',
          icon: Icon(Icons.playlist_add_rounded, color: p.textSecondary),
          onPressed: () => showAddToPlaylist(context, ref, song),
        ),
        IconButton(
          tooltip: 'Queue',
          icon: Icon(Icons.queue_music_rounded, color: p.textSecondary),
          onPressed: () => showQueueSheet(context),
        ),
      ],
    );
  }
}

class _Attribution extends ConsumerWidget {
  const _Attribution({required this.song});
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (song.isLocal) return const SizedBox.shrink();
    final source = ref.watch(sourceByIdProvider(song.sourceId));
    final text = [
      source?.info.attribution ?? '',
      if (song.license.isNotEmpty) 'Licence: ${song.license}',
    ].where((e) => e.isNotEmpty).join(' · ');
    return Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: context.text.bodySmall),
        if (song.externalUrl.startsWith('https://'))
          TextButton(
            onPressed: () => openExternal(context, song.externalUrl),
            child: Text('View on ${source?.info.displayName ?? 'provider'}'),
          ),
      ],
    );
  }
}
