import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/aurora_theme.dart';
import '../widgets/artwork_image.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    return ValueListenableBuilder<Box<Playlist>>(
      valueListenable: HiveStorageService.playlistsListenable(),
      builder: (context, box, _) {
        final playlist = box.get(playlistId);
        if (playlist == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.queue_music_rounded, title: 'Playlist not found'),
          );
        }
        final songs = [for (final id in playlist.songIds) ?HiveStorageService.getSongById(id)];
        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Playlist options',
                onSelected: (v) async {
                  if (v == 'rename') {
                    final name = await _askName(context, playlist.name);
                    if (name != null) {
                      await controller.renamePlaylist(playlistId: playlistId, newName: name);
                    }
                  } else if (v == 'delete') {
                    final ok = await _confirmDelete(context, playlist.name);
                    if (ok && context.mounted) {
                      await controller.deletePlaylist(playlistId);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                ],
              ),
            ],
          ),
          body: songs.isEmpty
              ? const EmptyState(
                  icon: Icons.playlist_add_rounded,
                  title: 'This playlist is empty',
                  message: 'Use “Add to playlist” on any song to fill it.',
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  header: _Header(playlist: playlist, songs: songs),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: songs.length,
                  onReorderItem: (oldIndex, newIndex) {
                    controller.reorderPlaylistSongs(
                      playlistId: playlistId,
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                    );
                  },
                  itemBuilder: (context, i) => SongTile(
                    key: ValueKey('${songs[i].id}-$i'),
                    song: songs[i],
                    playlistId: playlistId,
                    onTap: () => controller.playPlaylist(songs, startIndex: i),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.drag_handle_rounded,
                            semanticLabel: 'Reorder', color: context.palette.textTertiary),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Future<String?> _askName(BuildContext context, String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(controller: c, autofocus: true, maxLength: 100),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Save')),
        ],
      ),
    ).whenComplete(c.dispose);
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Delete “$name”?'),
          content: const Text('The songs stay in your library.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
          ],
        ),
      ) ??
      false;
}

class _Header extends ConsumerWidget {
  const _Header({required this.playlist, required this.songs});
  final Playlist playlist;
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final total = songs.fold<Duration>(Duration.zero, (a, s) => a + (s.duration ?? Duration.zero));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          ArtworkImage(
            imageUrl: songs.first.coverUrl,
            size: 96,
            borderRadius: 14,
            seed: playlist.name,
            icon: Icons.queue_music_rounded,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${songs.length} songs · ${formatTrackDuration(total)}', style: context.text.bodySmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                      onPressed: () => controller.playPlaylist(songs),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Shuffle play',
                      icon: const Icon(Icons.shuffle_rounded),
                      onPressed: () => controller.playPlaylist([...songs]..shuffle()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
