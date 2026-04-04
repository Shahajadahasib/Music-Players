import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/search_track_outcome.dart';
import '../models/song.dart';

/// Audius discovery API — search and stream URLs only; no API key required.
///
/// Docs: https://docs.audius.org/api
class AudiusService {
  AudiusService._();

  static final AudiusService instance = AudiusService._();

  static const String _host = 'discoveryprovider.audius.co';

  /// Trending tracks (network “top” chart). Same [Song] shape as [searchTracks].
  ///
  /// GET `/v1/tracks/trending?limit=…`
  Future<SearchTrackOutcome> trendingTracks({int limit = 40}) async {
    final c = limit.clamp(1, 100);
    final uri = Uri.https(_host, '/v1/tracks/trending', {'limit': '$c'});

    final http.Response response;
    try {
      response = await http.get(uri);
    } catch (_) {
      return SearchTrackOutcome.networkUnavailable();
    }

    if (response.statusCode != 200) {
      return SearchTrackOutcome.apiFailure(statusCode: response.statusCode);
    }

    return compute(_parseTracksBody, response.body);
  }

  /// GET `/v1/tracks/search?query=…` → [SearchTrackOutcome] with [Song.audioUrl]
  /// set to the canonical stream endpoint for each track id.
  ///
  /// Network and HTTP failures return [SearchTrackOutcome] with [errorMessage];
  /// parsing runs in a background isolate when possible to avoid jank.
  Future<SearchTrackOutcome> searchTracks(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return SearchTrackOutcome.success(const []);
    }

    final uri = Uri.https(_host, '/v1/tracks/search', {'query': trimmed});

    final http.Response response;
    try {
      response = await http.get(uri);
    } catch (_) {
      return SearchTrackOutcome.networkUnavailable();
    }

    if (response.statusCode != 200) {
      return SearchTrackOutcome.apiFailure(statusCode: response.statusCode);
    }

    return compute(_parseTracksBody, response.body);
  }

  /// `GET /v1/tracks/{id}/stream`
  static String streamUrlForTrackId(String id) {
    if (id.isEmpty) return '';
    final encoded = Uri.encodeComponent(id);
    return Uri.https(_host, '/v1/tracks/$encoded/stream').toString();
  }

  static SearchTrackOutcome _parseTracksBody(String responseBody) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } on FormatException {
      return SearchTrackOutcome.parseFailure();
    }

    final raw = body['data'];
    if (raw is! List<dynamic>) {
      return SearchTrackOutcome.parseFailure();
    }

    final out = <Song>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final song = _trackToSong(item);
      if (song != null) {
        out.add(song);
      }
    }
    return SearchTrackOutcome.success(out);
  }

  static Song? _trackToSong(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;

    final title = json['title'] is String ? json['title'] as String : '';
    final artist = _parseUserName(json['user']);
    final coverUrl = _parseArtworkUrl(json['artwork']);
    final duration = _parseDuration(json['duration']);
    final streamUrl = streamUrlForTrackId(id);
    if (streamUrl.isEmpty) return null;

    return Song(
      id: id,
      title: title,
      artist: artist,
      album: '',
      audioUrl: streamUrl,
      coverUrl: coverUrl,
      duration: duration,
    );
  }

  static String _parseUserName(dynamic user) {
    if (user is Map<String, dynamic>) {
      final name = user['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return '';
  }

  /// Prefers larger artwork; handles nested size map or plain string.
  static String _parseArtworkUrl(dynamic artwork) {
    if (artwork is String && artwork.trim().isNotEmpty) {
      return artwork.trim();
    }
    if (artwork is Map<String, dynamic>) {
      for (final key in ['1000x1000', '480x480', '150x150']) {
        final v = artwork[key];
        if (v is String && v.trim().isNotEmpty) {
          return v.trim();
        }
      }
      for (final value in artwork.values) {
        if (value is String && value.startsWith('http')) {
          return value.trim();
        }
      }
    }
    return '';
  }

  static Duration? _parseDuration(dynamic value) {
    if (value is int) {
      return Duration(seconds: value);
    }
    if (value is double) {
      return Duration(seconds: value.round());
    }
    if (value is String) {
      final s = int.tryParse(value);
      if (s != null) return Duration(seconds: s);
    }
    return null;
  }
}
