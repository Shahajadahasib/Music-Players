import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/song.dart';
import '../services/api_client.dart';
import 'music_source.dart';

/// Live internet radio from the community-run Radio Browser directory
/// (https://www.radio-browser.info). Its API may be used in free and
/// commercial software. Radio is a **separate feature**: stations never
/// appear in song search and never take part in song matching or fallback.
///
/// The directory is free; each station streams under its own broadcast
/// licence. Apple App Review (guideline 5.2.3) may ask for evidence that you
/// may stream third-party radio — see docs/MUSIC_PROVIDER_RESEARCH.md.
///
/// Only `https` streams are used: Android and iOS block clear-text audio by
/// default and browsers block mixed content.
class RadioSource {
  RadioSource({ApiClient? client, Random? random})
      : _client = client ?? ApiClient(),
        _random = random ?? Random();

  final ApiClient _client;
  final Random _random;
  String? _server;

  static const sourceInfo = SourceInfo(
    id: 'radio',
    displayName: 'Live radio (Radio Browser)',
    fullTracks: false,
    previews: false,
    commercialStatus: CommercialStatus.permitted,
    attribution: 'Station directory by radio-browser.info',
    homepage: 'https://www.radio-browser.info',
    kind: SourceKind.radio,
    capabilities: {SourceCapability.liveRadio, SourceCapability.artwork},
  );

  static bool get isEnabled => AppConfig.radioEnabled;

  static const _fallbackServers = [
    'de1.api.radio-browser.info',
    'de2.api.radio-browser.info',
    'fi1.api.radio-browser.info',
  ];

  /// Radio Browser asks clients to pick among its mirrors.
  Future<String> _host() async {
    if (_server != null) return _server!;
    try {
      final list = await _client.getJson(
        Uri.https('all.api.radio-browser.info', '/json/servers'),
        headers: _headers,
      );
      if (list is List) {
        final names = list
            .whereType<Map>()
            .map((m) => m['name'])
            .whereType<String>()
            .where((n) => n.endsWith('.api.radio-browser.info'))
            .toSet()
            .toList();
        if (names.isNotEmpty) return _server = names[_random.nextInt(names.length)];
      }
    } catch (_) {/* fall through */}
    return _server = _fallbackServers.first;
  }

  /// Browsers forbid setting User-Agent; native apps identify themselves.
  Map<String, String>? get _headers =>
      kIsWeb ? null : {'User-Agent': '${AppConfig.audiusAppName}/1.0'};

  Future<List<Song>> _query(Map<String, String> params) async {
    final host = await _host();
    final Object? body;
    try {
      body = await _client.getJson(
        Uri.https(host, '/json/stations/search', {
          'hidebroken': 'true',
          'is_https': 'true',
          'order': 'votes',
          'reverse': 'true',
          'limit': '30',
          ...params,
        }),
        headers: _headers,
      );
    } on ApiException catch (e) {
      _server = null; // try another mirror next time
      throw SourceException(sourceInfo.id, e.message, statusCode: e.statusCode);
    }
    return parseStations(body);
  }

  /// Station name search ("Radio Foorti", "BBC").
  Future<List<Song>> searchByName(String name) =>
      name.trim().isEmpty ? Future.value(const []) : _query({'name': name.trim()});

  /// Genre / tag ("jazz", "bangla", "islamic").
  Future<List<Song>> searchByTag(String tag) => _query({'tag': tag.trim().toLowerCase()});

  /// ISO 3166-1 country code ("BD", "IN", "GB").
  Future<List<Song>> searchByCountry(String code) =>
      _query({'countrycode': code.trim().toUpperCase()});

  /// Broadcast language ("bengali", "english", "hindi").
  Future<List<Song>> searchByLanguage(String language) =>
      _query({'language': language.trim().toLowerCase()});

  Future<List<Song>> topStations() => _query(const {});

  /// Tells the directory a station was played (Radio Browser asks clients to
  /// do this so popularity stays meaningful). Fire-and-forget.
  Future<void> reportPlay(Song station) async {
    final uuid = station.id.startsWith('radio:') ? station.id.substring(6) : '';
    if (uuid.isEmpty) return;
    try {
      await _client.getJson(Uri.https(await _host(), '/json/url/$uuid'), headers: _headers);
    } catch (_) {}
  }

  static List<Song> parseStations(Object? body) {
    if (body is! List) return const [];
    final out = <Song>[];
    final seen = <String>{};
    for (final s in body.whereType<Map<String, dynamic>>()) {
      final uuid = s['stationuuid'] as String? ?? '';
      final name = (s['name'] as String? ?? '').trim();
      final url = ((s['url_resolved'] as String?) ?? (s['url'] as String?) ?? '').trim();
      if (uuid.isEmpty || name.isEmpty || !url.startsWith('https://')) continue;
      if (s['lastcheckok'] == 0) continue;
      if (!seen.add(url)) continue; // the directory has duplicate entries
      final favicon = (s['favicon'] as String? ?? '').trim();
      final country = (s['country'] as String? ?? '').trim();
      final language = (s['language'] as String? ?? '').trim();
      final tags = (s['tags'] as String? ?? '')
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .take(2)
          .join(' · ');
      final homepage = (s['homepage'] as String? ?? '').trim();
      out.add(Song(
        id: 'radio:$uuid',
        title: name,
        artist: [if (tags.isNotEmpty) tags, if (country.isNotEmpty) country, if (language.isNotEmpty) language]
            .join(' — '),
        album: 'Live radio',
        audioUrl: url,
        coverUrl: favicon.startsWith('https://') ? favicon : '',
        sourceId: sourceInfo.id,
        playability: Playability.full,
        externalUrl: homepage.startsWith('https://') ? homepage : '',
      ));
    }
    return out;
  }
}

extension SongRadio on Song {
  /// Live stream: no duration, no seeking, no song matching or fallback.
  bool get isRadio => sourceId == RadioSource.sourceInfo.id;
}
