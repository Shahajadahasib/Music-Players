import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Apple iTunes Search API — the app's **reference catalogue**.
///
/// Used to identify the "real" song (canonical title, artist, album,
/// duration, artwork) so results from streaming providers can be matched
/// against it. Apple permits previews only to promote store content, so by
/// default results are *metadata-only* ([Playability.none]) with an
/// "Open in Apple Music" link. Preview playback can be enabled with
/// `ITUNES_PREVIEWS=true`; previews are then labelled as such and shown with
/// the store link.
///
/// No key required. Apple asks heavy users to cache results (we do) and
/// rate-limits to roughly 20 requests/minute per client.
class ItunesSource extends MusicSource {
  ItunesSource({ApiClient? client, String? country, bool? previews})
      : _client = client ?? ApiClient(),
        _country = country ?? AppConfig.itunesCountry,
        _previews = previews ?? AppConfig.itunesPreviews;

  final ApiClient _client;
  final String _country;
  final bool _previews;

  static const sourceInfo = SourceInfo(
    id: 'itunes',
    displayName: 'Apple Music catalogue',
    fullTracks: false,
    previews: true,
    commercialStatus: CommercialStatus.promotionalOnly,
    attribution: 'Song information from Apple',
    homepage: 'https://music.apple.com',
  );

  @override
  SourceInfo get info => sourceInfo;

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetch(Uri.https('itunes.apple.com', '/search', {
      'term': q,
      'media': 'music',
      'entity': 'song',
      'limit': '${limit.clamp(1, 200)}',
      'country': _country,
    }));
  }

  @override
  Future<List<Song>> artistTracks(String artistId, {int limit = 50}) =>
      _fetch(Uri.https('itunes.apple.com', '/lookup', {
        'id': artistId,
        'entity': 'song',
        'limit': '$limit',
        'country': _country,
      }));

  @override
  Future<List<Song>> albumTracks(String albumId) =>
      _fetch(Uri.https('itunes.apple.com', '/lookup', {
        'id': albumId,
        'entity': 'song',
        'country': _country,
      }));

  Future<List<Song>> _fetch(Uri uri) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseResults(body, previews: _previews);
  }

  static List<Song> parseResults(
    Map<String, dynamic> body, {
    required bool previews,
  }) {
    final results = body['results'];
    if (results is! List) return const [];
    final out = <Song>[];
    for (final r in results.whereType<Map<String, dynamic>>()) {
      // lookup?entity=song also returns the album/artist wrapper row.
      if (r['wrapperType'] != 'track' || r['kind'] != 'song') continue;
      final trackId = r['trackId']?.toString() ?? '';
      if (trackId.isEmpty) continue;
      final preview = r['previewUrl'] as String? ?? '';
      final canPreview = previews && preview.startsWith('https://');
      final ms = r['trackTimeMillis'];
      out.add(Song(
        id: 'itunes:$trackId',
        title: (r['trackName'] as String?)?.trim() ?? '',
        artist: (r['artistName'] as String?)?.trim() ?? '',
        album: (r['collectionName'] as String?)?.trim() ?? '',
        audioUrl: canPreview ? preview : '',
        coverUrl: _hiResArtwork(r['artworkUrl100'] as String? ?? ''),
        duration: ms is num ? Duration(milliseconds: ms.round()) : null,
        sourceId: sourceInfo.id,
        playability: canPreview ? Playability.preview : Playability.none,
        externalUrl: (r['trackViewUrl'] as String?) ?? '',
        artistId: r['artistId']?.toString() ?? '',
        albumId: r['collectionId']?.toString() ?? '',
      ));
    }
    return out;
  }

  /// `…/100x100bb.jpg` → `…/600x600bb.jpg` (documented Apple artwork pattern).
  static String _hiResArtwork(String url) =>
      url.replaceFirst(RegExp(r'/\d+x\d+bb\.'), '/600x600bb.');
}
