import 'dart:math' as math;

import '../models/song.dart';
import 'text_normalizer.dart';

/// Why a candidate was or wasn't accepted as the requested recording.
enum RecordingVerdict {
  exact,
  differentTitle,
  missingArtist,
  differentArtist,
  unrequestedVersion,
  durationMismatch,
}

class RecordingMatch {
  const RecordingMatch(this.verdict, {this.detail = '', this.score = 0});

  final RecordingVerdict verdict;
  final String detail;

  /// Tie-breaker among exact matches (album / duration agreement), 0..1.
  final double score;

  bool get isExact => verdict == RecordingVerdict.exact;

  @override
  String toString() => '${verdict.name}${detail.isEmpty ? '' : ' ($detail)'}';
}

/// Scores how likely two tracks are the *same recording*, and how relevant a
/// track is to a free-text query. Pure Dart, no I/O — fully unit-tested.
class TrackMatcher {
  const TrackMatcher();

  /// Legacy similarity threshold. [sameSong] is now only used for *ranking*;
  /// accepting a stream as the requested recording uses [matchRecording],
  /// which is rule-based (0.78 accepted e.g. a same-title track by
  /// "Ed Sheeran Fan" for Ed Sheeran, and unknown artists).
  static const double matchThreshold = 0.78;

  /// Normalised-title similarity required for an exact match. Allows small
  /// typos / punctuation differences ("Dont" vs "Don't") but not extra words.
  static const double titleThreshold = 0.92;

  /// Artist-name similarity required (after splitting credits).
  static const double artistThreshold = 0.9;

  /// Durations further apart than this are different recordings (when both
  /// are known and neither is a preview).
  static const Duration durationTolerance = Duration(seconds: 8);

  /// Decides whether [candidate] is the *same recording* as [reference].
  ///
  /// Rules (all must pass):
  ///  * no version indicator (cover, remix, live, violin, karaoke, sped up…)
  ///    that the reference lacks and the [query] did not request — these are
  ///    rejected outright, not penalised;
  ///  * normalised titles equal (≥ [titleThreshold] for typos), so a merely
  ///    similar title ("Perfect Symphony" for "Perfect") is rejected;
  ///  * both artists known, and the reference's primary artist appears in the
  ///    candidate's credits (featured artists may differ);
  ///  * durations within [durationTolerance] when both are reliable.
  RecordingMatch matchRecording(Song reference, Song candidate, {String query = ''}) {
    final extra = TextNormalizer.unrequestedVersions(
      candidate.title,
      reference.title,
      query: query,
    );
    if (extra.isNotEmpty) {
      return RecordingMatch(RecordingVerdict.unrequestedVersion, detail: extra.join(','));
    }
    // The reference itself may be a version the user asked for ("Live"):
    // then the candidate must carry the same version.
    final missing = TextNormalizer.versionTags(reference.title)
        .difference(TextNormalizer.versionTags(candidate.title));
    if (missing.isNotEmpty) {
      return RecordingMatch(RecordingVerdict.unrequestedVersion, detail: 'missing ${missing.join(',')}');
    }

    final rt = TextNormalizer.title(reference.title);
    final ct = TextNormalizer.title(candidate.title);
    final titleSim = rt == ct ? 1.0 : _levRatio(rt, ct);
    if (titleSim < titleThreshold) {
      return RecordingMatch(RecordingVerdict.differentTitle, detail: '"$ct" vs "$rt"');
    }

    final refArtists = TextNormalizer.artists(reference.artist);
    final candArtists = TextNormalizer.artists(candidate.artist);
    if (refArtists.isEmpty || candArtists.isEmpty) {
      return const RecordingMatch(RecordingVerdict.missingArtist);
    }
    final primary = TextNormalizer.basic(_primaryArtist(reference.artist));
    var artistSim = 0.0;
    for (final c in candArtists) {
      artistSim = math.max(artistSim, _artistSimilarity(primary, c));
    }
    if (artistSim < artistThreshold) {
      return RecordingMatch(
        RecordingVerdict.differentArtist,
        detail: '"${candidate.artist}" vs "${reference.artist}"',
      );
    }

    final dr = reference.duration, dc = candidate.duration;
    var durationScore = 0.5;
    if (dr != null && dc != null && dr > Duration.zero && dc > Duration.zero &&
        !reference.isPreview && !candidate.isPreview) {
      final diff = (dr - dc).abs();
      if (diff > durationTolerance) {
        return RecordingMatch(
          RecordingVerdict.durationMismatch,
          detail: '${dc.inSeconds}s vs ${dr.inSeconds}s',
        );
      }
      durationScore = 1 - diff.inMilliseconds / durationTolerance.inMilliseconds;
    }

    final albumMatch = reference.album.isNotEmpty &&
        candidate.album.isNotEmpty &&
        TextNormalizer.title(reference.album) == TextNormalizer.title(candidate.album);
    return RecordingMatch(
      RecordingVerdict.exact,
      score: (0.5 * titleSim + 0.3 * durationScore + (albumMatch ? 0.2 : 0)).clamp(0.0, 1.0),
    );
  }

