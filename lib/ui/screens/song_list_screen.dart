import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/aurora_theme.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';
import 'library_screen.dart';

enum _Kind { favourites, history, local }

/// Favourites, history and on-device files share one list screen.
class SongListScreen extends ConsumerWidget {
  const SongListScreen._(this._kind);

  factory SongListScreen.favourites() => const SongListScreen._(_Kind.favourites);
  factory SongListScreen.history() => const SongListScreen._(_Kind.history);
  factory SongListScreen.local() => const SongListScreen._(_Kind.local);

  final _Kind _kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = switch (_kind) {
      _Kind.favourites => 'Favourites',
      _Kind.history => 'Recently played',
      _Kind.local => 'On this device',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_kind == _Kind.local)
            IconButton(
              tooltip: 'Add files',
              icon: const Icon(Icons.add_rounded),
              onPressed: () => importLocalMusic(context, ref),
            ),
          if (_kind == _Kind.history)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Clear listening history?'),
                    content: const Text('This removes your recently played list from this device.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Clear')),
                    ],
                  ),
                );
                if (ok == true) await HiveStorageService.clearHistory();
              },
            ),
        ],
      ),
      body: switch (_kind) {
        _Kind.history => ValueListenableBuilder<Box<Map<dynamic, dynamic>>>(
            valueListenable: HiveStorageService.historyListenable(),
            builder: (context, _, _) {
              final entries = HiveStorageService.getHistory(limit: 200);
              return _list(
                context,
                ref,
                [for (final e in entries) e.song],
                subtitles: [for (final e in entries) '${e.song.artist} · ${_ago(e.playedAt)}'],
                empty: const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Nothing played yet',
                  message: 'Songs you play appear here.',
                ),
              );
            },
          ),
        _Kind.favourites => Builder(builder: (context) {
            final ids = ref.watch(playerControllerProvider.select((s) => s.favorites));
            final songs = [for (final id in ids) ?HiveStorageService.getSongById(id)].reversed.toList();
            return _list(
              context,
              ref,
              songs,
              empty: const EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No favourites yet',
                message: 'Tap the heart on any song to save it here.',
              ),
            );
          }),
        _Kind.local => ValueListenableBuilder<Box<Song>>(
            valueListenable: HiveStorageService.songsListenable(),
            builder: (context, _, _) => _list(
              context,
              ref,
              localSongs(ref),
              empty: EmptyState(
                icon: Icons.audio_file_rounded,
                title: 'No local files',
                message: 'Add MP3, AAC, M4A, WAV or FLAC files you own.',
                actionLabel: 'Add files',
                onAction: () => importLocalMusic(context, ref),
              ),
            ),
          ),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<Song> songs, {
    List<String>? subtitles,
    required Widget empty,
  }) {
    if (songs.isEmpty) return empty;
    final controller = ref.read(playerControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
                onPressed: () => controller.playPlaylist(songs),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.shuffle_rounded),
                label: const Text('Shuffle'),
                onPressed: () async {
                  final shuffled = [...songs]..shuffle();
                  await controller.playPlaylist(shuffled);
                },
              ),
              const Spacer(),
              Text('${songs.length} songs', style: context.text.bodySmall),
            ],
          ),
        ),
        for (var i = 0; i < songs.length; i++)
          SongTile(
            song: songs[i],
            subtitle: subtitles?[i],
            onTap: () => controller.playPlaylist(songs, startIndex: i),
          ),
      ],
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 7) return '${d.inDays} d ago';
    return '${t.day}/${t.month}/${t.year}';
  }
}
