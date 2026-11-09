import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../search/matched_track.dart';
import '../../theme/aurora_theme.dart';
import '../widgets/artwork_image.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';

/// Album page. Catalogue albums (Apple metadata) are matched track-by-track
/// against authorised full-track providers in the background; each row shows
/// the result as it arrives (full track / not streamable).
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.reference});
  final Song reference;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  List<MatchedTrack>? _tracks;
  bool _failed = false;
  int _matching = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _tracks = null;
    });
    final source = ref.read(sourceByIdProvider(widget.reference.sourceId));
    if (source == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final songs = await source.albumTracks(widget.reference.albumId);
      if (!mounted) return;
      setState(() {
        _tracks = [
          for (final s in songs)
            MatchedTrack(display: s, candidates: s.canPlay ? [s] : const [], relevance: 1),
        ];
      });
      await _matchCatalogueTracks();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Finds authorised streams for catalogue-only rows, 3 at a time.
  Future<void> _matchCatalogueTracks() async {
    final aggregator = ref.read(searchAggregatorProvider);
    final pending = [
      for (var i = 0; i < (_tracks?.length ?? 0); i++)
        if (!_tracks![i].isPlayable) i,
    ];
    if (pending.isEmpty) return;
    setState(() => _matching = pending.length);
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < pending.length && mounted) {
        final i = pending[cursor++];
        final t = _tracks![i];
        try {
          final found = await aggregator.findPlayableFor(t.display);
          if (!mounted) return;
          if (found.isNotEmpty) {
            setState(() {
              _tracks![i] = MatchedTrack(
                display: t.display,
                candidates: found,
                references: [t.display],
                relevance: 1,
              );
            });
          }
        } catch (_) {}
        if (mounted) setState(() => _matching--);
      }
    }

    await Future.wait([worker(), worker(), worker()]);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reference;
    final tracks = _tracks;
    final p = context.palette;
    final playableCount = tracks?.where((t) => t.isPlayable).length ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(r.album, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: _failed
          ? EmptyState(
              icon: Icons.album_rounded,
              title: 'Couldn’t load this album',
              actionLabel: 'Try again',
              onAction: _load,
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      ArtworkImage(imageUrl: r.coverUrl, size: 132, borderRadius: 16, seed: r.album),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.album, style: context.text.titleLarge, maxLines: 3),
                            const SizedBox(height: 4),
                            Text(r.artist, style: context.text.bodyMedium),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Play'),
                              onPressed: playableCount == 0
                                  ? null
                                  : () => ref.read(playerControllerProvider.notifier).playMatched(
                                        tracks!,
                                        tracks.indexWhere((t) => t.isPlayable),
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_matching > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Text('Finding authorised streams… ($_matching left)',
                            style: context.text.bodySmall?.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                if (tracks == null)
                  const SongTileSkeletonList()
                else
                  for (var i = 0; i < tracks.length; i++)
                    SongTile(
                      song: tracks[i].display,
                      track: tracks[i],
                      leadingIndex: i,
                      onTap: () => ref.read(playerControllerProvider.notifier).playMatched(tracks, i),
                    ),
                if (tracks != null && r.sourceId == 'itunes')
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Album information from Apple. Tracks marked “Not streamable” are not offered by '
                      'any service this app is licensed to stream.',
                      style: context.text.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}
