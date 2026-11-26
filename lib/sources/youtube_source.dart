import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// YouTube Data API v3 — finds official videos; playback **only** in the
/// official YouTube player, opened externally. The app never extracts,
/// downloads or converts audio, and claims no background playback for it
/// (YouTube API Services Developer Policies prohibit separating audio).
///
/// Needs `YOUTUBE_API_KEY` (restrict it to your app in Google Cloud). The
/// default quota is 10,000 units/day and each search costs 100 units, so it
/// is used sparingly: only to offer an official link when an original
/// recording has no authorised in-app stream.
class YouTubeSource extends MusicSource {
  YouTubeSource({ApiClient? client, String? apiKey})
      : _client = client ?? ApiClient(),
        _key = apiKey ?? AppConfig.youtubeApiKey;

  final ApiClient _client;
  final String _key;

  static const sourceInfo = SourceInfo(
    id: 'youtube',
    displayName: 'YouTube',
    fullTracks: false,
    previews: false,
    commercialStatus: CommercialStatus.promotionalOnly,
    attribution: 'Opens in the official YouTube player',
    homepage: 'https://www.youtube.com',
    kind: SourceKind.externalPlayer,
    capabilities: {SourceCapability.metadata, SourceCapability.artwork, SourceCapability.externalPlayer},
  );

  static bool get isConfigured => AppConfig.youtubeApiKey.isNotEmpty;

  @override
  SourceInfo get info => sourceInfo;

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 10}) async {
    final q = query.trim();
    if (q.isEmpty || _key.isEmpty) return const [];
    final Map<String, dynamic> body;
    try {
      body = await _client.get(Uri.https('www.googleapis.com', '/youtube/v3/search', {
        'part': 'snippet',
        'type': 'video',
        'videoCategoryId': '10', // Music
        'videoEmbeddable': 'true',
        'maxResults': '${limit.clamp(1, 25)}',
        'q': q,
        'key': _key,
      }));
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseSearch(body);
  }

  static List<Song> parseSearch(Map<String, dynamic> body) {
    final items = body['items'];
    if (items is! List) return const [];
    final out = <Song>[];
    for (final it in items.whereType<Map<String, dynamic>>()) {
      final idMap = it['id'];
      final videoId = idMap is Map ? idMap['videoId'] as String? ?? '' : '';
      final snip = it['snippet'];
      if (videoId.isEmpty || snip is! Map) continue;
      final rawTitle = unescape(snip['title'] as String? ?? '');
      final channel = cleanChannel(unescape(snip['channelTitle'] as String? ?? ''));
      var title = rawTitle;
      var artist = channel;
      // "Artist - Title (Official Video)" → split when the left side is the
      // channel's artist.
      final dash = rawTitle.indexOf(' - ');
      if (dash > 0) {
        final left = rawTitle.substring(0, dash).trim();
        if (channel.isEmpty || left.toLowerCase().contains(channel.toLowerCase()) ||
            channel.toLowerCase().contains(left.toLowerCase())) {
          artist = left;
          title = rawTitle.substring(dash + 3).trim();
        }
      }
      final thumbs = snip['thumbnails'];
      String thumb = '';
      if (thumbs is Map) {
        for (final k in ['high', 'medium', 'default']) {
          final t = thumbs[k];
          if (t is Map && t['url'] is String) {
            thumb = t['url'] as String;
            break;
          }
        }
      }
      out.add(Song(
        id: 'youtube:$videoId',
        title: title,
        artist: artist,
        album: '',
        audioUrl: '', // never a direct audio URL
        coverUrl: thumb,
        sourceId: sourceInfo.id,
        playability: Playability.external,
        externalUrl: 'https://www.youtube.com/watch?v=$videoId',
      ));
    }
    return out;
  }

  /// "Ed Sheeran - Topic" / "EdSheeranVEVO" / "Ed Sheeran Official" → artist.
  static String cleanChannel(String channel) => channel
      .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+(Official|Music|Official Channel)$', caseSensitive: false), '')
      .trim();

  static String unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  @override
  Future<Uri?> resolveStream(Song song) async => null; // external player only
}
