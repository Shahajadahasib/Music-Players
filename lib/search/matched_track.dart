import '../models/song.dart';

/// One song as the user sees it, merged from every provider that returned it.
///
/// [display] carries the best metadata (catalogue data from iTunes when
/// available); [candidates] are the *playable* versions ordered best-first
/// (full tracks before previews, remembered/most reliable provider first).
class MatchedTrack {
  const MatchedTrack({
    required this.display,
    required this.candidates,
    required this.relevance,
    this.references = const [],
    this.isBestMatch = false,
    this.verifiedIds = const {},
  });

  final Song display;
  final List<Song> candidates;

  /// Metadata-only entries (e.g. catalogue rows) merged into this track.
  final List<Song> references;
  final double relevance;

  /// The catalogue song the query named (shown first as "Best match").
  final bool isBestMatch;

  /// Candidate ids whose stream was verified during the search.
  final Set<String> verifiedIds;

  /// A catalogue recording for which no authorised full-track source holds
  /// the *original* recording.
  bool get originalUnavailable => isBestMatch && candidates.isEmpty;

  /// The song to put in the queue: best playable candidate (with catalogue
  /// metadata), or the display entry when nothing is playable.
  Song get best => candidates.isNotEmpty ? candidates.first : display;

  bool get hasFullTrack => candidates.any((c) => c.playability == Playability.full);

  bool get previewOnly => !hasFullTrack && candidates.any((c) => c.isPreview);

  bool get isPlayable => candidates.isNotEmpty;

  /// Providers that can play this track (for the "Full track · Audius" badge).
  List<String> get playableSourceIds =>
      {for (final c in candidates) c.sourceId}.toList(growable: false);

  /// Link for "Open in…" when the track can't be streamed here.
  String get externalUrl => display.externalUrl.isNotEmpty
      ? display.externalUrl
      : references.map((r) => r.externalUrl).firstWhere(
            (u) => u.isNotEmpty,
            orElse: () => '',
          );
}

/// Aggregated search result with per-provider diagnostics so the UI can tell
/// "no results" apart from "a provider is down".
class AggregatedSearchResult {
  const AggregatedSearchResult({
    required this.query,
    required this.tracks,
    this.failedSources = const {},
    this.fromCache = false,
    this.attempts = const [],
    this.cancelled = false,
  });

  final String query;
  final List<MatchedTrack> tracks;

  /// sourceId → human-readable reason.
  final Map<String, String> failedSources;
  final bool fromCache;

  /// Providers asked, in order, and what each one answered.
  final List<ProviderAttempt> attempts;

  /// A newer search superseded this one before it finished.
  final bool cancelled;

  MatchedTrack? get bestMatch {
    for (final t in tracks) {
      if (t.isBestMatch) return t;
    }
    return null;
  }

  bool get allSourcesFailed => tracks.isEmpty && failedSources.isNotEmpty;

  /// Flat list of what can actually be played, in ranking order.
  List<Song> get playableSongs =>
      [for (final t in tracks) if (t.isPlayable) t.best];
}

/// What one provider answered during a search / discovery.
class ProviderAttempt {
  const ProviderAttempt(this.sourceId, this.outcome, {this.detail = ''});

  final String sourceId;
  final AttemptOutcome outcome;
  final String detail;

  bool get isFailure =>
      outcome == AttemptOutcome.timeout ||
      outcome == AttemptOutcome.error ||
      outcome == AttemptOutcome.rateLimited;

  @override
  String toString() => '$sourceId: ${outcome.name}${detail.isEmpty ? '' : ' ($detail)'}';
}

enum AttemptOutcome {
  /// Exact original found and its stream verified — search stopped here.
  verified,

  /// Returned results (free-text search) — search stopped here.
  results,

  /// Answered, but had no acceptable original / no relevant results.
  noMatch,

  /// Had the exact recording, but none of its streams were playable.
  unplayable,
  timeout,
  rateLimited,
  error,
}

/// Outcome of looking for an authorised full-track source of one recording.
class Discovery {
  const Discovery({
    required this.reference,
    this.playable,
    this.alternates = const [],
    this.attempts = const [],
    this.fromCache = false,
  });

  final Song reference;

  /// Verified exact recording to play, or null when none exists.
  final Song? playable;

  /// Other exact matches of the same recording (not yet verified).
  final List<Song> alternates;
  final List<ProviderAttempt> attempts;
  final bool fromCache;

  bool get found => playable != null;

  Set<String> get searchedSources => {for (final a in attempts) a.sourceId};

  /// Short explanation for the UI when nothing was found.
  String get explanation {
    if (found) return '';
    final failed = attempts.where((a) => a.isFailure).map((a) => a.sourceId).toList();
    if (attempts.isNotEmpty && failed.length == attempts.length) {
      return 'Music services could not be reached.';
    }
    return 'Original recording unavailable from authorised streaming sources.';
  }
}
