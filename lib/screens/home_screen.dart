import 'dart:async';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../controllers/player_controller.dart';
import '../models/song.dart';
import '../providers/player_provider.dart';
import '../providers/player_stream_providers.dart';
import '../services/hive_storage_service.dart';
import '../theme/app_layout.dart';
import '../theme/aurora_theme.dart';
import '../utils/haptics.dart';
import '../utils/player_navigation.dart';
import '../widgets/premium/song_card.dart';
import '../widgets/premium/empty_placeholder.dart';
import '../widgets/premium/staggered_entrance.dart';

/// Premium home screen: greeting + hero + horizontal carousels.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  bool _searchDebouncePending = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _query = value;
        _searchDebouncePending = false;
      });
      ref.read(playerControllerProvider.notifier).searchSongs('');
      return;
    }

    setState(() {
      _query = value;
      _searchDebouncePending = true;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() {
        _searchDebouncePending = false;
      });
      await ref.read(playerControllerProvider.notifier).searchSongs(trimmed);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: AuroraTheme.deepSpace,
      appBar: _HomeAppBar(
        searchController: _searchController,
        onSearchChanged: _onSearchChanged,
        query: _query,
        debouncePending: _searchDebouncePending,
      ),
      body: SafeArea(
        top: false,
        child: _query.trim().isNotEmpty
            ? _SearchResultsBody(
                query: _query,
                debouncePending: _searchDebouncePending,
              )
            : const _PremiumHomeBody(),
      ),
    );
  }
}

// ─── Home AppBar: greeting + search ─────────────────────────────────────────

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.query,
    required this.debouncePending,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String query;
  final bool debouncePending;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      getGreeting(),
                      style: AuroraTheme.greetingText,
                    ),
                    const _ProfileAvatar(),
                  ],
                ),
                const SizedBox(height: 14),
                _SearchField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  query: query,
                  debouncePending: debouncePending,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 94);
}

class _SearchField extends ConsumerWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.query,
    required this.debouncePending,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String query;
  final bool debouncePending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchLoading = ref.watch(isSearchLoadingProvider);
    final showSpinner = debouncePending || searchLoading;

    return TextField(
      controller: controller,
      style: const TextStyle(color: AuroraTheme.textPrimary),
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search songs, artists...',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : _SearchTrailing(
                showSpinner: showSpinner,
                onClear: () {
                  AppHaptics.selection();
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: AuroraTheme.surfaceElevated.withValues(alpha: 0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SearchTrailing extends StatelessWidget {
  const _SearchTrailing({
    required this.showSpinner,
    required this.onClear,
  });

  final bool showSpinner;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSpinner)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        IconButton(
          tooltip: 'Clear',
          onPressed: onClear,
          icon: Icon(
            Icons.close_rounded,
            color: AuroraTheme.textSecondary,
            size: 18,
          ),
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AuroraTheme.playButtonGlow,
      ),
      child: const Center(
        child: Icon(Icons.person_rounded, size: 20, color: Colors.white),
      ),
    );
  }
}

// ─── Premium Home Body ───────────────────────────────────────────────────

class _PremiumHomeBody extends ConsumerWidget {
  const _PremiumHomeBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final favorites = ref.watch(favoritesProvider);
    final libraryLoading = ref.watch(
      playerControllerProvider.select((s) => s.isLibraryLoading),
    );
    final queue = ref.watch(queueProvider);

    return ValueListenableBuilder<Box<Song>>(
      valueListenable: HiveStorageService.songsListenable(),
      builder: (context, box, _) {
        final allSongs = box.values.toList(growable: false);

        if (libraryLoading && allSongs.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white70),
          );
        }

        if (allSongs.isEmpty) {
          return const EmptyLibraryPlaceholder(
            icon: Icons.library_music_outlined,
            message: 'No songs available yet.',
            subtitle:
                'Search for music to get started, or try trending tracks '
                'from Audius.',
          );
        }

        final recent = _recentFromQueue(allSongs, queue, currentSong);
        final recentIds = recent.map((s) => s.id).toSet();
        final discover = [
          for (final s in allSongs)
            if (!recentIds.contains(s.id)) s,
        ];

        final madeForYou = [
          for (var i = 0; i < allSongs.length; i++)
            if (i % 3 == 0) allSongs[i],
        ].take(10).toList(growable: false);

