import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Audius — decentralised streaming platform whose artists publish tracks for
/// streaming through the public API. Full-length streams, no key required for
/// read endpoints (an `app_name` is requested for production apps).
///
/// Gated tracks (`stream_conditions` / `access.stream == false`, e.g. pay-to-
/// unlock or follow-gated) are excluded: the app must not play them.
///
/// Docs: https://docs.audius.org — terms: Audius API Terms + Open Music
/// Licence (July 2025). See docs/PROVIDER_LICENSING.md.
class AudiusSource extends MusicSource {
  AudiusSource({ApiClient? client, String? host})
      : _client = client ?? ApiClient(),
        _host = host ?? AppConfig.audiusHost;

  final ApiClient _client;
  final String _host;

  static const sourceInfo = SourceInfo(
    id: 'audius',
    displayName: 'Audius',
    fullTracks: true,
    previews: false,
    commercialStatus: CommercialStatus.permitted,
    attribution: 'Streaming via Audius',
    homepage: 'https://audius.co',
    kind: SourceKind.fullTrack,
    capabilities: {SourceCapability.metadata, SourceCapability.artwork, SourceCapability.fullTrackStream, SourceCapability.artistInfo},
    perTrackLicence: false,
  );

  @override
  SourceInfo get info => sourceInfo;

  Uri _uri(String path, [Map<String, String> query = const {}]) => Uri.https(
        _host,
        path,
        {...query, 'app_name': AppConfig.audiusAppName},
      );

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetch(
      _uri('/v1/tracks/search', {'query': q, 'limit': '${limit.clamp(1, 50)}'}),
    );
  }

  @override
  Future<List<Song>> featuredTracks({int limit = 30}) =>
      _fetch(_uri('/v1/tracks/trending', {'limit': '${limit.clamp(1, 100)}'}));

  @override
  Future<List<Song>> artistTracks(String artistId, {int limit = 50}) {
    if (artistId.isEmpty) return Future.value(const []);
    return _fetch(
      _uri('/v1/users/$artistId/tracks', {
        'limit': '${limit.clamp(1, 100)}',
        'sort': 'plays',
      }),
    );
  }

  @override
  Future<List<Song>> albumTracks(String albumId) {
    if (albumId.isEmpty) return Future.value(const []);
    return _fetch(_uri('/v1/playlists/$albumId/tracks'));
  }

  /// Artists (Audius users) matching [name], most-followed first.
  Future<List<AudiusArtist>> searchArtists(String name, {int limit = 10}) async {
    final q = name.trim();
    if (q.isEmpty) return const [];
    final Map<String, dynamic> body;
    try {
      body = await _client.get(_uri('/v1/users/search', {'query': q, 'limit': '${limit.clamp(1, 50)}'}));
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseArtists(body);
  }

  /// One track by id (null when removed, gated or not streamable).
  Future<Song?> trackById(String trackId) async {
    if (trackId.isEmpty) return null;
    final Map<String, dynamic> body;
    try {
      body = await _client.get(_uri('/v1/tracks/$trackId'));
    } on ApiException catch (e) {
      if (e.isNotFound) return null;
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    final data = body['data'];
    return data is Map<String, dynamic> ? parseTrack(data, host: _host) : null;
  }

  static List<AudiusArtist> parseArtists(Map<String, dynamic> body) {
    final raw = body['data'];
    if (raw is! List) return const [];
    final out = <AudiusArtist>[];
    for (final u in raw.whereType<Map<String, dynamic>>()) {
      final id = u['id']?.toString() ?? '';
      final name = (u['name'] as String? ?? '').trim();
      if (id.isEmpty || name.isEmpty) continue;
      out.add(AudiusArtist(
        id: id,
        name: name,
        handle: (u['handle'] as String? ?? '').trim(),
        followers: (u['follower_count'] as num?)?.toInt() ?? 0,
        verified: u['is_verified'] == true,
      ));
    }
    out.sort((a, b) => b.followers.compareTo(a.followers));
    return out;
  }

  Future<List<Song>> _fetch(Uri uri) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseTracks(body, host: _host);
  }

  /// Parses `{ "data": [track, …] }`. Public for unit tests.
  static List<Song> parseTracks(Map<String, dynamic> body, {String? host}) {
    final raw = body['data'];
    if (raw is! List) return const [];
    final out = <Song>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final song = parseTrack(item, host: host ?? AppConfig.audiusHost);
        if (song != null) out.add(song);
      }
    }
    return out;
  }

  static Song? parseTrack(Map<String, dynamic> json, {required String host}) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    // Never surface gated / non-streamable content as playable.
    if (json['is_streamable'] == false) return null;
    if (json['is_delete'] == true) return null;
    final conditions = json['stream_conditions'];
    if (conditions != null && conditions is Map && conditions.isNotEmpty) {
      return null;
    }
    final access = json['access'];
    if (access is Map && access['stream'] == false) return null;

    final user = json['user'];
    var artist = '';
    var artistId = '';
    if (user is Map) {
      final name = user['name'];
      if (name is String) artist = name.trim();
      artistId = user['id']?.toString() ?? '';
    }

    final permalink = json['permalink'];
    return Song(
      id: id, // un-prefixed for compatibility with v1 libraries
      title: (json['title'] as String?)?.trim() ?? '',
      artist: artist,
      album: '',
      audioUrl: Uri.https(
        host,
        '/v1/tracks/$id/stream',
        {'app_name': AppConfig.audiusAppName},
      ).toString(),
      coverUrl: _artwork(json['artwork']),
      duration: _duration(json['duration']),
      sourceId: sourceInfo.id,
      playability: Playability.full,
      externalUrl: permalink is String && permalink.isNotEmpty
          ? 'https://audius.co$permalink'
          : '',
      artistId: artistId,
      // Artist-declared licence (e.g. "All rights reserved", a CC licence).
      // Streaming in third-party apps is governed by the Audius API Terms.
      license: (json['license'] as String?)?.trim() ?? '',
      isrc: (json['isrc'] as String?)?.trim() ?? '',
    );
  }

  static String _artwork(dynamic artwork) {
    if (artwork is String) return artwork.trim();
    if (artwork is Map) {
      for (final key in ['480x480', '1000x1000', '150x150']) {
        final v = artwork[key];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return '';
  }

  static Duration? _duration(dynamic value) {
    if (value is num) return Duration(seconds: value.round());
    if (value is String) {
      final s = int.tryParse(value);
      if (s != null) return Duration(seconds: s);
    }
    return null;
  }
}

class AudiusArtist {
  const AudiusArtist({
    required this.id,
    required this.name,
    required this.handle,
    required this.followers,
    required this.verified,
  });

  final String id;
  final String name;
  final String handle;
  final int followers;

  /// Audius-verified account (the artist's own profile).
  final bool verified;
}
