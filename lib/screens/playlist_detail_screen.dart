import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_layout.dart';
import '../theme/aurora_theme.dart';
import '../utils/player_navigation.dart';
import '../widgets/song_list_tile.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final favorites = ref.watch(favoritesProvider);

    return ValueListenableBuilder<Box<Playlist>>(
      valueListenable: HiveStorageService.playlistsListenable(),
      builder: (context, box, _) {
        final current = box.get(playlist.id) ?? playlist;
        final songs = current.songIds
            .map(HiveStorageService.getSongById)
            .whereType<Song>()
            .toList(growable: false);

        return Scaffold(
          backgroundColor: AuroraTheme.deepSpace,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: AuroraTheme.textPrimary,
            title: Text(current.name),
            actions: [
              if (songs.isNotEmpty)
                IconButton(
                  tooltip: 'Play all',
                  onPressed: () async {
                    controller.playPlaylist(songs);
                    if (!context.mounted) return;
                    await pushPlayerScreen(context);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
            ],
          ),
          body: songs.isEmpty
              ? const _PlaylistEmptyState()
              : ListView.separated(
                  padding: EdgeInsets.only(
                    top: 8,
                    bottom: currentSong == null
                        ? 0
                        : AppLayout.contentBottomInsetWhenPlaying,
                  ),
                  itemCount: songs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongListTile(
                      song: song,
                      isCurrentSong: currentSong?.id == song.id,
                      isPlaying: isPlaying,
                      isFavorite: favorites.contains(song.id),
                      onFavorite: () => controller.toggleFavorite(song),
                      onTap: () async {
                        if (currentSong?.id == song.id) {
                          if (!isPlaying) controller.resume();
                        } else {
                          controller.playPlaylist(songs, startIndex: index);
                        }
                        if (!context.mounted) return;
                        await pushPlayerScreen(context);
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

class _PlaylistEmptyState extends StatelessWidget {
  const _PlaylistEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_outlined,
              size: 48,
              color: AuroraTheme.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No songs yet.\nAdd songs from the Player screen.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AuroraTheme.textSecondary,
                fontSize: 15,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
