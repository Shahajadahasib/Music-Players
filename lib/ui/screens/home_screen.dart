import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../config/app_config.dart';
import '../../licensing/license_controller.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/aurora_theme.dart';
import '../app_shell.dart';
import '../navigation.dart';
import '../widgets/artwork_image.dart';
import '../widgets/common.dart';
import '../widgets/pressable_scale.dart';
import '../widgets/song_actions.dart';
import '../widgets/song_tile.dart';
import '../widgets/staggered_entrance.dart';

/// Real featured tracks from every enabled source (Audius trending, …).
final featuredProvider = FutureProvider<List<Song>>((ref) async {
  ref.watch(enabledSourcesProvider);
  return ref.read(searchAggregatorProvider).featured(limit: 30);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final featured = ref.watch(featuredProvider);
    final p = context.palette;
    final isPremium = ref.watch(isPremiumProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(featuredProvider.future),
        child: CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppConfig.appName.toUpperCase(),
                                style: context.text.labelSmall?.copyWith(color: p.accent)),
                            const SizedBox(height: 4),
                            Semantics(
                              header: true,
                              child: Text(getGreeting(), style: context.text.headlineMedium),
                            ),
                          ],
                        ),
                      ),
                      if (!isPremium && !AppConfig.isPaidUpfront)
                        PressableScale(
                          onTap: () => openPremium(context),
                          borderRadius: BorderRadius.circular(8),
                          child: const PremiumChip(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: _RecentlyPlayedSection()),
            SliverToBoxAdapter(
              child: SectionHeader(
                'Trending now',
                subtitle: 'Full tracks from independent artists',
                action: featured.valueOrNull?.isNotEmpty == true ? 'Play all' : null,
                onAction: () {
                  final songs = featured.valueOrNull ?? const [];
                  ref.read(playerControllerProvider.notifier).playPlaylist(songs);
                },
              ),
            ),
            ...featured.when(
              loading: () => [const SliverToBoxAdapter(child: SongTileSkeletonList(count: 6))],
              error: (_, _) => [_errorSliver(ref)],
              data: (songs) => songs.isEmpty
                  ? [_errorSliver(ref)]
                  : [
                      SliverList.builder(
                        itemCount: songs.length.clamp(0, 10),
                        itemBuilder: (context, i) => StaggeredListEntrance(
                          index: i,
                          child: SongTile(
                            song: songs[i],
                            leadingIndex: i,
                            onTap: () => ref
                                .read(playerControllerProvider.notifier)
                                .playPlaylist(songs, startIndex: i),
                          ),
                        ),
                      ),
                      if (songs.length > 10) ...[
                        const SliverToBoxAdapter(child: SectionHeader('More to discover')),
                        SliverToBoxAdapter(child: _CardCarousel(songs: songs.sublist(10))),
                      ],
                    ],
            ),
            const SliverToBoxAdapter(child: _FavouritesSection()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Text(
                  'Streams are provided by the services shown on each track. '
                  'Trending tracks are streamed via Audius.',
                  style: context.text.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorSliver(WidgetRef ref) => SliverToBoxAdapter(
        child: EmptyState(
          icon: Icons.wifi_off_rounded,
          title: 'Can’t reach the music services',
          message: 'Check your connection. Your library and files on this device still work.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(featuredProvider),
        ),
      );
}

class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<Box<Map<dynamic, dynamic>>>(
      valueListenable: HiveStorageService.historyListenable(),
      builder: (context, _, _) {
        final recent = HiveStorageService.getRecentlyPlayed(limit: 12);
        if (recent.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _WelcomeCard(),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader('Jump back in'),
            _CardCarousel(songs: recent),
          ],
        );
      },
    );
  }
}

class _FavouritesSection extends ConsumerWidget {
  const _FavouritesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(playerControllerProvider.select((s) => s.favorites));
    final songs = [
      for (final id in ids) ?HiveStorageService.getSongById(id),
    ].reversed.toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Your favourites'),
        _CardCarousel(songs: songs.take(15).toList()),
      ],
    );
  }
}

class _WelcomeCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accent.withValues(alpha: 0.9), p.accentAlt.withValues(alpha: 0.85), p.accentWarm.withValues(alpha: 0.8)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Find any song',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Search once — we check every connected music service and play the best authorised source.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), height: 1.35),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: p.accent),
            onPressed: () => ref.read(shellTabProvider.notifier).state = 1,
            child: const Text('Start searching'),
          ),
        ],
      ),
    );
  }
}

class _CardCarousel extends ConsumerWidget {
  const _CardCarousel({required this.songs});
  final List<Song> songs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final s = songs[i];
          return SizedBox(
            width: 148,
            child: PressableScale(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref.read(playerControllerProvider.notifier).playPlaylist(songs, startIndex: i),
              child: GestureDetector(
                onLongPress: () => showSongActions(context, ref, s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ArtworkImage(imageUrl: s.coverUrl, size: 148, borderRadius: 14, seed: s.title),
                    const SizedBox(height: 8),
                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium?.copyWith(fontSize: 14)),
                    Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