        final trending = allSongs.take(12).toList(growable: false);

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _HeroSection(
                songs: allSongs,
                currentSong: currentSong,
                isPlaying: isPlaying,
                controller: controller,
                favorites: favorites,
              ),
            ),

            if (recent.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Recently Played'),
              ),
              SliverToBoxAdapter(
                child: _RecentCarousel(
                  songs: recent,
                  currentSong: currentSong,
                  isPlaying: isPlaying,
                  controller: controller,
                ),
              ),
            ],

            if (discover.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Quick Picks'),
              ),
              _QuickPicksSliver(
                songs: discover,
                currentSong: currentSong,
                isPlaying: isPlaying,
                favorites: favorites,
                controller: controller,
              ),
            ],

            if (madeForYou.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Made For You'),
              ),
              SliverToBoxAdapter(
                child: _HorizontalCarousel(
                  songs: madeForYou,
                  currentSong: currentSong,
                  isPlaying: isPlaying,
                  controller: controller,
                ),
              ),
            ],

            if (trending.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: _SectionHeader(title: 'Trending Now'),
              ),
              SliverToBoxAdapter(
                child: _TrendingList(
                  songs: trending,
                  currentSong: currentSong,
                  isPlaying: isPlaying,
                  favorites: favorites,
                  controller: controller,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: currentSong != null
                      ? AppLayout.contentBottomInsetWhenPlaying + 10
                      : 32,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

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
    for (final s in queue.reversed) {
      if (seen.add(s.id)) out.add(s);
      if (out.length >= 12) break;
    }
    if (out.length < 4) {
      for (final s in catalog) {
        if (seen.add(s.id)) out.add(s);
        if (out.length >= 12) break;
      }
    }
    return out;
  }
}

// ─── Search Results Body ─────────────────────────────────────────────────

class _SearchResultsBody extends ConsumerWidget {
  const _SearchResultsBody({
    required this.query,
    required this.debouncePending,
  });

  final String query;
  final bool debouncePending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResults = ref.watch(searchResultsProvider);
    final isSearchLoading = ref.watch(isSearchLoadingProvider);
    final searchPending = debouncePending || isSearchLoading;
    final q = query.trim();

    if (q.isEmpty) return const _PremiumHomeBody();

    final controller = ref.read(playerControllerProvider.notifier);
    final searchError = ref.watch(searchErrorProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final favorites = ref.watch(favoritesProvider);

    if (searchPending && searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchError != null && searchResults.isEmpty && !searchPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AuroraTheme.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                searchError,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  color: AuroraTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => controller.searchSongs(q),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (searchResults.isEmpty) {
      return const EmptyLibraryPlaceholder(
        icon: Icons.search_off,
        message: 'No results found.',
        subtitle: 'Try a different search term.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: searchResults.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = searchResults[index];
        return Consumer(
          builder: (context, ref, _) {
            final isCurrent = ref.watch(
              currentSongProvider.select((s) => s?.id == song.id),
            );
            return PremiumDiscoverSongRow(
              song: song,
              isCurrent: isCurrent,
              isPlaying: isPlaying,
              isFavorite: favorites.contains(song.id),
              onFavorite: () => controller.toggleFavorite(song),
              onPlay: () async {
                controller.playPlaylist(searchResults, startIndex: index);
                if (!context.mounted) return;
                await pushPlayerScreen(context);
              },
            );
          },
        );
      },
    );
  }
}

// ─── Section Header ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Text(title, style: AuroraTheme.sectionTitleText),
    );
  }
}

