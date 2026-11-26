import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Free To Use (https://freetouse.com) — royalty-free tracks by real artists,
/// public API without a key (https://api.freetouse.com/v3/openapi.json).
///
/// **Licensing:** the API itself says free usage is available under specific
/// conditions and commercial use requires a paid licence. Free use requires
/// attribution and excludes commercial digital products, so this paid app may
/// stream these tracks only with a Free To Use Commercial plan →
/// registered only when `FREETOUSE_COMMERCIAL_LICENSE=true`.
/// Premium (`is_premium`) tracks are never streamed.
class FreeToUseSource extends MusicSource {
  FreeToUseSource({ApiClient? client})
      : _client = client ?? ApiClient();

  final ApiClient _client;

  static const sourceInfo = SourceInfo(
    id: 'freetouse',
    displayName: 'Free To Use',
    fullTracks: true,
    previews: false,
    commercialStatus: CommercialStatus.requiresAgreement,
    attribution: 'Music from Free To Use (freetouse.com)',
    homepage: 'https://freetouse.com',
    kind: SourceKind.fullTrack,
    capabilities: {
      SourceCapability.metadata,
      SourceCapability.artwork,
      SourceCapability.fullTrackStream,
      SourceCapability.artistInfo,
    },
    perTrackLicence: true,
  );

  static bool get isConfigured => AppConfig.freeToUseCommercialLicence;

  @override
  SourceInfo get info => sourceInfo;

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetch(Uri.https('api.freetouse.com', '/v3/music/tracks/search', {
      'query': q,
      'limit': '${limit.clamp(1, 50)}',
    }));
  }

  @override
  Future<List<Song>> featuredTracks({int limit = 30}) =>
      _fetch(Uri.https('api.freetouse.com', '/v3/music/tracks/all', {'limit': '${limit.clamp(1, 50)}'}));

  @override
  Future<List<Song>> artistTracks(String artistId, {int limit = 50}) {
    if (artistId.isEmpty) return Future.value(const []);
    return _fetch(Uri.https('api.freetouse.com', '/v3/music/artists/$artistId/tracks', {'limit': '$limit'}));
  }

  Future<List<Song>> _fetch(Uri uri) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    if (body['ok'] == false) throw SourceException(id, 'Free To Use API error');
    return parseTracks(body);
  }

  static List<Song> parseTracks(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! List) return const [];
    final out = <Song>[];
    for (final t in data.whereType<Map<String, dynamic>>()) {
      final id = t['id'] as String? ?? '';
      final title = (t['title'] as String? ?? '').trim();
      if (id.isEmpty || title.isEmpty || t['status'] != 1) continue;
      final files = t['files'];
      final mp3 = files is Map ? files['mp3'] as String? ?? '' : '';
      final premium = t['is_premium'] == true;
      final artists = _names(t['artists']);
      final thumbs = t['thumbnails'];
      final cover = thumbs is Map ? (thumbs['md'] ?? thumbs['lg'] ?? thumbs['sm'] ?? '') as String : '';
      final playable = mp3.startsWith('https://') && !premium;
      final duration = t['duration'];
      out.add(Song(
        id: 'freetouse:$id',
        title: title,
        artist: artists.join(', '),
        album: '',
        audioUrl: playable ? mp3 : '',
        coverUrl: cover.startsWith('https://') ? cover : '',
        duration: duration is num ? Duration(milliseconds: (duration * 1000).round()) : null,
        sourceId: sourceInfo.id,
        playability: playable ? Playability.full : Playability.none,
        externalUrl: 'https://freetouse.com/music',
        license: 'Free To Use Commercial licence',
        artistId: _firstId(t['artists']),
      ));
    }
    return out;
  }

  /// `artists` is a list of `[index, {id, name}]` pairs.
  static List<String> _names(Object? raw) => [
        if (raw is List)
          for (final e in raw)
            if (e is List && e.length > 1 && e[1] is Map && (e[1] as Map)['name'] is String)
              ((e[1] as Map)['name'] as String).trim(),
      ];

  static String _firstId(Object? raw) {
    if (raw is List && raw.isNotEmpty && raw.first is List) {
      final e = raw.first as List;
      if (e.length > 1 && e[1] is Map) return '${(e[1] as Map)['id'] ?? ''}';
    }
    return '';
  }
}
