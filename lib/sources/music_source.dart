import '../models/song.dart';

/// How a provider's terms relate to *this* app's business model (a paid,
/// one-time-purchase app). Shown in Settings → Sources and documented in
/// docs/PROVIDER_LICENSING.md.
enum CommercialStatus {
  /// Terms permit use in a commercial app for the way we use it.
  permitted,

  /// Usable only for metadata / promotion (e.g. store previews + store link).
  promotionalOnly,

  /// Needs a signed commercial agreement before it may be enabled.
  requiresAgreement,
}

/// Static description of a provider — used by the registry, the settings
/// screen and the licensing matrix.
class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.displayName,
    required this.fullTracks,
    required this.previews,
    required this.commercialStatus,
    required this.attribution,
    required this.homepage,
  });

  final String id;
  final String displayName;

  /// Provider may return authorised full-length streams.
  final bool fullTracks;

  /// Provider may return short previews.
  final bool previews;
  final CommercialStatus commercialStatus;

  /// Attribution text the UI must show next to this provider's content.
  final String attribution;
  final String homepage;
}

/// Thrown by sources for recoverable failures (network, HTTP, parse). The
/// aggregator catches these per-source so one failing provider never breaks
/// search as a whole.
class SourceException implements Exception {
  const SourceException(this.sourceId, this.message, {this.statusCode});

  final String sourceId;
  final String message;
  final int? statusCode;

  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'SourceException[$sourceId]($statusCode): $message';
}

/// A pluggable music provider. Add a provider by implementing this interface
/// and registering it in `sourceRegistryProvider` — no other code changes.
abstract class MusicSource {
  SourceInfo get info;

  String get id => info.id;

  /// Search tracks. Must return only tracks with the correct
  /// [Song.playability] for this provider's terms.
  Future<List<Song>> searchTracks(String query, {int limit = 25});

  /// Popular / featured tracks for the home screen, if supported.
  Future<List<Song>> featuredTracks({int limit = 30}) async => const [];

  /// Tracks by an artist, if the provider has artist pages.
  Future<List<Song>> artistTracks(String artistId, {int limit = 50}) async =>
      const [];

  /// Tracks of an album, if the provider has album pages.
  Future<List<Song>> albumTracks(String albumId) async => const [];

  /// Returns a playable URI for [song], resolving lazily if needed (e.g.
  /// Internet Archive needs a metadata call to find the audio file).
  /// Returns null when the track cannot be played.
  Future<Uri?> resolveStream(Song song) async {
    if (!song.canPlay || song.audioUrl.isEmpty) return null;
    return Uri.tryParse(song.audioUrl);
  }
}
