import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import '../models/song.dart';
import '../playback/stream_verifier.dart';
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

/// Finds music across providers **sequentially**, so the app only asks the
/// next provider when the previous one could not supply what was requested.
///
/// Two flows share the provider list (in priority order):
///
/// * [search] — what the Search screen shows. Catalogue metadata (iTunes) is
///   fetched first and independently. If the query names a specific song, the
///   full-track providers are then asked one by one until one has the
///   **exact original recording with a verified stream**; later providers are
///   not contacted. For free-text queries ("lofi") the first provider with
///   relevant results ends the search.
/// * [discover] — finds a verified authorised stream for one known recording
///   (catalogue tap, album page, playback fallback). Same sequential rule.
///
/// Acceptance always uses [TrackMatcher.matchRecording]: covers, remixes,
/// live/instrumental/sped-up versions, other artists, unknown artists and
/// merely similar titles are rejected, never substituted.
class SearchAggregator {
  SearchAggregator({
    required List<MusicSource> Function() sources,
    MatchMemory? memory,
    StreamVerifier? verifier,
    this.matcher = const TrackMatcher(),
    this.perSourceTimeout = const Duration(seconds: 8),
    this.cacheTtl = const Duration(minutes: 10),
    this.discoveryTtl = const Duration(minutes: 30),
    this.negativeDiscoveryTtl = const Duration(minutes: 10),
    this.cacheSize = 60,
    this.specificSongRelevance = 0.75,
    Map<String, RateLimiter>? rateLimits,
    DateTime Function()? clock,
  })  : _sources = sources,
        memory = memory ?? InMemoryMatchMemory(),
        _clock = clock ?? DateTime.now,
        _limits = rateLimits ?? defaultRateLimits(clock) {
    this.verifier = verifier ?? TrustingStreamVerifier(_sourceById);
  }

  /// Conservative per-provider request budgets (iTunes publishes ≈20/min).
  static Map<String, RateLimiter> defaultRateLimits([DateTime Function()? clock]) => {
        'itunes': RateLimiter(18, const Duration(minutes: 1), clock: clock),
        'audius': RateLimiter(60, const Duration(minutes: 1), clock: clock),
        'archive': RateLimiter(30, const Duration(minutes: 1), clock: clock),
        'jamendo': RateLimiter(60, const Duration(minutes: 1), clock: clock),
      };

  final List<MusicSource> Function() _sources;
  final MatchMemory memory;
  late final StreamVerifier verifier;
  final TrackMatcher matcher;
  final Duration perSourceTimeout;
  final Duration cacheTtl;
  final Duration discoveryTtl;
  final Duration negativeDiscoveryTtl;
  final int cacheSize;

  /// Relevance at which the top catalogue result is treated as "the song the
  /// user asked for" (enables exact-original discovery).
  final double specificSongRelevance;
  final DateTime Function() _clock;
  final Map<String, RateLimiter> _limits;

  // ignore: prefer_collection_literals
  final LinkedHashMap<String, _CacheEntry<AggregatedSearchResult>> _cache = LinkedHashMap();
  final Map<String, Future<AggregatedSearchResult>> _inFlight = {};
  final Map<String, _CacheEntry<Discovery>> _discoveries = {};
  final Map<String, Future<Discovery>> _discovering = {};

  /// sourceId → raw error of the most recent failure (diagnostics only).
  final Map<String, String> lastFailureDetails = {};

  List<MusicSource> get sources => _sources();

  MusicSource? _sourceById(String id) {
    for (final s in _sources()) {
      if (s.id == id) return s;
    }
    return null;
  }

  List<MusicSource> get _catalogueSources => [for (final s in _sources()) if (!s.info.fullTracks) s];
  List<MusicSource> get _playableSources => [for (final s in _sources()) if (s.info.fullTracks) s];

  void clearCache() {
    _cache.clear();
    _discoveries.clear();
  }

  String _cacheKey(String query, List<MusicSource> sources) =>
      '${TextNormalizer.basic(query)}#${sources.map((s) => s.id).join(',')}';

  // ── Provider call with limits, timeout and failure reporting ─────────────

