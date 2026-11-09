import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/app_config.dart';
import '../../licensing/license_controller.dart';
import '../../models/playlist.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../services/hive_storage_service.dart';
import '../../services/local_music_service.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/song_actions.dart';
import 'playlist_screen.dart';
import 'song_list_screen.dart';

/// Web: imported local files live only for the session.
final webLocalSongsProvider = StateProvider<List<Song>>((ref) => const []);

List<Song> localSongs(WidgetRef ref) => kIsWeb
    ? ref.watch(webLocalSongsProvider)
    : HiveStorageService.getAllSongs().where((s) => s.isLocal).toList();

Future<void> importLocalMusic(BuildContext context, WidgetRef ref) async {
  if (!requirePremium(context, ref, PremiumFeature.localFiles)) return;
  try {
    final songs = await const LocalMusicService().pickAndImport();
    if (songs.isEmpty) return;
    if (kIsWeb) {
      final current = ref.read(webLocalSongsProvider);
      ref.read(webLocalSongsProvider.notifier).state = [
        ...current.where((c) => !songs.any((s) => s.id == c.id)),
        ...songs,
      ];
    } else {
      await HiveStorageService.saveSongs(songs);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${songs.length} file${songs.length == 1 ? '' : 's'}')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t import those files.')),
      );
    }
  }
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favCount = ref.watch(playerControllerProvider.select((s) => s.favorites.length));
    final isPremium = ref.watch(isPremiumProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: const Text('Your library')),
        actions: [
          IconButton(
            tooltip: 'New playlist',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => createPlaylistFlow(context, ref),
          ),
        ],
      ),
      body: ValueListenableBuilder<Box<Playlist>>(
        valueListenable: HiveStorageService.playlistsListenable(),
        builder: (context, box, _) {
          final playlists = HiveStorageService.getAllPlaylists();
          return ValueListenableBuilder<Box<Song>>(
            valueListenable: HiveStorageService.songsListenable(),
            builder: (context, _, _) {
              final local = localSongs(ref);
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _LibraryTile(
                    icon: Icons.favorite_rounded,
                    color: p.accentWarm,
                    title: 'Favourites',
                    subtitle: '$favCount songs',
                    onTap: () => pushPage(context, SongListScreen.favourites()),
                  ),
                  _LibraryTile(
                    icon: Icons.history_rounded,
                    color: p.accent,
                    title: 'Recently played',
                    subtitle: 'Your listening history',
                    onTap: () => pushPage(context, SongListScreen.history()),
                  ),
                  _LibraryTile(
                    icon: Icons.phone_iphone_rounded,
                    color: p.accentAlt,
                    title: 'On this device',
                    subtitle: local.isEmpty ? 'Play music files you own' : '${local.length} files',
                    trailing: isPremium ? null : const PremiumChip(),
                    onTap: () => local.isEmpty
                        ? importLocalMusic(context, ref)
                        : pushPage(context, SongListScreen.local()),
                  ),
                  SectionHeader(
                    'Playlists',
                    subtitle: isPremium || AppConfig.isPaidUpfront
                        ? null
                        : '${playlists.length}/${AppConfig.freePlaylistLimit} on the free plan',
                    action: 'New',
                    onAction: () => createPlaylistFlow(context, ref),
                  ),
                  if (playlists.isEmpty)
                    const EmptyState(
                      icon: Icons.queue_music_rounded,
                      title: 'No playlists yet',
                      message: 'Create one, or use “Add to playlist” on any song.',
                    )
                  else
                    for (final pl in playlists)
                      _LibraryTile(
                        icon: Icons.queue_music_rounded,
                        color: p.textSecondary,
                        title: pl.name,
                        subtitle: '${pl.songIds.length} songs',
                        onTap: () => pushPage(context, PlaylistScreen(playlistId: pl.id)),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: context.text.titleMedium),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
