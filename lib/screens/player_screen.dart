import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/player_controller.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../services/hive_storage_service.dart';
import '../utils/haptics.dart';
import '../theme/aurora_theme.dart';
import '../widgets/new_playlist_dialog.dart';
import '../widgets/premium/now_playing_panel.dart';

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final song = ref.watch(currentSongProvider);
    final errorMessage = ref.watch(playerErrorMessageProvider);

    if (song == null) {
      return Scaffold(
        extendBodyBehindAppBar: false,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AuroraTheme.backgroundGradient,
          ),
          child: const SafeArea(
            top: false,
            bottom: true,
            child: Center(
              child: Text(
                'No song selected.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AuroraTheme.backgroundGradient,
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: NowPlayingPanel(
            onShowAddToPlaylist: (context, ref, s) {
              _showAddToPlaylistSheet(
                context,
                ref,
                ref.read(playerControllerProvider.notifier),
                s,
              );
            },
            errorBanner: errorMessage != null
                ? _ErrorBanner(
                    message: errorMessage,
                    onRetry: () => controller.retryPlayback(),
                    onDismiss: () => controller.clearError(),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

// ─── Error Banner ────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
              ),
            ),
            TextButton(
              onPressed: () {
                AppHaptics.light();
                onRetry();
              },
              child: const Text('Retry'),
            ),
            IconButton(
              onPressed: () {
                AppHaptics.selection();
                onDismiss();
              },
              icon: const Icon(Icons.close, size: 16, color: Colors.white70),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// ─── Add to Playlist ────────────────────────────────────────────────────────

void _showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  PlayerController controller,
  Song song,
) {
  ref.read(bottomSheetActiveProvider.notifier).state = true;

  showModalBottomSheet<void>(
    context: context,
    builder: (_) => _AddToPlaylistSheet(song: song, controller: controller),
  ).whenComplete(() {
    ref.read(bottomSheetActiveProvider.notifier).state = false;
  });
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({
    required this.song,
    required this.controller,
  });

  final Song song;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final playlists = HiveStorageService.getAllPlaylists();
    final itemCount =
        playlists.isEmpty ? 4 : 3 + playlists.length;

    return SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              key: const ValueKey<String>('sheet-title'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Add to Playlist',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            );
          }
          if (index == 1) {
            return const Divider(key: ValueKey<String>('sheet-div'), height: 1);
          }
          if (index == 2) {
            return ListTile(
              key: const ValueKey<String>('sheet-new-playlist'),
              leading: const Icon(Icons.add),
              title: const Text('New Playlist'),
              onTap: () async {
                final name = await showDialog<String?>(
                  context: context,
                  builder: (_) => const NewPlaylistDialog(),
                );

                if (!context.mounted) return;
                Navigator.pop(context);

                if (name != null && name.trim().isNotEmpty) {
                  final trimmed = name.trim();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    controller.createPlaylist(trimmed).then((id) {
                      if (id != null) {
                        controller.addToPlaylist(song, id);
                      }
                    });
                  });
                }
              },
            );
          }
          if (playlists.isEmpty) {
            return ListTile(
              key: const ValueKey<String>('sheet-empty-msg'),
              title: Text(
                'No playlists yet',
                style: TextStyle(color: Colors.white54),
              ),
            );
          }
          final playlist = playlists[index - 3];
          return ListTile(
            key: ValueKey<String>(playlist.id),
            leading: const Icon(Icons.queue_music),
            title: Text(playlist.name),
            subtitle: Text('${playlist.songIds.length} songs'),
            onTap: () {
              controller.addToPlaylist(song, playlist.id);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
