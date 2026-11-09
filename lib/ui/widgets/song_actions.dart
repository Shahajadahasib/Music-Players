import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_config.dart';
import '../../licensing/license_controller.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../search/matched_track.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import 'artwork_image.dart';
import 'common.dart';
import 'new_playlist_dialog.dart';

/// Bottom sheet with every action for a song. Only real, working actions are
/// shown — e.g. "Go to album" only appears when the provider has album pages.
Future<void> showSongActions(
  BuildContext context,
  WidgetRef ref,
  Song song, {
  MatchedTrack? track,
  String? playlistId,
}) {
  final controller = ref.read(playerControllerProvider.notifier);
  final isFav = ref.read(playerControllerProvider).favorites.contains(song.id);
  final display = track?.display ?? song;
  final source = ref.read(sourceByIdProvider(display.sourceId));
  final playable = track?.isPlayable ?? song.canPlay;
  final link = track?.externalUrl ?? song.externalUrl;
  final canBeResolved = !playable && !song.isLocal;

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final p = sheetContext.palette;
      void close() => Navigator.of(sheetContext).pop();
      final target = track?.best ?? song;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    ArtworkImage(imageUrl: display.coverUrl, size: 56, seed: display.title),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(display.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: sheetContext.text.titleMedium),
                          const SizedBox(height: 2),
                          Text(display.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: sheetContext.text.bodyMedium),
                          const SizedBox(height: 6),
                          track != null
                              ? AvailabilityBadge.forTrack(track)
                              : AvailabilityBadge(playability: song.playability),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              if (playable || canBeResolved) ...[
                ListTile(
                  leading: const Icon(Icons.queue_play_next_rounded),
                  title: const Text('Play next'),
                  onTap: () {
                    close();
                    controller.playNext(target);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_to_queue_rounded),
                  title: const Text('Add to queue'),
                  onTap: () {
                    close();
                    controller.addToQueue(target);
                  },
                ),
              ],
              if (playable || song.isLocal)
                ListTile(
                  leading: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: isFav ? p.accentWarm : null),
                  title: Text(isFav ? 'Remove from favourites' : 'Add to favourites'),
                  onTap: () {
                    close();
                    controller.toggleFavorite(target);
                  },
                ),
              if (playable || song.isLocal)
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded),
                  title: const Text('Add to playlist'),
                  onTap: () {
                    close();
                    showAddToPlaylist(context, ref, target);
                  },
                ),
              if (playlistId != null)
                ListTile(
                  leading: const Icon(Icons.playlist_remove_rounded),
                  title: const Text('Remove from this playlist'),
                  onTap: () {
                    close();
                    controller.removeFromPlaylist(song: song, playlistId: playlistId);
                  },
                ),
              if (display.artist.isNotEmpty && !song.isLocal)
                ListTile(
                  leading: const Icon(Icons.person_rounded),
                  title: Text('Go to ${display.artist}'),
                  onTap: () {
                    close();
                    pushPage(context, ArtistScreen(name: display.artist, sourceId: display.sourceId, artistId: display.artistId));
                  },
                ),
              if (display.albumId.isNotEmpty && source != null && display.album.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.album_rounded),
                  title: Text('Go to album “${display.album}”'),
                  onTap: () {
                    close();
                    pushPage(context, AlbumScreen(reference: display));
                  },
                ),
              if (link.startsWith('https://'))
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: Text(display.sourceId == 'itunes'
                      ? 'Open in Apple Music'
                      : 'Open on ${source?.info.displayName ?? 'provider'}'),
                  onTap: () {
                    close();
                    openExternal(context, link);
                  },
                ),
              if (source != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                  child: Text(
                    [
                      source.info.attribution,
                      if (target.license.isNotEmpty) 'Licence: ${target.license}',
                    ].join(' · '),
                    style: sheetContext.text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Pick (or create) a playlist; respects the free-tier playlist limit.
Future<void> showAddToPlaylist(BuildContext context, WidgetRef ref, Song song) async {
  final controller = ref.read(playerControllerProvider.notifier);
  final playlists = HiveStorageService.getAllPlaylists();
  final picked = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Add to playlist', style: sheet.text.titleLarge),
          ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            onTap: () => Navigator.pop(sheet, '__new__'),
          ),
          for (final pl in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(pl.name),
              subtitle: Text('${pl.songIds.length} songs'),
              onTap: () => Navigator.pop(sheet, pl.id),
            ),
        ],
      ),
    ),
  );
  if (picked == null || !context.mounted) return;
  var id = picked;
  if (picked == '__new__') {
    final created = await createPlaylistFlow(context, ref);
    if (created == null) return;
    id = created;
  }
  await controller.addToPlaylist(song, id);
}

/// Name dialog + free-tier limit check. Returns the new playlist id.
Future<String?> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final count = HiveStorageService.getAllPlaylists().length;
  if (count >= AppConfig.freePlaylistLimit &&
      !requirePremium(context, ref, PremiumFeature.unlimitedPlaylists)) {
    return null;
  }
  final name = await showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => const NewPlaylistDialog(),
  );
  if (name == null || name.trim().isEmpty) return null;
  return ref.read(playerControllerProvider.notifier).createPlaylist(name);
}
