import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_provider.dart';
import '../../theme/aurora_theme.dart';
import '../widgets/artwork_image.dart';
import '../widgets/common.dart';

Future<void> showQueueSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(heightFactor: 0.85, child: _QueueSheet()),
    );

/// Queue editor: jump, remove (swipe), reorder (drag, when shuffle is off).
class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerControllerProvider);
    final c = ref.read(playerControllerProvider.notifier);
    final current = state.currentSong;
    final upNext = state.upNext;
    final p = context.palette;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Queue', style: context.text.titleLarge)),
              if (state.isShuffle)
                Text('Shuffle on — drag to reorder is off', style: context.text.bodySmall),
            ],
          ),
        ),
        if (current != null)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: ArtworkImage(imageUrl: current.coverUrl, size: 48, seed: current.title),
            title: Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
            subtitle: Text(current.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: NowPlayingBars(playing: state.isPlaying),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('UP NEXT', style: context.text.labelSmall?.copyWith(color: p.textTertiary)),
          ),
        ),
        Expanded(
          child: upNext.isEmpty
              ? const EmptyState(
                  icon: Icons.queue_music_rounded,
                  title: 'Nothing queued',
                  message: 'Use “Play next” or “Add to queue” on any song.',
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: upNext.length,
                  onReorderItem: (from, to) {
                    if (state.isShuffle) return;
                    unawaited(c.moveInQueue(upNext[from].index, upNext[to].index));
                  },
                  itemBuilder: (context, i) {
                    final item = upNext[i];
                    return Dismissible(
                      key: ValueKey('${item.song.id}-${item.index}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: p.danger.withValues(alpha: 0.85),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_rounded, color: Colors.white),
                      ),
                      onDismissed: (_) => c.removeFromQueue(item.index),
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 20, right: 8),
                        leading: ArtworkImage(imageUrl: item.song.coverUrl, size: 44, seed: item.song.title),
                        title: Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(item.song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => c.jumpTo(item.index),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Remove from queue',
                              icon: const Icon(Icons.remove_circle_outline_rounded),
                              onPressed: () => c.removeFromQueue(item.index),
                            ),
                            if (!state.isShuffle)
                              ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle_rounded, semanticLabel: 'Reorder'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  final c = ref.read(playerControllerProvider.notifier);
  final state = ref.read(playerControllerProvider);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheet) {
      void pick(Duration d) {
        c.setSleepTimer(d);
        Navigator.pop(sheet);
      }

      final ends = state.sleepTimerEndsAt;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Sleep timer', style: sheet.text.titleLarge)),
                  if (ends != null)
                    Text(
                      'Stops at ${TimeOfDay.fromDateTime(ends).format(sheet)}',
                      style: sheet.text.bodySmall,
                    ),
                  if (state.sleepAtEndOfTrack) Text('Stops after this song', style: sheet.text.bodySmall),
                ],
              ),
            ),
            for (final m in const [5, 15, 30, 45, 60, 90])
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: Text(m < 60 ? '$m minutes' : '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${m % 60} min'}'),
                onTap: () => pick(Duration(minutes: m)),
              ),
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: const Text('End of this song'),
              onTap: () {
                c.setSleepAtEndOfTrack();
                Navigator.pop(sheet);
              },
            ),
            if (state.sleepTimerActive)
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Turn off timer'),
                onTap: () {
                  c.cancelSleepTimer();
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      );
    },
  );
}
