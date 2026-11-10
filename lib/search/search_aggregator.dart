import 'dart:async';
import 'dart:collection';

import '../models/song.dart';
import '../sources/music_source.dart';
import 'matched_track.dart';
import 'text_normalizer.dart';
import 'track_matcher.dart';

/// Remembers which provider track successfully played for a given song so the
/// next search / fallback prefers it ("remember successful matches").
abstract class MatchMemory {
  String? lookup(String songKey);
  Future<void> remember(String songKey, String songId);
}

class InMemoryMatchMemory implements MatchMemory {
  final Map<String, String> _map = {};
  @override
  String? lookup(String songKey) => _map[songKey];
  @override
  Future<void> remember(String songKey, String songId) async =>
      _map[songKey] = songId;
}

/// Sliding-window limiter so the app never exceeds a provider's published
/// rate limit (e.g. iTunes ≈ 20 req/min).
class RateLimiter {
  RateLimiter(this.maxRequests, this.window, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int maxRequests;
  final Duration window;
  final DateTime Function() _clock;
  final Queue<DateTime> _hits = Queue();

  bool tryAcquire() {
    final now = _clock();
    while (_hits.isNotEmpty && now.difference(_hits.first) > window) {
      _hits.removeFirst();
    }
    if (_hits.length >= maxRequests) return false;
    _hits.addLast(now);
    return true;
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.at);
  final T value;
  final DateTime at;
}

/// Searches every enabled [MusicSource] concurrently, merges duplicates,
/// identifies the same song across providers and ranks by relevance *and*
/// real playback availability (full track > preview > metadata only).
class SearchAggregator {
  SearchAggregator({
    required List<MusicSource> Function() sources,
    MatchMemory? memory,
    this.matcher = const TrackMatcher(),
    this.perSourceTimeout = const Duration(seconds: 8),
    this.cacheTtl = const Duration(minutes: 10),
    this.cacheSize = 60,
    Map<String, RateLimiter>? rateLimits,
    DateTime Function()? clock,
  })  : _sources = sources,
        memory = memory ?? InMemoryMatchMemory(),
        _clock = clock ?? DateTime.now,
        _limits = rateLimits ??
            {'itunes': RateLimiter(18, const Duration(minutes: 1), clock: clock)};

  final List<MusicSource> Function() _sources;
  final MatchMemory memory;
  final TrackMatcher matcher;
  final Duration perSourceTimeout;
  final Duration cacheTtl;
  final int cacheSize;
  final DateTime Function() _clock;
  final Map<String, RateLimiter> _limits;

  // ignore: prefer_collection_literals
  final LinkedHashMap<String, _CacheEntry<AggregatedSearchResult>> _cache =
      LinkedHashMap();
  final Map<String, Future<AggregatedSearchResult>> _inFlight = {};

  List<MusicSource> get sources => _sources();

  void clearCache() => _cache.clear();

  String _cacheKey(String query, List<MusicSource> sources) =>
      '${TextNormalizer.basic(query)}#${sources.map((s) => s.id).join(',')}';

