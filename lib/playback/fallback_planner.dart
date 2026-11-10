import '../models/song.dart';
import '../search/search_aggregator.dart';
import '../search/text_normalizer.dart';

/// Decides what to play when a stream fails.
///
/// Order of attempts for one song:
///  1. Retry the *same* source once if the failure looked transient and the
///     track had already started (mid-stream network drop).
///  2. Other candidates already known from the search that produced it.
///  3. A fresh, confidence-checked search for the same recording on other
///     authorised providers ([SearchAggregator.findPlayableFor]).
///  4. Give up → caller skips to the next track and tells the user.
class FallbackPlanner {
  FallbackPlanner(this._aggregator, {this.maxAttemptsPerSong = 4});

  final SearchAggregator _aggregator;
  final int maxAttemptsPerSong;

  /// songKey → ids already tried for it.
  final Map<String, Set<String>> _tried = {};

  /// songKey → candidates known from search (best first).
  final Map<String, List<Song>> _known = {};

  /// songKey → whether we already retried the same source.
  final Set<String> _retriedSame = {};

  static String keyFor(Song s) => TextNormalizer.songKey(s.title, s.artist);

  /// Registers alternatives for a song (from a [MatchedTrack]).
  void registerCandidates(Song song, List<Song> candidates) {
    if (candidates.length < 2) return;
    _known[keyFor(song)] = candidates;
  }

  /// Call when a song plays successfully — clears failure bookkeeping.
  void markSuccess(Song song) {
    final k = keyFor(song);
    _tried.remove(k);
    _retriedSame.remove(k);
  }

  bool shouldRetrySame(Song failed, {required bool hadStarted}) {
    final k = keyFor(failed);
    if (!hadStarted || _retriedSame.contains(k)) return false;
    _retriedSame.add(k);
    return true;
  }

  /// Next song to try instead of [failed], or null to give up.
  Future<Song?> nextFor(Song failed) async {
    final k = keyFor(failed);
    final tried = _tried.putIfAbsent(k, () => <String>{})..add(failed.id);
    if (tried.length >= maxAttemptsPerSong) return null;

    for (final c in _known[k] ?? const <Song>[]) {
      if (!tried.contains(c.id) && c.canPlay) {
        tried.add(c.id);
        return c;
      }
    }
    // Local files have no alternative source.
    if (failed.isLocal) return null;
    try {
      final found = await _aggregator.findPlayableFor(failed, excludeIds: tried);
      for (final c in found) {
        if (!tried.contains(c.id)) {
          tried.add(c.id);
          return c;
        }
      }
    } catch (_) {
      // Network down: nothing else to try right now.
    }
    return null;
  }
}
