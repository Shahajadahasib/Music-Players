import '../models/song.dart';
import '../search/matched_track.dart';
import '../search/search_aggregator.dart';
import '../search/text_normalizer.dart';

/// Decides what to play when a stream fails — always **the same recording**,
/// never a cover or another artist's song.
///
/// Order of attempts for one song:
///  1. Retry the *same* source once.
///  2. Other known sources of the same recording (from the search that
///     produced it), each verified before use.
///  3. Sequential discovery on the enabled authorised providers
///     ([SearchAggregator.discover]), skipping streams that already failed.
///  4. Give up: the caller stops playback and shows [explanation].
class FallbackPlanner {
  FallbackPlanner(this._aggregator, {this.maxAttemptsPerSong = 6});

  final SearchAggregator _aggregator;
  final int maxAttemptsPerSong;

  /// songKey → ids already tried for it.
  final Map<String, Set<String>> _tried = {};

  /// songKey → other sources of the same recording (best first).
  final Map<String, List<Song>> _known = {};

  /// songKey → whether we already retried the same source.
  final Set<String> _retriedSame = {};

  /// Why the last [nextFor] gave up (for the error message).
  String explanation = '';

  static String keyFor(Song s) => TextNormalizer.songKey(s.title, s.artist);

  /// Registers other sources of the same recording (from a [MatchedTrack]
  /// or a [Discovery]); they were matched with the strict recording matcher.
  void registerCandidates(Song song, List<Song> candidates) {
    final others = [for (final c in candidates) if (c.id != song.id) c];
    if (others.isEmpty) return;
    _known[keyFor(song)] = others;
  }

  /// Call when a song plays successfully — clears failure bookkeeping.
  void markSuccess(Song song) {
    final k = keyFor(song);
    _tried.remove(k);
    _retriedSame.remove(k);
  }

  /// Step 1: true once per song (then false until it plays successfully).
  bool shouldRetrySame(Song failed) {
    final k = keyFor(failed);
    if (_retriedSame.contains(k)) return false;
    // A stream the verifier knows is gone (403/404/…) is not worth retrying.
    final cached = _aggregator.verifier.cached(failed.id);
    if (cached != null && !cached.isPlayable) return false;
    _retriedSame.add(k);
    return true;
  }

  /// Next verified source of the same recording as [failed], or null.
  /// [reference] is the catalogue song the user picked, when known.
  Future<Song?> nextFor(Song failed, {Song? reference}) async {
    explanation = '';
    final k = keyFor(failed);
    final tried = _tried.putIfAbsent(k, () => <String>{})..add(failed.id);
    if (tried.length >= maxAttemptsPerSong) {
      explanation = 'No other authorised source could play this recording.';
      return null;
    }

    // 2. Known sources of the same recording, verified before use.
    for (final c in _known[k] ?? const <Song>[]) {
      if (tried.contains(c.id) || !c.canPlay) continue;
      tried.add(c.id);
      final check = await _aggregator.verifier.verify(c);
      if (check.isPlayable) {
        return c.audioUrl.isEmpty && check.uri != null
            ? c.copyWith(audioUrl: check.uri.toString())
            : c;
      }
    }

    // Local files have no alternative source.
    if (failed.isLocal) {
      explanation = 'This file could not be played.';
      return null;
    }

    // 3. Sequential discovery of the same recording on authorised providers.
    try {
      final d = await _aggregator.discover(reference ?? failed, excludeIds: tried);
      if (d.found) {
        tried.add(d.playable!.id);
        _known[k] = [..._known[k] ?? const <Song>[], ...d.alternates];
        return d.playable;
      }
      explanation = d.explanation;
    } catch (_) {
      explanation = 'Music services could not be reached.';
    }
    return null;
  }
}
