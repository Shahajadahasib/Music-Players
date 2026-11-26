import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../providers/source_providers.dart';
import '../../sources/radio_source.dart';
import '../../theme/aurora_theme.dart';
import '../navigation.dart';
import '../widgets/common.dart';

/// Live radio (Radio Browser directory). Separate from song search: a
/// station is a live broadcast, never a match for a requested recording.
class RadioScreen extends ConsumerStatefulWidget {
  const RadioScreen({super.key});

  @override
  ConsumerState<RadioScreen> createState() => _RadioScreenState();
}

/// Quick filters: (label, how to query the directory).
typedef _Filter = ({String label, Future<List<Song>> Function(RadioSource r) load});

class _RadioScreenState extends ConsumerState<RadioScreen> {
  static final List<_Filter> _filters = [
    (label: 'Popular', load: (r) => r.topStations()),
    (label: 'Bangladesh', load: (r) => r.searchByCountry('BD')),
    (label: 'Bangla', load: (r) => r.searchByLanguage('bengali')),
    (label: 'India', load: (r) => r.searchByCountry('IN')),
    (label: 'Hindi', load: (r) => r.searchByLanguage('hindi')),
    (label: 'English', load: (r) => r.searchByLanguage('english')),
    (label: 'Islamic', load: (r) => r.searchByTag('islamic')),
    (label: 'Classical', load: (r) => r.searchByTag('classical')),
    (label: 'Jazz', load: (r) => r.searchByTag('jazz')),
    (label: 'Rock', load: (r) => r.searchByTag('rock')),
    (label: 'News', load: (r) => r.searchByTag('news')),
  ];

  final _controller = TextEditingController();
  Timer? _debounce;
  int _selected = 0;
  int _request = 0;
  bool _loading = false;
  String? _error;
  List<Song> _stations = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load((r) => _filters[0].load(r)));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load(Future<List<Song>> Function(RadioSource r) query) async {
    final radio = ref.read(radioSourceProvider);
    if (radio == null) return;
    final id = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await query(radio);
      if (!mounted || id != _request) return;
      setState(() {
        _stations = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _request) return;
      setState(() {
        _loading = false;
        _error = 'Couldn’t reach the radio directory. Check your connection.';
      });
    }
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      final q = text.trim();
      if (q.isEmpty) {
        _load(_filters[_selected < 0 ? 0 : _selected].load);
      } else {
        setState(() => _selected = -1);
        _load((r) => r.searchByName(q));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final radio = ref.watch(radioSourceProvider);
    final p = context.palette;
    final current = ref.watch(playerControllerProvider.select((s) => s.currentSong));

    return Scaffold(
      appBar: AppBar(title: const Text('Live radio')),
      body: radio == null
          ? const EmptyState(
              icon: Icons.radio_rounded,
              title: 'Radio is turned off',
              message: 'This build doesn’t include live radio.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: TextField(
                    controller: _controller,
                    onChanged: _onQuery,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Search stations',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (var i = 0; i < _filters.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(_filters[i].label),
                            selected: _selected == i,
                            onSelected: (_) {
                              _controller.clear();
                              setState(() => _selected = i);
                              _load(_filters[i].load);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _body(context, p, current)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: InkWell(
                    onTap: () => openExternal(context, RadioSource.sourceInfo.homepage),
                    child: Text(
                      '${RadioSource.sourceInfo.attribution}. Stations stream under their own licences.',
                      style: context.text.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _body(BuildContext context, AuroraPalette p, Song? current) {
    if (_loading && _stations.isEmpty) return const SongTileSkeletonList();
    if (_error != null) {
      return EmptyState(icon: Icons.wifi_off_rounded, title: 'Radio unavailable', message: _error!);
    }
    if (_stations.isEmpty) {
      return const EmptyState(
        icon: Icons.radio_rounded,
        title: 'No stations found',
        message: 'Try another name, language or genre.',
      );
    }
    return ListView.builder(
      itemCount: _stations.length,
      padding: const EdgeInsets.only(bottom: 16),
      itemBuilder: (context, i) {
        final s = _stations[i];
        final playing = current?.id == s.id;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 48,
              height: 48,
              child: s.coverUrl.isEmpty
                  ? ColoredBox(
                      color: p.accentWarm.withValues(alpha: 0.15),
                      child: Icon(Icons.radio_rounded, color: p.accentWarm),
                    )
                  : Image.network(
                      s.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: p.accentWarm.withValues(alpha: 0.15),
                        child: Icon(Icons.radio_rounded, color: p.accentWarm),
                      ),
                    ),
            ),
          ),
          title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Row(
            children: [
              const StatusBadge(TrackStatus.liveRadio),
              const SizedBox(width: 6),
              Expanded(child: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          trailing: playing ? NowPlayingBars(playing: true, color: p.accentWarm) : null,
          onTap: () => ref.read(playerControllerProvider.notifier).playPlaylist([s]),
        );
      },
    );
  }
}
