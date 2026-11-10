import 'package:equatable/equatable.dart';

/// What the app is allowed (and able) to do with a track's audio.
///
/// This is decided by the *provider integration* according to that provider's
/// terms — never by the UI.
enum Playability {
  /// Authorised full-length stream (e.g. Audius, licensed Jamendo, public
  /// domain / CC-BY Internet Archive items).
  full,

  /// Short promotional clip only (e.g. 30-second store previews).
  preview,

  /// Metadata only — the app may display it and link out, but must not play it.
  none,

  /// A file the user picked from their own device.
  local,
}

class Song extends Equatable {
  /// Parses a single track item from the Jamendo `/v3.0/tracks/` JSON response.
  ///
  /// Expected shape (with `audioformat=mp32`):
  /// ```json
  /// {
  ///   "id": "1234",
  ///   "name": "Track Name",
  ///   "artist_name": "Artist",
  ///   "album_name": "Album",
  ///   "audio": "https://mp3d.jamendo.com/...",
  ///   "image": "https://usercontent.jamendo.com/...",
  ///   "duration": 245
  /// }
  /// ```
  factory Song.fromJamendoJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId?.toString() ?? '';

    final durationSeconds = json['duration'];
    final Duration? duration;
    if (durationSeconds is int) {
      duration = Duration(seconds: durationSeconds);
    } else if (durationSeconds is String) {
      final parsed = int.tryParse(durationSeconds);
      duration = parsed != null ? Duration(seconds: parsed) : null;
    } else {
      duration = null;
    }

    final licence = json['license_ccurl'];
    return Song(
      id: id.isEmpty ? '' : 'jamendo:$id',
      title: (json['name'] as String?) ?? '',
      artist: (json['artist_name'] as String?) ?? '',
      album: (json['album_name'] as String?) ?? '',
      audioUrl: (json['audio'] as String?) ?? '',
      coverUrl: (json['image'] as String?) ?? '',
      duration: duration,
      sourceId: 'jamendo',
      externalUrl: (json['shareurl'] as String?) ?? '',
      license: licence is String ? licence : '',
      artistId: json['artist_id']?.toString() ?? '',
      albumId: json['album_id']?.toString() ?? '',
    );
  }

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.audioUrl,
    required this.coverUrl,
    this.duration,
    this.sourceId = 'audius',
    this.playability = Playability.full,
    this.externalUrl = '',
    this.license = '',
    this.artistId = '',
    this.albumId = '',
  });

  /// Globally unique id. Audius ids are stored un-prefixed for backwards
  /// compatibility with libraries saved by earlier versions; every other
  /// provider uses `<provider>:<id>`.
  final String id;
  final String title;
  final String artist;
  final String album;

  /// Direct stream URL. May be empty for providers that resolve the stream
  /// lazily (see `MusicSource.resolveStream`) or for metadata-only results.
  final String audioUrl;
  final String coverUrl;
  final Duration? duration;

  /// Which `MusicSource` produced this track (`audius`, `jamendo`, `itunes`,
  /// `archive`, `local`).
  final String sourceId;
  final Playability playability;

  /// Public page for the track on the provider (attribution / "open in…").
  final String externalUrl;

  /// Licence name or URL when the provider supplies one (e.g. CC BY 4.0).
  final String license;

  /// Provider-specific artist / album ids, used for artist & album pages.
  final String artistId;
  final String albumId;

  /// True when the app may play this track's audio at all.
  bool get canPlay => playability != Playability.none;

  bool get isPreview => playability == Playability.preview;

  bool get isLocal => playability == Playability.local;

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? audioUrl,
    String? coverUrl,
    Duration? duration,
    bool clearDuration = false,
    String? sourceId,
    Playability? playability,
    String? externalUrl,
    String? license,
    String? artistId,
    String? albumId,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      audioUrl: audioUrl ?? this.audioUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: clearDuration ? null : (duration ?? this.duration),
      sourceId: sourceId ?? this.sourceId,
      playability: playability ?? this.playability,
      externalUrl: externalUrl ?? this.externalUrl,
      license: license ?? this.license,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        artist,
        album,
        audioUrl,
        coverUrl,
        duration,
        sourceId,
        playability,
        externalUrl,
        license,
        artistId,
        albumId,
      ];
}