  Future<({List<Song> songs, ProviderAttempt? failure})> _ask(
    MusicSource s,
    String query,
    int limit,
  ) async {
    final limiter = _limits[s.id];
    if (limiter != null && !limiter.tryAcquire()) {
      return (
        songs: const <Song>[],
        failure: ProviderAttempt(s.id, AttemptOutcome.rateLimited,
            detail: 'paused to respect ${s.info.displayName} rate limits'),
      );
    }
    try {
      final songs = await s.searchTracks(query, limit: limit).timeout(perSourceTimeout);
      return (songs: songs, failure: null);
    } on TimeoutException {
      _logFailure(s.id, 'timeout after ${perSourceTimeout.inSeconds}s');
      return (
        songs: const <Song>[],
        failure: ProviderAttempt(s.id, AttemptOutcome.timeout,
            detail: '${s.info.displayName} did not respond in time'),
      );
    } on SourceException catch (e) {
      _logFailure(s.id, e);
      return (
        songs: const <Song>[],
        failure: ProviderAttempt(
          s.id,
          e.isRateLimited ? AttemptOutcome.rateLimited : AttemptOutcome.error,
          detail: e.isRateLimited
              ? '${s.info.displayName} is rate-limiting requests'
              : '${s.info.displayName} is unavailable',
        ),
      );
    } catch (e, st) {
      _logFailure(s.id, e, st);
      return (
        songs: const <Song>[],
        failure: ProviderAttempt(s.id, AttemptOutcome.error,
            detail: '${s.info.displayName} is unavailable'),
      );
    }
  }

  /// Records the underlying cause (DNS, TLS, timeout, HTTP status…) in the
  /// debug console / logcat, so "unavailable" in the UI can be diagnosed.
  void _logFailure(String sourceId, Object error, [StackTrace? stack]) {
    developer.log(
      'search failed for $sourceId: $error',
      name: 'aurora.search',
      error: error,
      stackTrace: stack,
    );
    lastFailureDetails[sourceId] = error.toString();
  }