// ─── Hero Section ─────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({
    required this.songs,
    required this.currentSong,
    required this.isPlaying,
    required this.controller,
    required this.favorites,
  });

  final List<Song> songs;
  final Song? currentSong;
  final bool isPlaying;
  final PlayerController controller;
  final Set<String> favorites;

  @override
  Widget build(BuildContext context) {
    final featured = currentSong ?? (songs.isNotEmpty ? songs[0] : null);
    if (featured == null) return const SizedBox.shrink();

    final displayIndex = songs.indexWhere((s) => s.id == featured.id);
    final playIndex = displayIndex >= 0 ? displayIndex : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Hero(
        tag: 'cover-${featured.id}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppLayout.cardRadiusLarge),
          child: SizedBox(
            height: AppLayout.heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppLayout.cardRadiusLarge),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: CachedNetworkImage(
                      imageUrl: featured.coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const DecoratedBox(
                        decoration: BoxDecoration(
                          color: AuroraTheme.surfaceElevated,
                        ),
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      AppLayout.cardRadiusLarge,
                    ),
                    gradient: AuroraTheme.heroOverlayGradient,
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Chip(
                        text: currentSong == null ? 'Featured' : 'Now Playing',
                      ),
                      const SizedBox(height: 10),
                      Text(
                        featured.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.heroTitleText,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        featured.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AuroraTheme.heroSubText,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HeroPlayButton(
                            isPlaying:
                                isPlaying && currentSong?.id == featured.id,
                            onTap: () async {
                              if (currentSong?.id == featured.id) {
                                if (!isPlaying) controller.resume();
                              } else {
                                controller.playPlaylist(
                                  songs,
                                  startIndex: playIndex,
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: () => controller.toggleFavorite(featured),
                            child: Icon(
                              favorites.contains(featured.id)
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: favorites.contains(featured.id)
                                  ? Colors.pinkAccent.shade100
                                  : Colors.white.withValues(alpha: 0.7),
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.9),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _HeroPlayButton extends StatefulWidget {
  const _HeroPlayButton({
    required this.isPlaying,
    required this.onTap,
  });

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  State<_HeroPlayButton> createState() => _HeroPlayButtonState();
}

class _HeroPlayButtonState extends State<_HeroPlayButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
          AppHaptics.medium();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AuroraTheme.playButtonGlow,
            boxShadow: [
              BoxShadow(
                color: AuroraTheme.auroraViolet.withValues(alpha: 0.4),
                blurRadius: 20,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              widget.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              key: ValueKey(widget.isPlaying),
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Horizontal Carousel ─────────────────────────────────────────────────

class _HorizontalCarousel extends StatelessWidget {
  const _HorizontalCarousel({
    required this.songs,
    required this.currentSong,
    required this.isPlaying,
    required this.controller,
  });

  final List<Song> songs;
  final Song? currentSong;
  final bool isPlaying;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayout.cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final song = songs[i];
          final isCurrent = currentSong?.id == song.id;
          return StaggeredListEntrance(
            index: i,
            cap: 10,
            offsetY: 14,
            child: _PremiumCard(
              song: song,
              isCurrent: isCurrent,
              isPlaying: isPlaying,
              onTap: () async {
                final idx = songs.indexWhere((s) => s.id == song.id);
                if (isCurrent && !isPlaying) {
                  controller.resume();
                } else if (!isCurrent) {
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
    );
  }
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableCard(
      onTap: onTap,
      child: Container(
        width: AppLayout.cardWidth,
        height: AppLayout.cardHeight,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: AuroraTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(AppLayout.cardRadiusMedium),
          border: Border.all(
            color: isCurrent
                ? AuroraTheme.auroraBlue.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppLayout.cardRadiusSmall),
              child: CachedNetworkImage(
                imageUrl: song.coverUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                memCacheHeight: 300,
                filterQuality: FilterQuality.medium,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, url) => Container(
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.15),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.08),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: AuroraTheme.textTertiary,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AuroraTheme.cardTitleText,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AuroraTheme.cardArtistText,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recent Carousel ─────────────────────────────────────────────────────

class _RecentCarousel extends StatelessWidget {
  const _RecentCarousel({
    required this.songs,
    required this.currentSong,
    required this.isPlaying,
    required this.controller,
  });

  final List<Song> songs;
  final Song? currentSong;
  final bool isPlaying;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppLayout.cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final song = songs[i];
          final isCurrent = currentSong?.id == song.id;
          return StaggeredListEntrance(
            index: i,
            cap: 10,
            offsetY: 14,
            child: _PremiumRecentCard(
              song: song,
              isCurrent: isCurrent,
              isPlaying: isPlaying,
              onTap: () async {
                final idx = songs.indexWhere((s) => s.id == song.id);
                if (isCurrent && !isPlaying) {
                  controller.resume();
                } else if (!isCurrent) {
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
    );
  }
}

class _PremiumRecentCard extends StatelessWidget {
  const _PremiumRecentCard({
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
  });

  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressableCard(
      onTap: onTap,
      child: Container(
        width: AppLayout.recentCardWidth,
        height: AppLayout.cardHeight,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: AuroraTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(AppLayout.cardRadiusMedium),
          border: Border.all(
            color: isCurrent
                ? AuroraTheme.auroraBlue.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppLayout.cardRadiusMedium - 2),
              child: CachedNetworkImage(
                imageUrl: song.coverUrl,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                memCacheHeight: 300,
                filterQuality: FilterQuality.medium,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (context, url) => Container(
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.15),
                  child: const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Container(
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.08),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: AuroraTheme.textTertiary,
                    size: 32,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AuroraTheme.cardTitleText.copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AuroraTheme.cardArtistText,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick Picks Sliver ──────────────────────────────────────────────────

class _QuickPicksSliver extends StatelessWidget {
  const _QuickPicksSliver({
    required this.songs,
    required this.currentSong,
    required this.isPlaying,
    required this.favorites,
    required this.controller,
  });

  final List<Song> songs;
  final Song? currentSong;
  final bool isPlaying;
  final Set<String> favorites;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final song = songs[index];
            return PremiumDiscoverSongRow(
              song: song,
              isCurrent: currentSong?.id == song.id,
              isPlaying: isPlaying,
              isFavorite: favorites.contains(song.id),
              onFavorite: () => controller.toggleFavorite(song),
              onPlay: () async {
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
          childCount: songs.length.clamp(0, 10),
        ),
      ),
    );
  }
}

// ─── Trending List ───────────────────────────────────────────────────────

class _TrendingList extends StatelessWidget {
  const _TrendingList({
    required this.songs,
    required this.currentSong,
    required this.isPlaying,
    required this.favorites,
    required this.controller,
  });

  final List<Song> songs;
  final Song? currentSong;
  final bool isPlaying;
  final Set<String> favorites;
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        return Consumer(
          builder: (context, ref, child) {
            final isCurrent = ref.watch(
              currentSongProvider.select((s) => s?.id == song.id),
            );
            return _TrendingPill(
              rank: index + 1,
              song: song,
              isCurrent: isCurrent,
              isPlaying: isPlaying,
              isFavorite: favorites.contains(song.id),
              onFavorite: () => controller.toggleFavorite(song),
              onPlay: () async {
                if (isCurrent && !isPlaying) {
                  controller.resume();
                } else if (!isCurrent) {
                  controller.playPlaylist(songs, startIndex: index);
                } else {
                  controller.resume();
                }
                if (!context.mounted) return;
                await pushPlayerScreen(context);
              },
            );
          },
        );
      },
    );
  }
}

class _TrendingPill extends StatelessWidget {
  const _TrendingPill({
    required this.rank,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    required this.isFavorite,
    required this.onFavorite,
    required this.onPlay,
  });

  final int rank;
  final Song song;
  final bool isCurrent;
  final bool isPlaying;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return _PressableCard(
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: rank <= 3
                      ? AuroraTheme.auroraBlue
                      : AuroraTheme.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: song.coverUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                memCacheWidth: 100,
                memCacheHeight: 100,
                fadeInDuration: const Duration(milliseconds: 160),
                placeholder: (context, url) => Container(
                  width: 48,
                  height: 48,
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.1),
                ),
                errorWidget: (_, _, _) => Container(
                  width: 48,
                  height: 48,
                  color: AuroraTheme.textTertiary.withValues(alpha: 0.08),
                  child: const Icon(
                    Icons.music_note_rounded,
                    color: AuroraTheme.textTertiary,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isCurrent
                          ? AuroraTheme.auroraBlue
                          : AuroraTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuroraTheme.cardArtistText,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onFavorite,
              child: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 20,
                color: isFavorite
                    ? Colors.pinkAccent.shade100
                    : AuroraTheme.textTertiary,
              ),
            ),
            const SizedBox(width: 8),
            if (isCurrent)
              Icon(
                isPlaying
                    ? Icons.graphic_eq_rounded
                    : Icons.music_note_rounded,
                size: 18,
                color: AuroraTheme.auroraBlue,
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Pressable Card ──────────────────────────────────────────────────────

class _PressableCard extends StatefulWidget {
  const _PressableCard({
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<_PressableCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.96 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: GestureDetector(
        onTapDown: (_) {
          setState(() => _pressed = true);
          AppHaptics.light();
        },
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      ),
    );
  }
}