  /// [playableOnly] restricts the search to providers that serve full tracks
  /// (used when matching a known song, so metadata providers' rate limits are
  /// not spent on lookups).
  Future<AggregatedSearchResult> search(
    String query, {
    int perSource = 25,
    bool playableOnly = false,
  }) {
    final trimmed = query.trim();
    final sources = [
      for (final s in _sources())
        if (!playableOnly || s.info.fullTracks) s,
    ];
    if (trimmed.isEmpty) {
      return Future.value(AggregatedSearchResult(query: trimmed, tracks: const []));
    }
    final key = _cacheKey(trimmed, sources);
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.at) < cacheTtl) {
      _cache.remove(key);
      _cache[key] = cached; // LRU touch
      return Future.value(AggregatedSearchResult(
        query: trimmed,
        tracks: cached.value.tracks,
        failedSources: cached.value.failedSources,
        fromCache: true,
      ));
    }
    // De-duplicate concurrent identical searches.
    return _inFlight[key] ??= _search(trimmed, sources, perSource).then((r) {
      if (r.failedSources.isEmpty || r.tracks.isNotEmpty) {
        _cache[key] = _CacheEntry(r, _clock());
        while (_cache.length > cacheSize) {
          _cache.remove(_cache.keys.first);
        }
      }
      return r;
    }).whenComplete(() {
      // Block body: returning the removed Future would make whenComplete
      // wait on itself.
      _inFlight.remove(key);
    });
  }

  Future<AggregatedSearchResult> _search(
    String query,
    List<MusicSource> sources,
    int perSource,
  ) async {
    final failures = <String, String>{};
    final perSourceResults = await Future.wait(sources.map((s) async {
      final limiter = _limits[s.id];
      if (limiter != null && !limiter.tryAcquire()) {
        failures[s.id] = 'Paused briefly to respect ${s.info.displayName} rate limits';
        return <Song>[];
      }
      try {
        return await s.searchTracks(query, limit: perSource).timeout(perSourceTimeout);
      } on TimeoutException {
        failures[s.id] = '${s.info.displayName} did not respond in time';
      } on SourceException catch (e) {
        failures[s.id] = e.isRateLimited
            ? '${s.info.displayName} is rate-limiting requests'
            : '${s.info.displayName} is unavailable';
      } catch (_) {
        failures[s.id] = '${s.info.displayName} is unavailable';
      }
      return <Song>[];
    }));

    final ranked = rank(query, perSourceResults, sources.map((s) => s.id).toList());
    return AggregatedSearchResult(query: query, tracks: ranked, failedSources: failures);
  }

  /// Clusters + ranks results. Public for unit tests.
  List<MatchedTrack> rank(
    String query,
    List<List<Song>> perSourceResults,
    List<String> sourceOrder,
  ) {
    // Interleave so every provider's top hits are considered first.
    final interleaved = <({Song song, int rank})>[];
    final maxLen = perSourceResults.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < maxLen; i++) {
      for (final list in perSourceResults) {
        if (i < list.length) interleaved.add((song: list[i], rank: i));
      }
    }

    final clusters = <_Cluster>[];
    final seenIds = <String>{};
    for (final item in interleaved) {
      if (!seenIds.add(item.song.id)) continue;
      _Cluster? home;
      var bestScore = 0.0;
      for (final c in clusters) {
        final s = matcher.sameSong(c.anchor, item.song);
        if (s >= TrackMatcher.matchThreshold && s > bestScore) {
          bestScore = s;
          home = c;
        }
      }
      if (home == null) {
        clusters.add(_Cluster(item.song, item.rank));
      } else {
        home.add(item.song, item.rank);
      }
    }

    final scored = <({MatchedTrack track, double score})>[];
    for (final c in clusters) {
      final track = _toMatched(query, c, sourceOrder);
      final availability = track.hasFullTrack
          ? 0.25
          : track.previewOnly
              ? 0.12
              : 0.0;
      final rankBonus = 0.05 / (1 + c.bestRank);
      scored.add((track: track, score: track.relevance * 0.75 + availability + rankBonus));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Drop noise (tracks that barely relate to the query) unless that would
    // leave nothing.
    final relevant = scored.where((e) => e.track.relevance >= 0.3).toList();
    final pick = relevant.isNotEmpty ? relevant : scored;
    return [for (final e in pick) e.track];
  }

  MatchedTrack _toMatched(String query, _Cluster c, List<String> sourceOrder) {
    final refs = c.songs.where((s) => !s.canPlay).toList();
    final catalogue = c.songs.where((s) => s.sourceId == 'itunes').toList();
    final display = catalogue.isNotEmpty ? catalogue.first : c.anchor;
    final playable = c.songs.where((s) => s.canPlay).toList();
    final remembered = memory.lookup(TextNormalizer.songKey(display.title, display.artist));
    playable.sort((a, b) {
      int tier(Song s) => s.playability == Playability.full ? 0 : 1;
      final t = tier(a).compareTo(tier(b));
      if (t != 0) return t;
      if (a.id == remembered) return -1;
      if (b.id == remembered) return 1;
      final oa = sourceOrder.indexOf(a.sourceId), ob = sourceOrder.indexOf(b.sourceId);
      if (oa != ob) return oa.compareTo(ob);
      return matcher.sameSong(display, b).compareTo(matcher.sameSong(display, a));
    });
    final relevance = c.songs
        .map((s) => matcher.relevance(query, s))
        .fold<double>(0, (m, v) => v > m ? v : m);
    return MatchedTrack(
      display: display,
      candidates: playable,
      references: refs,
      relevance: relevance,
    );
  }

  /// Finds authorised playable versions of [reference] (e.g. a catalogue-only
  /// result, or a track whose stream just failed). Only candidates that are
  /// confidently the *same recording* are returned, best first.
  Future<List<Song>> findPlayableFor(
    Song reference, {
    Set<String> excludeIds = const {},
  }) async {
    final query = '${TextNormalizer.title(reference.title)} '
        '${TextNormalizer.artists(reference.artist).join(' ')}'
        .trim();
    final result = await search(query, playableOnly: true);
    final remembered = memory.lookup(
      TextNormalizer.songKey(reference.title, reference.artist),
    );
    final scored = <({Song song, double score})>[];
    for (final t in result.tracks) {
      for (final c in t.candidates) {
        if (excludeIds.contains(c.id) || c.id == reference.id) continue;
        final s = matcher.sameSong(reference, c);
        if (s >= TrackMatcher.matchThreshold) scored.add((song: c, score: s));
      }
    }
    scored.sort((a, b) {
      int tier(Song s) => s.playability == Playability.full ? 0 : 1;
      final t = tier(a.song).compareTo(tier(b.song));
      if (t != 0) return t;
      if (a.song.id == remembered) return -1;
      if (b.song.id == remembered) return 1;
      return b.score.compareTo(a.score);
    });
    return [for (final e in scored) e.song];
  }

  /// Featured tracks for the home screen from every playable source.
  Future<List<Song>> featured({int limit = 30}) async {
    final lists = await Future.wait(_sources().map((s) async {
      try {
        return await s.featuredTracks(limit: limit).timeout(perSourceTimeout);
      } catch (_) {
        return <Song>[];
      }
    }));
    final out = <Song>[];
    final maxLen = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < maxLen; i++) {
      for (final l in lists) {
        if (i < l.length && l[i].canPlay) out.add(l[i]);
      }
    }
    return out;
  }

  Future<void> rememberSuccess(Song reference, Song played) => memory.remember(
        TextNormalizer.songKey(reference.title, reference.artist),
        played.id,
      );
}

class _Cluster {
  _Cluster(this.anchor, this.bestRank) : songs = [anchor];
  final Song anchor;
  final List<Song> songs;
  int bestRank;

  void add(Song s, int rank) {
    songs.add(s);
    if (rank < bestRank) bestRank = rank;
  }
}