  /// Exact matches of [reference] among [songs], remembered match first,
  /// then best album/duration agreement.
  List<Song> _exactMatches(
    Song reference,
    Iterable<Song> songs, {
    String query = '',
    Set<String> excludeIds = const {},
  }) {
    final remembered = memory.lookup(TextNormalizer.songKey(reference.title, reference.artist));
    final scored = <({Song song, double score})>[];
    for (final c in songs) {
      if (!c.canPlay || c.id == reference.id || excludeIds.contains(c.id)) continue;
      final m = matcher.matchRecording(reference, c, query: query);
      if (m.isExact) {
        scored.add((song: c, score: m.score));
      } else {
        developer.log('rejected ${c.id} for "${reference.title}": $m', name: 'aurora.match');
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

  /// First candidate whose stream verifies, with its resolved URL applied.
  Future<({Song? song, String detail})> _firstVerified(List<Song> candidates) async {
    final reasons = <String>[];
    for (final c in candidates) {
      final check = await verifier.verify(c);
      if (check.isPlayable) {
        final song = c.audioUrl.isEmpty && check.uri != null
            ? c.copyWith(audioUrl: check.uri.toString())
            : c;
        return (song: song, detail: '');
      }
      reasons.add('${c.id}: $check');
    }
    return (song: null, detail: reasons.join('; '));
  }

  // ── Search screen ────────────────────────────────────────────────────────

  /// Search for the Search screen. See the class docs for the order of work.
  /// [isCancelled] is checked before every provider request, so a newer query
  /// stops an older one from sending further requests.
  Future<AggregatedSearchResult> search(
    String query, {
    int perSource = 25,
    bool Function()? isCancelled,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Future.value(AggregatedSearchResult(query: trimmed, tracks: const []));
    }
    final key = _cacheKey(trimmed, _sources());
    final cached = _cache[key];
    if (cached != null && _clock().difference(cached.at) < cacheTtl) {
      _cache.remove(key);
      _cache[key] = cached; // LRU touch
      final v = cached.value;
      return Future.value(AggregatedSearchResult(
        query: trimmed,
        tracks: v.tracks,
        failedSources: v.failedSources,
        attempts: v.attempts,
        fromCache: true,
      ));
    }
    // De-duplicate concurrent identical searches.
    return _inFlight[key] ??= _search(trimmed, perSource, isCancelled).then((r) {
      final failedEverywhere = r.tracks.isEmpty && r.failedSources.isNotEmpty;
      if (!r.cancelled && !failedEverywhere) {
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
    int perSource,
    bool Function()? isCancelled,
  ) async {
    bool cancelled() => isCancelled?.call() ?? false;
    final attempts = <ProviderAttempt>[];

    // 1. Authoritative metadata, independent of playback discovery.
    final catalogue = <Song>[];
    for (final s in _catalogueSources) {
      if (cancelled()) break;
      final r = await _ask(s, query, perSource);
      if (r.failure != null) {
        attempts.add(r.failure!);
      } else {
        catalogue.addAll(r.songs);
        attempts.add(ProviderAttempt(s.id, r.songs.isEmpty ? AttemptOutcome.noMatch : AttemptOutcome.results));
      }
    }

    // 2. Did the user name a specific song? (see [pickReference])
    final reference = pickReference(query, catalogue);

    // 3. Full-track providers, one at a time.
    final playable = <List<Song>>[];
    Song? verifiedOriginal;
    for (final s in _playableSources) {
      if (cancelled()) {
        return AggregatedSearchResult(query: query, tracks: const [], attempts: attempts, cancelled: true);
      }
      final r = await _ask(s, query, perSource);
      if (r.failure != null) {
        attempts.add(r.failure!);
        continue;
      }
      playable.add(r.songs);
      if (reference != null) {
        final exact = _exactMatches(reference, r.songs, query: query);
        if (exact.isEmpty) {
          attempts.add(ProviderAttempt(s.id, AttemptOutcome.noMatch));
          continue;
        }
        final v = await _firstVerified(exact);
        if (v.song != null) {
          verifiedOriginal = v.song;
          attempts.add(ProviderAttempt(s.id, AttemptOutcome.verified, detail: v.song!.id));
          break; // exact original found: do not ask later providers
        }
        attempts.add(ProviderAttempt(s.id, AttemptOutcome.unplayable, detail: v.detail));
      } else {
        final relevant = r.songs.where((x) => x.canPlay && matcher.relevance(query, x) >= 0.45);
        if (relevant.isNotEmpty) {
          attempts.add(ProviderAttempt(s.id, AttemptOutcome.results));
          break; // free-text query answered
        }
        attempts.add(ProviderAttempt(s.id, AttemptOutcome.noMatch));
      }
    }

    final tracks = rank(
      query,
      [catalogue, ...playable],
      _sources().map((s) => s.id).toList(),
      reference: reference,
      verifiedOriginal: verifiedOriginal,
    );
    return AggregatedSearchResult(
      query: query,
      tracks: tracks,
      attempts: attempts,
      failedSources: {for (final a in attempts) if (a.isFailure) a.sourceId: a.detail},
    );
  }

  /// True when [query] names [song] specifically: it contains the song's
  /// whole title and also names the artist (an artist word that is not just
  /// part of the title — "lofi" by "LoFi Hip Hop" doesn't count).
  static bool namesSong(String query, Song song) {
    final q = TextNormalizer.tokens(TextNormalizer.basic(query));
    final title = TextNormalizer.tokens(TextNormalizer.title(song.title));
    if (title.isEmpty || !q.containsAll(title)) return false;
    final artistWords = TextNormalizer.tokens(TextNormalizer.basic(song.artist)).difference(title);
    return artistWords.any(q.contains);
  }

  /// A playable upload that names the requested song's artist in its title
  /// ("Ed Sheeran - Perfect (Lyrics)") but was published by someone else is
  /// almost certainly an unauthorised re-upload, not an authorised source.
  /// Such results are hidden when the user asked for that song.
  bool isLikelyReupload(Song reference, Song candidate) {
    if (!candidate.canPlay || candidate.isLocal || candidate.sourceId == reference.sourceId) return false;
    if (matcher.artistSimilarity(reference.artist, candidate.artist) >= TrackMatcher.artistThreshold) {
      return false; // published by the artist
    }
    final title = ' ${TextNormalizer.basic(candidate.title)} ';
    final artists = TextNormalizer.artists(reference.artist).where((a) => a.length >= 3);
    final namesArtist = artists.any((a) => title.contains(' $a '));
    final namesSong = TextNormalizer.tokens(TextNormalizer.title(reference.title))
        .every(TextNormalizer.tokens(TextNormalizer.basic(candidate.title)).contains);
    return namesArtist && namesSong;
  }

  /// The catalogue song the user is asking for, or null for an open search.
  ///
  /// * If the query names title **and** artist ([namesSong]) → that song.
  /// * Otherwise only for a multi-word title that the query contains, when
  ///   the top catalogue result clearly *owns* that title (most same-title
  ///   entries in the top results are by the same artist). "Shape of You" →
  ///   Ed Sheeran; "Moonlight Sonata" (many performers) → no single original.
  Song? pickReference(String query, List<Song> catalogue) {
    final top = catalogue.take(10).where((c) =>
        TextNormalizer.unrequestedVersions(c.title, '', query: query).isEmpty).toList();
    for (final c in top) {
      if (namesSong(query, c) && matcher.relevance(query, c) >= specificSongRelevance) return c;
    }
    if (top.isEmpty) return null;
    final first = top.first;
    final q = TextNormalizer.tokens(TextNormalizer.basic(query));
    final title = TextNormalizer.title(first.title);
    final titleWords = TextNormalizer.tokens(title);
    if (titleWords.length < 2 || !q.containsAll(titleWords)) return null;
    // Every query word must be explained by the title (no unexplained
    // performer / composer names).
    if (!titleWords.containsAll(q)) return null;
    // Count entries per artist for this title, versions included (remixes /
    // acoustic versions by the same artist show who owns the song).
    final counts = <String, int>{};
    for (final c in catalogue.take(10)) {
      if (TextNormalizer.title(c.title) != title) continue;
      final key = TextNormalizer.artists(c.artist).join('|');
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final mine = counts[TextNormalizer.artists(first.artist).join('|')] ?? 0;
    final rival = counts.entries
        .where((e) => e.key != TextNormalizer.artists(first.artist).join('|'))
        .fold<int>(0, (m, e) => e.value > m ? e.value : m);
    return mine >= 2 && mine > rival ? first : null;
  }

  /// Groups results into recordings and ranks them. Public for unit tests.
  ///
  /// Songs are only grouped when [TrackMatcher.matchRecording] says they are
  /// the same recording. When [reference] is given it becomes the first
  /// ("Best match") entry; its playable candidates are the verified original
  /// followed by other exact matches — never covers or other artists.
  List<MatchedTrack> rank(
    String query,
    List<List<Song>> perSourceResults,
    List<String> sourceOrder, {
    Song? reference,
    Song? verifiedOriginal,
  }) {
    // Interleave so every provider's top hits are considered first.
    final interleaved = <({Song song, int rank})>[];
    final maxLen = perSourceResults.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < maxLen; i++) {
      for (final list in perSourceResults) {
        if (i < list.length) interleaved.add((song: list[i], rank: i));
      }
    }

    _Cluster? refCluster;
    if (reference != null) {
      refCluster = _Cluster(reference, 0, isReference: true);
      if (verifiedOriginal != null) refCluster.add(verifiedOriginal, 0);
    }
    final clusters = <_Cluster>[?refCluster];
    final seenIds = <String>{?reference?.id, ?verifiedOriginal?.id};
    for (final item in interleaved) {
      if (!seenIds.add(item.song.id)) continue;
      if (reference != null && isLikelyReupload(reference, item.song)) {
        developer.log('hid likely re-upload ${item.song.id} "${item.song.title}" by "${item.song.artist}"',
            name: 'aurora.match');
        continue;
      }
      _Cluster? home;
      for (final c in clusters) {
        if (c.isReference && verifiedOriginal == null && item.song.canPlay) {
          // Without a verified original the reference stays unavailable:
          // unverified streams must not make it look playable. (Catalogue
          // duplicates of the same recording are still folded in.)
          continue;
        }
        if (matcher.isSameRecording(c.anchor, item.song, query: query)) {
          home = c;
          break;
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
      final track = _toMatched(query, c, sourceOrder, verifiedOriginal: verifiedOriginal);
      final availability = track.hasFullTrack
          ? 0.25
          : track.previewOnly
              ? 0.12
              : 0.0;
      final rankBonus = 0.05 / (1 + c.bestRank);
      final score = c.isReference ? 10.0 : track.relevance * 0.75 + availability + rankBonus;
      scored.add((track: track, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    // Drop noise (tracks that barely relate to the query) unless that would
    // leave nothing.
    final relevant = scored.where((e) => e.track.isBestMatch || e.track.relevance >= 0.3).toList();
    final pick = relevant.isNotEmpty ? relevant : scored;
    return [for (final e in pick) e.track];
  }

  MatchedTrack _toMatched(
    String query,
    _Cluster c,
    List<String> sourceOrder, {
    Song? verifiedOriginal,
  }) {
    final refs = c.songs.where((s) => !s.canPlay).toList();
    final catalogue = c.songs.where((s) => s.sourceId == 'itunes').toList();
    final display = catalogue.isNotEmpty ? catalogue.first : c.anchor;
    final playable = c.songs.where((s) => s.canPlay).toList();
    final remembered = memory.lookup(TextNormalizer.songKey(display.title, display.artist));
    playable.sort((a, b) {
      if (a.id == verifiedOriginal?.id) return -1;
      if (b.id == verifiedOriginal?.id) return 1;
      int tier(Song s) => s.playability == Playability.full ? 0 : 1;
      final t = tier(a).compareTo(tier(b));
      if (t != 0) return t;
      if (a.id == remembered) return -1;
      if (b.id == remembered) return 1;
      final oa = sourceOrder.indexOf(a.sourceId), ob = sourceOrder.indexOf(b.sourceId);
      return oa.compareTo(ob);
    });
    final relevance = c.songs
        .map((s) => matcher.relevance(query, s))
        .fold<double>(0, (m, v) => v > m ? v : m);
    return MatchedTrack(
      display: display,
      candidates: playable,
      references: refs,
      relevance: relevance,
      isBestMatch: c.isReference,
      verifiedIds: {
        if (verifiedOriginal != null && playable.any((p) => p.id == verifiedOriginal.id))
          verifiedOriginal.id,
      },
    );
  }

  // ── Discovery for one known recording ────────────────────────────────────

  /// Finds a verified authorised stream of exactly [reference].
  ///
  /// Providers are asked in priority order; the first verified exact match
  /// ends the search. [skipSources] continues a previous discovery (fallback)
  /// without re-asking providers already tried; [excludeIds] skips streams
  /// that already failed. Results are cached (positive [discoveryTtl],
  /// negative [negativeDiscoveryTtl]) and identical lookups are shared.
  Future<Discovery> discover(
    Song reference, {
    String query = '',
    Set<String> excludeIds = const {},
    Set<String> skipSources = const {},
    bool Function()? isCancelled,
  }) {
    final key = '${TextNormalizer.songKey(reference.title, reference.artist)}'
        '|${TextNormalizer.versionTags(query).join(',')}'
        '|${_playableSources.map((s) => s.id).join(',')}';
    final cacheable = excludeIds.isEmpty && skipSources.isEmpty;
    if (cacheable) {
      final hit = _discoveries[key];
      if (hit != null) {
        final ttl = hit.value.found ? discoveryTtl : negativeDiscoveryTtl;
        final stillValid = _clock().difference(hit.at) < ttl &&
            (!hit.value.found || verifier.cached(hit.value.playable!.id)?.status != StreamStatus.unavailable);
        if (stillValid) {
          final v = hit.value;
          return Future.value(Discovery(
            reference: v.reference,
            playable: v.playable,
            alternates: v.alternates,
            attempts: v.attempts,
            fromCache: true,
          ));
        }
        _discoveries.remove(key);
      }
      final running = _discovering[key];
      if (running != null) return running;
    }
    final future = _discover(reference, query, excludeIds, skipSources, isCancelled).then((d) {
      if (cacheable && !(isCancelled?.call() ?? false) && !d.attempts.every((a) => a.isFailure)) {
        _discoveries[key] = _CacheEntry(d, _clock());
      }
      return d;
    });
    if (!cacheable) return future;
    return _discovering[key] = future.whenComplete(() {
      _discovering.remove(key);
    });
  }

  Future<Discovery> _discover(
    Song reference,
    String query,
    Set<String> excludeIds,
    Set<String> skipSources,
    bool Function()? isCancelled,
  ) async {
    final attempts = <ProviderAttempt>[];
    final lookup = '${TextNormalizer.title(reference.title)} '
            '${TextNormalizer.artists(reference.artist).join(' ')}'
        .trim();
    for (final s in _playableSources) {
      if (skipSources.contains(s.id)) continue;
      if (isCancelled?.call() ?? false) break;
      final r = await _ask(s, lookup, 25);
      if (r.failure != null) {
        attempts.add(r.failure!);
        continue;
      }
      final exact = _exactMatches(reference, r.songs, query: query, excludeIds: excludeIds);
      if (exact.isEmpty) {
        attempts.add(ProviderAttempt(s.id, AttemptOutcome.noMatch));
        continue;
      }
      final v = await _firstVerified(exact);
      if (v.song != null) {
        attempts.add(ProviderAttempt(s.id, AttemptOutcome.verified, detail: v.song!.id));
        return Discovery(
          reference: reference,
          playable: v.song,
          alternates: [for (final e in exact) if (e.id != v.song!.id) e],
          attempts: attempts,
        );
      }
      attempts.add(ProviderAttempt(s.id, AttemptOutcome.unplayable, detail: v.detail));
    }
    return Discovery(reference: reference, attempts: attempts);
  }

  /// Verified playable versions of [reference], best first (compatibility
  /// wrapper over [discover] used by album pages).
  Future<List<Song>> findPlayableFor(
    Song reference, {
    Set<String> excludeIds = const {},
  }) async {
    final d = await discover(reference, excludeIds: excludeIds);
    return d.found ? [d.playable!, ...d.alternates] : const [];
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
  _Cluster(this.anchor, this.bestRank, {this.isReference = false}) : songs = [anchor];
  final Song anchor;
  final List<Song> songs;
  final bool isReference;
  int bestRank;

  void add(Song s, int rank) {
    songs.add(s);
    if (rank < bestRank) bestRank = rank;
  }
}
