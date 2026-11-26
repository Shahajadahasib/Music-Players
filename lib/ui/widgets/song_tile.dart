import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../playback/stream_verifier.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../search/matched_track.dart';
import '../../theme/aurora_theme.dart';
import 'artwork_image.dart';
import 'common.dart';
import 'song_actions.dart';

/// Standard song row used everywhere (search, library, playlists, queue).
class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.subtitle,
    this.track,
    this.playlistId,
    this.leadingIndex,
    this.trailing,
    this.showActions = true,
  });

  final Song song;
  final VoidCallback onTap;
  final String? subtitle;

  /// When shown from search: the merged multi-provider track.
  final MatchedTrack? track;
  final String? playlistId;
  final int? leadingIndex;
  final Widget? trailing;
  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final ids = {song.id, ...?track?.candidates.map((c) => c.id)};
    final isCurrent = ref.watch(
      playerControllerProvider.select((s) => ids.contains(s.currentSong?.id)),
    );
    final isPlaying = isCurrent && ref.watch(playerControllerProvider.select((s) => s.isPlaying));
    final isFav = ref.watch(playerControllerProvider.select((s) => s.favorites.contains(song.id)));

    final status = _status(ref);
    // Library lists only flag what is unusual; search shows every status.
    final showBadge = track != null || status != TrackStatus.full;
    final providerId = track == null
        ? ''
        : (track!.isPlayable ? track!.best.sourceId : track!.display.sourceId);
    final providerName = providerId.isEmpty
        ? ''
        : (ref.watch(sourceByIdProvider(providerId))?.info.displayName ?? providerId);
    final secondary = subtitle ??
        [
          song.artist,
          if (song.album.isNotEmpty && track == null) song.album,
          if (providerName.isNotEmpty) providerName,
        ].where((e) => e.isNotEmpty).join(' · ');
    final unplayable = status == TrackStatus.unavailable || status == TrackStatus.originalUnavailable;

    return Semantics(
      button: true,
      label: '${song.title}, ${song.artist}${isCurrent ? ', now playing' : ''}',
      child: InkWell(
        onTap: onTap,
        onLongPress: showActions ? () => showSongActions(context, ref, song, track: track, playlistId: playlistId) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(
            children: [
              if (leadingIndex != null)
                SizedBox(
                  width: 28,
                  child: isCurrent
                      ? NowPlayingBars(playing: isPlaying)
                      : Text('${leadingIndex! + 1}', style: context.text.bodyMedium),
                ),
              Opacity(
                opacity: unplayable ? 0.55 : 1,
                child: ArtworkImage(
                  imageUrl: song.coverUrl,
                  size: 52,
                  borderRadius: 10,
                  seed: song.title,
                  icon: song.isLocal ? Icons.audio_file_rounded : Icons.music_note_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCurrent && leadingIndex == null) ...[
                          NowPlayingBars(playing: isPlaying),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            song.title.isEmpty ? 'Untitled' : song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium?.copyWith(
                              fontSize: 15,
                              color: isCurrent ? p.accent : (unplayable ? p.textSecondary : p.textPrimary),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (showBadge) ...[
                          Flexible(flex: 0, child: StatusBadge(status)),
                          const SizedBox(width: 6),
                        ],
                        if (isFav) ...[
                          Icon(Icons.favorite_rounded, size: 12, color: p.accentWarm),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            secondary.isEmpty ? 'Unknown artist' : secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodyMedium?.copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (song.duration != null && !song.isPreview && trailing == null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(formatTrackDuration(song.duration!), style: context.text.bodySmall),
                ),
              ?trailing,
              if (showActions)
                IconButton(
                  tooltip: 'More options',
                  icon: Icon(Icons.more_vert_rounded, color: p.textTertiary),
                  onPressed: () => showSongActions(context, ref, song, track: track, playlistId: playlistId),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Status for the badge. Search results are only "Full track" once the
  /// stream has been verified (during discovery, or lazily here).
  TrackStatus _status(WidgetRef ref) {
    final t = track;
    if (t == null) {
      return switch (song.playability) {
        Playability.full => TrackStatus.full,
        Playability.preview => TrackStatus.preview,
        Playability.local => TrackStatus.local,
        Playability.none => TrackStatus.unavailable,
      };
    }
    if (t.originalUnavailable) return TrackStatus.originalUnavailable;
    if (!t.isPlayable) return TrackStatus.unavailable;
    final best = t.best;
    if (best.isLocal) return TrackStatus.local;
    if (t.verifiedIds.contains(best.id)) {
      return best.isPreview ? TrackStatus.preview : TrackStatus.full;
    }
    final check = ref.watch(streamCheckProvider(best));
    return check.when(
      loading: () => TrackStatus.checking,
      error: (_, _) => TrackStatus.unavailable,
      data: (c) => switch (c.status) {
        StreamStatus.playable => best.isPreview ? TrackStatus.preview : TrackStatus.full,
        StreamStatus.unavailable => TrackStatus.unavailable,
        // Could not confirm (timeout / server error): don't hide it, but
        // don't promise either.
        StreamStatus.unknown => TrackStatus.unverified,
      },
    );
  }
}
