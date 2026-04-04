import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_layout.dart';
import '../theme/aurora_theme.dart';
import '../utils/player_navigation.dart';
import '../widgets/song_list_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  List<Song> _filter(List<Song> songs) {
    if (_query.isEmpty) return songs;
    final q = _query.toLowerCase();
    return songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(playerControllerProvider.notifier);
    final hasCurrentSong = ref.watch(
      currentSongProvider.select((s) => s != null),
    );
    final isPlaying = ref.watch(isPlayingProvider);
    final favorites = ref.watch(favoritesProvider);

    final allSongs = HiveStorageService.getAllSongs();
    final results = _filter(allSongs);

    return Scaffold(
      backgroundColor: AuroraTheme.deepSpace,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        title: Container(
          height: 44,
          decoration: BoxDecoration(
            color: AuroraTheme.surfaceElevated.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: TextField(
            controller: _textController,
            autofocus: true,
            style: const TextStyle(color: AuroraTheme.textPrimary),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search songs or artists...',
              border: InputBorder.none,
              prefixIcon: const Icon(Icons.search, size: 20),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _textController.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _query.isEmpty
            ? const _SearchState(
                icon: Icons.search,
                message: 'Type to search songs or artists',
              )
            : results.isEmpty
                ? _SearchState(
                    icon: Icons.music_off,
                    message: 'No results for "$_query"',
                  )
                : ListView.separated(
                    key: ValueKey(_query),
                    padding: EdgeInsets.only(
                      top: 8,
                      bottom: hasCurrentSong
                          ? AppLayout.contentBottomInsetWhenPlaying
                          : 0,
                    ),
                    itemCount: results.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final song = results[index];
                      return Consumer(
                        builder: (context, ref, _) {
                          final isCurrentSong = ref.watch(
                            currentSongProvider.select(
                              (s) => s?.id == song.id,
                            ),
                          );
                          return SongListTile(
                            song: song,
                            isCurrentSong: isCurrentSong,
                            isPlaying: isPlaying,
                            isFavorite: favorites.contains(song.id),
                            onFavorite: () => controller.toggleFavorite(song),
                            onTap: () async {
                              if (isCurrentSong) {
                                if (!isPlaying) controller.resume();
                              } else {
                                controller.playPlaylist(
                                  results,
                                  startIndex: index,
                                );
                              }
                              if (!context.mounted) return;
                              await pushPlayerScreen(context);
                            },
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

class _SearchState extends StatelessWidget {
  const _SearchState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AuroraTheme.textTertiary),
            const SizedBox(height: 12),
            Text(
              message,
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
