import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../search/matched_track.dart';
import '../../search/text_normalizer.dart';
import '../../services/hive_storage_service.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';
import '../widgets/song_tile.dart';
import '../widgets/staggered_entrance.dart';
import 'artist_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  static const _recentKey = 'recentSearches';

  static const _moods = [
    'Lo-fi', 'Electronic', 'Hip-hop', 'Ambient', 'Jazz', 'Classical',
    'Indie rock', 'Acoustic', 'House', 'Piano', 'Soul', 'Chill',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<String> get _recent =>
      HiveStorageService.readSetting<List>(_recentKey)?.whereType<String>().toList() ?? const [];

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 380), () => _run(v, remember: false));
  }

  Future<void> _run(String q, {bool remember = true}) async {
    final query = q.trim();
    if (query.length > 200) return; // input validation
    await ref.read(playerControllerProvider.notifier).search(query);
    if (remember && query.isNotEmpty) {
      final next = [query, ..._recent.where((r) => r.toLowerCase() != query.toLowerCase())].take(10).toList();
      await HiveStorageService.writeSetting(_recentKey, next);
      if (mounted) setState(() {});
    }
  }

  void _searchFor(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _focus.unfocus();
    setState(() {});
    _run(text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final loading = ref.watch(playerControllerProvider.select((s) => s.isSearchLoading));
    final result = ref.watch(playerControllerProvider.select((s) => s.searchResult));
    final error = ref.watch(playerControllerProvider.select((s) => s.searchError));
    final resolving = ref.watch(playerControllerProvider.select((s) => s.isResolving));
    final hasQuery = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          maxLength: 200,
          onChanged: _onChanged,
          onSubmitted: (v) => _run(v),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Songs, artists or albums',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  )
                : null,
          ),
        ),
        bottom: resolving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: !hasQuery
            ? _Browse(recent: _recent, moods: _moods, onPick: _searchFor, onClearRecent: () async {
                await HiveStorageService.writeSetting(_recentKey, null);
                setState(() {});
              })
            : loading && (result == null || result.query != _controller.text.trim())
                ? const SingleChildScrollView(child: SongTileSkeletonList())
                : error != null
                    ? EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Search is unavailable',
                        message: error,
                        actionLabel: 'Try again',
                        onAction: () => _run(_controller.text),
                      )
                    : result == null || result.tracks.isEmpty
                        ? EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No results for “${_controller.text.trim()}”',
                            message: 'Try another spelling, or search by artist.',
                          )
                        : _Results(result: result, palette: p, onArtist: (name) {
                            pushPage(context, ArtistScreen(name: name));
                          }),
      ),
    );
  }
}

class _Browse extends StatelessWidget {
  const _Browse({required this.recent, required this.moods, required this.onPick, required this.onClearRecent});
  final List<String> recent;
  final List<String> moods;
  final ValueChanged<String> onPick;
  final VoidCallback onClearRecent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (recent.isNotEmpty) ...[
          SectionHeader('Recent searches', action: 'Clear', onAction: onClearRecent),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in recent)
                  ActionChip(avatar: const Icon(Icons.history_rounded, size: 16), label: Text(r), onPressed: () => onPick(r)),
              ],
            ),
          ),
        ],
        const SectionHeader('Browse by mood & genre'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.3,
            children: [
              for (var i = 0; i < moods.length; i++)
                Material(
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  color: [p.accent, p.accentAlt, p.accentWarm][i % 3].withValues(alpha: 0.85 - (i ~/ 3) * 0.12),
                  child: InkWell(
                    onTap: () => onPick(moods[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(moods[i],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.result, required this.palette, required this.onArtist});
  final AggregatedSearchResult result;
  final AuroraPalette palette;
  final ValueChanged<String> onArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = result.tracks;
    final artists = <String, String>{};
    for (final t in tracks.take(20)) {
      final a = t.display.artist.trim();
      if (a.isEmpty) continue;
      artists.putIfAbsent(TextNormalizer.basic(a), () => a);
      if (artists.length >= 8) break;
    }
    final failed = result.failedSources;

    return ListView(
      key: ValueKey(result.query),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (failed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: palette.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${failed.values.join('. ')}. Some results may be missing.',
                      style: context.text.bodySmall?.copyWith(color: palette.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (artists.isNotEmpty) ...[
          const SectionHeader('Artists'),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final a in artists.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.person_rounded, size: 16),
                      label: Text(a),
                      onPressed: () => onArtist(a),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SectionHeader('Songs', subtitle: 'Best playable source chosen automatically'),
        for (var i = 0; i < tracks.length; i++)
          StaggeredListEntrance(
            index: i,
            child: SongTile(
              song: tracks[i].display,
              track: tracks[i],
              onTap: () async {
                final hasLink = tracks[i].externalUrl.isNotEmpty;
                final ok = await ref
                    .read(playerControllerProvider.notifier)
                    .playMatched(tracks, i, reportUnavailable: !hasLink);
                if (!ok && context.mounted && hasLink) {
                  _offerExternal(context, ref, tracks[i]);
                }
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Text(
            'Searched: ${ref.read(enabledSourcesProvider).map((s) => s.info.displayName).join(', ')}.'
            '${result.fromCache ? ' (cached)' : ''}',
            style: context.text.bodySmall,
          ),
        ),
      ],
    );
  }

  void _offerExternal(BuildContext context, WidgetRef ref, MatchedTrack t) {
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Not available to stream here'),
        content: Text(
          '“${t.display.title}” by ${t.display.artist} isn’t offered by any music service this app is licensed to stream. '
          'You can listen to it on the provider’s own app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close')),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              openExternal(context, t.externalUrl);
            },
            child: Text(t.display.sourceId == 'itunes' ? 'Open in Apple Music' : 'Open'),
          ),
        ],
      ),
    );
  }
}
