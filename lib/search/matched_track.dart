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
  });

  final Song display;
  final List<Song> candidates;

  /// Metadata-only entries (e.g. catalogue rows) merged into this track.
  final List<Song> references;
  final double relevance;

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
  });

  final String query;
  final List<MatchedTrack> tracks;

  /// sourceId → human-readable reason.
  final Map<String, String> failedSources;
  final bool fromCache;

  bool get allSourcesFailed => tracks.isEmpty && failedSources.isNotEmpty;

  /// Flat list of what can actually be played, in ranking order.
  List<Song> get playableSongs =>
      [for (final t in tracks) if (t.isPlayable) t.best];
}
