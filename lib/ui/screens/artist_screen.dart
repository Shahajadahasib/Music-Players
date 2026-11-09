import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../search/matched_track.dart';
import '../../search/track_matcher.dart';
import '../../theme/aurora_theme.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';

typedef ArtistKey = ({String name, String sourceId, String artistId});

/// Tracks by an artist: the provider's own artist feed (when we know the
/// provider artist id) merged with a cross-provider search filtered to tracks
/// whose artist really matches.
final artistTracksProvider =
    FutureProvider.autoDispose.family<List<MatchedTrack>, ArtistKey>((ref, key) async {
  final aggregator = ref.read(searchAggregatorProvider);
  const matcher = TrackMatcher();
  final out = <MatchedTrack>[];
  final seen = <String>{};

  final source = key.sourceId.isEmpty ? null : ref.read(sourceByIdProvider(key.sourceId));
  if (source != null && key.artistId.isNotEmpty) {
    try {
      for (final s in await source.artistTracks(key.artistId)) {
        if (seen.add(s.id)) {
          out.add(MatchedTrack(display: s, candidates: s.canPlay ? [s] : const [], relevance: 1));
        }
      }
    } catch (_) {/* fall back to search below */}
  }

  final result = await aggregator.search(key.name, perSource: 40);
  for (final t in result.tracks) {
    if (matcher.artistSimilarity(key.name, t.display.artist) < 0.85) continue;
    if (t.candidates.any((c) => seen.contains(c.id)) || !seen.add(t.display.id)) continue;
    out.add(t);
  }
  if (out.isEmpty && result.allSourcesFailed) {
    throw Exception('offline');
  }
  // Playable first, keep provider order otherwise.
  final playable = out.where((t) => t.isPlayable).toList();
  final rest = out.where((t) => !t.isPlayable).toList();
  return [...playable, ...rest];
});

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name, this.sourceId = '', this.artistId = ''});
  final String name;
  final String sourceId;
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final key = (name: name, sourceId: sourceId, artistId: artistId);
    final tracks = ref.watch(artistTracksProvider(key));
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: Container(
                decoration: BoxDecoration(gradient: p.ambient(p.accentAlt)),
                alignment: const Alignment(0, -0.1),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: p.brandGradient),
                  alignment: Alignment.center,
                  child: Text(initial,
                      style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
          ),
          ...tracks.when(
            loading: () => [const SliverToBoxAdapter(child: SongTileSkeletonList())],
            error: (_, _) => [
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Couldn’t load $name',
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(artistTracksProvider(key)),
                ),
              ),
            ],
            data: (list) => list.isEmpty
                ? [
                    const SliverToBoxAdapter(
                      child: EmptyState(icon: Icons.person_search_rounded, title: 'No tracks found for this artist'),
                    ),
                  ]
                : [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Row(
                          children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Play'),
                              onPressed: list.any((t) => t.isPlayable)
                                  ? () => ref.read(playerControllerProvider.notifier).playMatched(
                                        list,
                                        list.indexWhere((t) => t.isPlayable),
                                      )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Text('${list.where((t) => t.isPlayable).length} playable · ${list.length} tracks',
                                style: context.text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => SongTile(
                        song: list[i].display,
                        track: list[i],
                        onTap: () => ref.read(playerControllerProvider.notifier).playMatched(list, i),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
          ),
        ],
      ),
    );
  }
}

/// Helper so other files can build an artist key from a song.
ArtistKey artistKeyFor(Song s) => (name: s.artist, sourceId: s.sourceId, artistId: s.artistId);