  bool isSameRecording(Song reference, Song candidate, {String query = ''}) =>
      matchRecording(reference, candidate, query: query).isExact;

  /// First credited artist: "A feat. B & C" → "A".
  static String _primaryArtist(String artist) {
    final parts = artist.split(RegExp(r'\s*(?:,|&|/|;|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b|\bx\b|\bvs\.?)\s*', caseSensitive: false));
    return parts.firstWhere((p) => p.trim().isNotEmpty, orElse: () => artist).trim();
  }

  /// Exact (ignoring a leading "the") or a near-identical spelling.
  static double _artistSimilarity(String a, String b) {
    String strip(String s) => s.startsWith('the ') ? s.substring(4) : s;
    final x = strip(a), y = strip(b);
    if (x == y) return 1;
    return _levRatio(x, y);
  }

  static double _levRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    return 1 - _lev(a, b) / math.max(a.length, b.length);
  }

  /// 0..1 — probability-like score that [a] and [b] are the same recording.
  double sameSong(Song a, Song b) {
    final titleScore = stringSimilarity(
      TextNormalizer.title(a.title),
      TextNormalizer.title(b.title),
    );
    if (titleScore < 0.5) return titleScore * 0.5;

    final artistScore = artistSimilarity(a.artist, b.artist);
    final durationScore = _durationScore(a, b);

    var score = 0.55 * titleScore + 0.35 * artistScore + 0.10 * durationScore;

    // A live / remix / karaoke / cover version is a different recording.
    final tagsA = TextNormalizer.versionTags(a.title);
    final tagsB = TextNormalizer.versionTags(b.title);
    if (tagsA.length != tagsB.length || !tagsA.containsAll(tagsB)) {
      score *= 0.6;
    }
    // Strong duration mismatch (> 30 s) with both known and both full-length.
    if (durationScore == 0) score *= 0.75;
    return score.clamp(0.0, 1.0);
  }

  bool isSameSong(Song a, Song b) => sameSong(a, b) >= matchThreshold;

  /// 0..1 — how well [song] answers [query] ("bohemian rhapsody queen").
  double relevance(String query, Song song) {
    final q = TextNormalizer.basic(query);
    if (q.isEmpty) return 0;
    final qTokens = TextNormalizer.tokens(q);
    final title = TextNormalizer.title(song.title);
    final titleTokens = TextNormalizer.tokens(title);
    final artistTokens = TextNormalizer.tokens(TextNormalizer.basic(song.artist));
    final albumTokens = TextNormalizer.tokens(TextNormalizer.basic(song.album));
    final all = {...titleTokens, ...artistTokens, ...albumTokens};

    // Coverage: fraction of query tokens explained by the track's metadata.
    var covered = 0.0;
    for (final t in qTokens) {
      if (all.contains(t)) {
        covered += 1;
      } else if (all.any((w) => w.length > 3 && (w.startsWith(t) || _lev(w, t) <= 1))) {
        covered += 0.7;
      }
    }
    final coverage = covered / qTokens.length;

    // Title precision: penalise long titles that merely contain the query.
    final titleHits = titleTokens.where(qTokens.contains).length;
    final precision = titleTokens.isEmpty ? 0.0 : titleHits / titleTokens.length;

    // Exact title (or "title artist") is the strongest signal.
    final exact = q == title ||
        q == '$title ${TextNormalizer.basic(song.artist)}' ||
        q == '${TextNormalizer.basic(song.artist)} $title';

    var score = 0.6 * coverage + 0.3 * precision + (exact ? 0.1 : 0);
    // Penalise unrequested versions (query didn't ask for "live"/"remix").
    final wanted = TextNormalizer.versionTags(query);
    final has = TextNormalizer.versionTags(song.title);
    if (has.difference(wanted).isNotEmpty) score *= 0.8;
    return score.clamp(0.0, 1.0);
  }

  double artistSimilarity(String a, String b) {
    final sa = TextNormalizer.artists(a);
    final sb = TextNormalizer.artists(b);
    if (sa.isEmpty || sb.isEmpty) return 0.5; // unknown → neutral
    var best = 0.0;
    for (final x in sa) {
      for (final y in sb) {
        best = math.max(best, stringSimilarity(x, y));
      }
    }
    return best;
  }

  double _durationScore(Song a, Song b) {
    final da = a.duration, db = b.duration;
    // Previews are ~30 s regardless of the song length — duration says nothing.
    if (da == null || db == null || a.isPreview || b.isPreview) return 0.5;
    if (da == Duration.zero || db == Duration.zero) return 0.5;
    final diff = (da.inSeconds - db.inSeconds).abs();
    if (diff <= 3) return 1;
    if (diff <= 10) return 0.8;
    if (diff <= 30) return 0.4;
    return 0;
  }

  /// Max of token-set similarity and normalised Levenshtein ratio.
  static double stringSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final ta = TextNormalizer.tokens(a), tb = TextNormalizer.tokens(b);
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    final jaccard = union == 0 ? 0.0 : inter / union;
    final lev = 1 - _lev(a, b) / math.max(a.length, b.length);
    return math.max(jaccard, lev);
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      final t = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }
}
