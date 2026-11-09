import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Jamendo — independent Creative Commons catalogue with full-length MP3
/// streams.
///
/// **Licensing:** the free Jamendo API is for *non-commercial* use only.
/// This source is therefore only registered when the build sets
/// `JAMENDO_COMMERCIAL_AGREEMENT=true` *and* `JAMENDO_CLIENT_ID`, i.e. after
/// you have a commercial agreement with Jamendo (licensing@jamendo.com).
class JamendoSource extends MusicSource {
  JamendoSource({ApiClient? client, String? clientId})
      : _client = client ?? ApiClient(),
        _clientId = clientId ?? AppConfig.jamendoClientId;

  final ApiClient _client;
  final String _clientId;

  static const sourceInfo = SourceInfo(
    id: 'jamendo',
    displayName: 'Jamendo',
    fullTracks: true,
    previews: false,
    commercialStatus: CommercialStatus.requiresAgreement,
    attribution: 'Music from Jamendo (Creative Commons)',
    homepage: 'https://www.jamendo.com',
  );

  static bool get isConfigured =>
      AppConfig.jamendoCommercialAgreement &&
      AppConfig.jamendoClientId.isNotEmpty;

  @override
  SourceInfo get info => sourceInfo;

  Uri _uri(String path, Map<String, String> query) =>
      Uri.https('api.jamendo.com', '/v3.0$path', {
        'client_id': _clientId,
        'format': 'json',
        'audioformat': 'mp32',
        'include': 'licenses',
        ...query,
      });

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetch(_uri('/tracks/', {
      'search': q,
      'limit': '${limit.clamp(1, 200)}',
      'order': 'relevance',
    }));
  }

  @override
  Future<List<Song>> featuredTracks({int limit = 30}) => _fetch(_uri(
        '/tracks/',
        {'limit': '${limit.clamp(1, 200)}', 'order': 'popularity_week'},
      ));

  @override
  Future<List<Song>> artistTracks(String artistId, {int limit = 50}) =>
      _fetch(_uri('/tracks/', {'artist_id': artistId, 'limit': '$limit'}));

  @override
  Future<List<Song>> albumTracks(String albumId) =>
      _fetch(_uri('/tracks/', {'album_id': albumId, 'limit': '200'}));

  Future<List<Song>> _fetch(Uri uri) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseTracks(body);
  }

  static List<Song> parseTracks(Map<String, dynamic> body) {
    final headers = body['headers'];
    if (headers is Map && headers['status'] != 'success') {
      throw SourceException(
        sourceInfo.id,
        '${headers['error_message'] ?? 'Jamendo API error'}',
      );
    }
    final results = body['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJamendoJson)
        .where((s) => s.id.isNotEmpty && s.audioUrl.trim().isNotEmpty)
        .toList(growable: false);
  }
}
