import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Internet Archive audio items, **restricted to licences that allow
/// commercial redistribution**: public domain marks, CC0, CC BY and CC BY-SA.
/// Non-commercial (NC) and no-licence items are never requested.
///
/// Caveat (documented in docs/PROVIDER_LICENSING.md): licences on archive.org
/// are declared by uploaders and are not verified by the Archive. Keep this
/// source user-toggleable and honour take-down requests.
class InternetArchiveSource extends MusicSource {
  InternetArchiveSource({ApiClient? client})
      : _client = client ?? ApiClient(timeout: const Duration(seconds: 10));

  final ApiClient _client;
  final Map<String, Uri> _resolved = {};

  static const sourceInfo = SourceInfo(
    id: 'archive',
    displayName: 'Internet Archive (public domain & CC BY)',
    fullTracks: true,
    previews: false,
    commercialStatus: CommercialStatus.permitted,
    attribution: 'Audio from the Internet Archive — see licence on each item',
    homepage: 'https://archive.org',
  );

  /// Lucene clause selecting commercially re-usable licences only.
  static const String licenceFilter = '(licenseurl:*publicdomain* OR '
      'licenseurl:*creativecommons.org/licenses/by/* OR '
      'licenseurl:*creativecommons.org/licenses/by-sa/*)';

  @override
  SourceInfo get info => sourceInfo;

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim().replaceAll(RegExp(r'[():"\\]'), ' ');
    if (q.isEmpty) return const [];
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': '($q) AND mediatype:(audio) AND $licenceFilter',
      'fl[]': ['identifier', 'title', 'creator', 'licenseurl'],
      'rows': '${limit.clamp(1, 50)}',
      'page': '1',
      'output': 'json',
    });
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseSearch(body);
  }

  static List<Song> parseSearch(Map<String, dynamic> body) {
    final response = body['response'];
    if (response is! Map) return const [];
    final docs = response['docs'];
    if (docs is! List) return const [];
    final out = <Song>[];
    for (final d in docs.whereType<Map<String, dynamic>>()) {
      final ident = d['identifier'] as String? ?? '';
      final licence = _first(d['licenseurl']);
      if (ident.isEmpty || !isCommercialLicence(licence)) continue;
      out.add(Song(
        id: 'archive:$ident',
        title: _first(d['title']),
        artist: _first(d['creator']),
        album: '',
        audioUrl: '', // resolved lazily from the item metadata
        coverUrl: 'https://archive.org/services/img/${Uri.encodeComponent(ident)}',
        sourceId: sourceInfo.id,
        playability: Playability.full,
        externalUrl: 'https://archive.org/details/${Uri.encodeComponent(ident)}',
        license: licence,
      ));
    }
    return out;
  }

  /// Defence in depth: re-check the licence client-side.
  static bool isCommercialLicence(String url) {
    final u = url.toLowerCase();
    if (u.isEmpty) return false;
    if (u.contains('publicdomain')) return true;
    if (u.contains('-nc') || u.contains('/nc')) return false;
    return u.contains('creativecommons.org/licenses/by/') ||
        u.contains('creativecommons.org/licenses/by-sa/');
  }

  @override
  Future<Uri?> resolveStream(Song song) async {
    final ident = song.id.startsWith('archive:') ? song.id.substring(8) : '';
    if (ident.isEmpty) return null;
    final cached = _resolved[ident];
    if (cached != null) return cached;
    final Map<String, dynamic> body;
    try {
      body = await _client.get(
        Uri.https('archive.org', '/metadata/$ident'),
      );
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    final uri = pickAudioFile(ident, body);
    if (uri != null) _resolved[ident] = uri;
    return uri;
  }

  /// Picks the first original-order MP3 (falls back to OGG) from an item.
  static Uri? pickAudioFile(String ident, Map<String, dynamic> metadata) {
    final files = metadata['files'];
    if (files is! List) return null;
    Map<String, dynamic>? best;
    for (final f in files.whereType<Map<String, dynamic>>()) {
      final format = (f['format'] as String? ?? '').toLowerCase();
      if (format.contains('mp3')) {
        best = f;
        break;
      }
      if (best == null && format.contains('ogg')) best = f;
    }
    final name = best?['name'] as String?;
    if (name == null || name.isEmpty) return null;
    // Uri.https percent-encodes the path itself.
    return Uri.https('archive.org', '/download/$ident/$name');
  }

  static String _first(dynamic v) {
    if (v is String) return v.trim();
    if (v is List && v.isNotEmpty) return v.first.toString().trim();
    return '';
  }
}
