import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// MusicBrainz — open music encyclopedia (https://musicbrainz.org).
///
/// **Metadata only**: recordings, artist credits, releases, durations and
/// ISRCs. Never an audio source. Strong for identifying the *exact* original
/// recording (ISRC), including Bengali releases.
///
/// Rules (https://musicbrainz.org/doc/MusicBrainz_API): a meaningful
/// User-Agent with contact details, about 1 request/second, and a MetaBrainz
/// commercial plan for commercial use — hence off unless
/// `MUSICBRAINZ_ENABLED=true`. Browsers cannot set a User-Agent, so on web
/// the browser's own agent is sent.
class MusicBrainzSource extends MusicSource {
  MusicBrainzSource({ApiClient? client, String? contact})
      : _client = client ?? ApiClient(timeout: const Duration(seconds: 10)),
        _contact = contact ?? AppConfig.musicBrainzContact;

  final ApiClient _client;
  final String _contact;

  static const sourceInfo = SourceInfo(
    id: 'musicbrainz',
    displayName: 'MusicBrainz',
    fullTracks: false,
    previews: false,
    commercialStatus: CommercialStatus.requiresAgreement,
    attribution: 'Recording data from MusicBrainz',
    homepage: 'https://musicbrainz.org',
    kind: SourceKind.metadata,
    capabilities: {SourceCapability.metadata, SourceCapability.isrc, SourceCapability.artistInfo},
  );

  @override
  SourceInfo get info => sourceInfo;

  Map<String, String>? get _headers =>
      kIsWeb ? null : {'User-Agent': '${AppConfig.appName}/1.0 ( $_contact )'};

  /// Lucene query for a free-text search: phrase match on recording or artist.
  static String buildQuery(String query) {
    final q = query.trim().replaceAll(RegExp(r'["\\:]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    return '(recording:"$q") OR (artist:"$q") OR ($q)';
  }

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetch(Uri.https('musicbrainz.org', '/ws/2/recording', {
      'query': buildQuery(q),
      'fmt': 'json',
      'limit': '${limit.clamp(1, 100)}',
    }));
  }

  /// Recordings carrying an ISRC (exact recording identification).
  Future<List<Song>> lookupIsrc(String isrc) async {
    final code = isrc.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (code.length != 12) return const [];
    return _fetch(Uri.https('musicbrainz.org', '/ws/2/isrc/$code', {
      'fmt': 'json',
      'inc': 'artist-credits+releases+isrcs',
    }));
  }

  Future<List<Song>> _fetch(Uri uri) async {
    final Map<String, dynamic> body;
    try {
      body = await _client.get(uri, headers: _headers);
    } on ApiException catch (e) {
      throw SourceException(id, e.message, statusCode: e.statusCode);
    }
    return parseRecordings(body);
  }

  static List<Song> parseRecordings(Map<String, dynamic> body) {
    final list = body['recordings'];
    if (list is! List) return const [];
    final out = <Song>[];
    for (final r in list.whereType<Map<String, dynamic>>()) {
      final id = r['id'] as String? ?? '';
      final title = (r['title'] as String? ?? '').trim();
      if (id.isEmpty || title.isEmpty) continue;
      final credits = r['artist-credit'];
      final artist = credits is List
          ? credits.whereType<Map>().map((c) => '${c['name'] ?? ''}${c['joinphrase'] ?? ''}').join().trim()
          : '';
      final length = r['length'];
      final isrcs = r['isrcs'];
      final releases = r['releases'];
      final release = releases is List && releases.isNotEmpty && releases.first is Map
          ? releases.first as Map
          : const {};
      out.add(Song(
        id: 'musicbrainz:$id',
        title: title,
        artist: artist,
        album: (release['title'] as String?) ?? '',
        audioUrl: '',
        coverUrl: '',
        duration: length is num ? Duration(milliseconds: length.round()) : null,
        sourceId: sourceInfo.id,
        playability: Playability.none,
        externalUrl: 'https://musicbrainz.org/recording/$id',
        albumId: (release['id'] as String?) ?? '',
        isrc: isrcs is List && isrcs.isNotEmpty ? '${isrcs.first}' : '',
      ));
    }
    return out;
  }
}
