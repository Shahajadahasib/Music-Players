import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/player_stream_providers.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/app_layout.dart';
import '../../utils/player_navigation.dart';
import 'empty_placeholder.dart';
import 'song_card.dart';
import 'staggered_entrance.dart';

List<Song> _recentFromQueue(
  List<Song> catalog,
  List<Song> queue,
  Song? current,
) {
  final out = <Song>[];
  final seen = <String>{};
  if (current != null) {
    out.add(current);
    seen.add(current.id);
  }
  for (final s in queue) {
    if (seen.add(s.id)) out.add(s);
    if (out.length >= 14) break;
  }
  if (out.length < 6) {
    for (final s in catalog) {
      if (seen.add(s.id)) out.add(s);
      if (out.length >= 14) break;
    }
  }
  return out;
}

/// Premium “Discover” home: Recently played carousel + vertical catalog.
class PremiumDiscoverTab extends ConsumerWidget {
  const PremiumDiscoverTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final currentSong = ref.watch(currentSongProvider);
    final queue = ref.watch(queueProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final favorites = ref.watch(favoritesProvider);
    final libraryLoading = ref.watch(
      playerControllerProvider.select((s) => s.isLibraryLoading),
    );
    final hasCurrentSong = currentSong != null;

    return ValueListenableBuilder<Box<Song>>(
      valueListenable: HiveStorageService.songsListenable(),
      builder: (context, box, _) {
        final songs = box.values.toList(growable: false);
        if (libraryLoading && songs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          );
        }
        if (songs.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: hasCurrentSong
                  ? AppLayout.contentBottomInsetWhenPlaying
                  : 0,
            ),
            child: const EmptyLibraryPlaceholder(
              icon: Icons.library_music_outlined,
              message: 'No songs available yet.',
            ),
          );
        }

        final recent = _recentFromQueue(songs, queue, currentSong);
        final recentIds = recent.map((s) => s.id).toSet();
        final discover = [
          for (final s in songs)
            if (!recentIds.contains(s.id)) s,
        ];

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 0, 8),
                child: Text(
                  'Recently played',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 208,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  itemCount: recent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final song = recent[i];
                    final isCurrent = currentSong?.id == song.id;
                    return StaggeredListEntrance(
                      index: i,
                      cap: 12,
                      offsetY: 14,
                      child: PremiumRecentSongCard(
                        song: song,
                        heroTag: isCurrent ? 'cover-${song.id}' : null,
                        onTap: () async {
                          if (isCurrent && !isPlaying) {
                            controller.resume();
                          } else if (!isCurrent) {
                            final idx =
                                songs.indexWhere((s) => s.id == song.id);
                            controller.playPlaylist(
                              songs,
                              startIndex: idx >= 0 ? idx : 0,
                            );
                          } else {
                            controller.resume();
                          }
                          if (!context.mounted) return;
                          await pushPlayerScreen(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'You might like',
                      style:
                          Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                    ),
                    const Spacer(),
                    Text(
                      '${discover.length} tracks',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                    ),
                  ],
                ),
              ),
            ),
            if (discover.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Everything you have is in Recently played — pull to explore search for more.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          height: 1.4,
                        ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  hasCurrentSong
                      ? AppLayout.contentBottomInsetWhenPlaying
                      : 28,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = discover[index];
                      return Consumer(
                        builder: (context, ref, _) {
                          final isCurrent =
                              currentSong?.id == song.id;
                          return StaggeredListEntrance(
                            index: index,
                            child: PremiumDiscoverSongRow(
                              song: song,
                              isCurrent: isCurrent,
                              isPlaying: isPlaying,
                              isFavorite: favorites.contains(song.id),
                              onFavorite: () =>
                                  controller.toggleFavorite(song),
                              onPlay: () async {
                                if (isCurrent && !isPlaying) {
                                  controller.resume();
                                } else if (!isCurrent) {
                                  final idx =
                                      songs.indexWhere((s) => s.id == song.id);
                                  controller.playPlaylist(
                                    songs,
                                    startIndex: idx >= 0 ? idx : 0,
                                  );
                                } else {
                                  controller.pause();
                                }
                                if (!context.mounted) return;
                                await pushPlayerScreen(context);
                              },
                            ),
                          );
                        },
                      );
                    },
                    childCount: discover.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
