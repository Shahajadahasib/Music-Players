import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../utils/api_config.dart';

/// Wraps the Jamendo Open API v3 — a catalogue of Creative Commons music
/// with publicly accessible, full-length audio streams.
///
/// The `mp32` audio format provides 128 kbps MP3 streaming URLs that are
/// compatible with `just_audio`.
///
/// Usage:
/// ```dart
/// final songs = await JamendoService.instance.search('Bohemian Rhapsody');
/// ```
class JamendoService {
  JamendoService._();

  static final JamendoService instance = JamendoService._();

  static const String _baseUrl = 'https://api.jamendo.com/v3.0/tracks/';

  static const int _logBodyMaxChars = 1200;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns Jamendo songs matching [query] (track name search).
  ///
  /// Uses a higher [limit] and popularity ordering so specific titles are
  /// easier to find. Jamendo’s catalogue is **Creative Commons / indie** —
  /// mainstream commercial releases often will not appear.
  ///
  /// Only songs with a non-null, non-empty `audio` URL are included.
  ///
  /// On network, HTTP, or parse errors, logs to debug console and returns an
  /// empty list (does not throw).
  Future<List<Song>> search(String query) async {
    final trimmed = _normalizeSearchQuery(query);
    if (trimmed.isEmpty) return const [];

    // Primary: full phrase (best for distinctive titles).
    final primary = await _fetchTracks(namesearch: trimmed);
    if (primary.length >= 8) {
      return primary;
    }

    // Secondary: strongest keyword — helps when the full phrase matches
    // nothing but a shorter token does (e.g. odd punctuation or word order).
    final keyword = _bestKeyword(trimmed);
    if (keyword != null && keyword != trimmed) {
      final secondary = await _fetchTracks(namesearch: keyword);
      return _mergeUnique(primary, secondary);
    }

    return primary;
  }

  /// Collapses whitespace; keeps letters/numbers/spaces (drops odd symbols
  /// that can break Jamendo’s namesearch).
  String _normalizeSearchQuery(String query) {
    final collapsed = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    return collapsed;
  }

  /// Picks a single meaningful word for a broader fallback search.
  String? _bestKeyword(String trimmed) {
    final parts = trimmed
        .split(' ')
        .where((w) => w.length >= 3)
        .toList(growable: false);
    if (parts.isEmpty) return null;
    // Prefer the longest token (often the most distinctive part of a title).
    parts.sort((a, b) => b.length.compareTo(a.length));
    return parts.first;
  }

  List<Song> _mergeUnique(List<Song> a, List<Song> b) {
    final byId = <String, Song>{};
    for (final s in a) {
      byId[s.id] = s;
    }
    for (final s in b) {
      byId.putIfAbsent(s.id, () => s);
    }
    return byId.values.toList(growable: false);
  }

  Future<List<Song>> _fetchTracks({required String namesearch}) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'client_id': jamendoClientId,
        'namesearch': namesearch,
        // Jamendo allows up to 200; 50 gives a much better hit rate than 10.
        'limit': '50',
        'format': 'json',
        'audioformat': 'mp32',
        // Surface well-known tracks first when many names match loosely.
        'order': 'popularity_week',
      },
    );

    debugPrint('[JamendoService] GET $uri');

    final http.Response response;
    try {
      response = await http.get(uri);
    } on Exception catch (e, st) {
      debugPrint('[JamendoService] network error: $e\n$st');
      return const [];
    }

    debugPrint(
      '[JamendoService] response status=${response.statusCode} '
      'length=${response.body.length}',
    );
    _debugLogBody(response.body);

    if (response.statusCode != 200) {
      debugPrint(
        '[JamendoService] non-200 response, returning empty list',
      );
      return const [];
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException catch (e, st) {
      debugPrint('[JamendoService] JSON decode failed: $e\n$st');
      return const [];
    }

    final headers = body['headers'] as Map<String, dynamic>?;
    final status = headers?['status'] as String?;
    if (status != 'success') {
      final msg = (headers?['error_message'] as String?)?.trim();
      debugPrint(
        '[JamendoService] API status=$status '
        '${msg != null && msg.isNotEmpty ? "error_message=$msg" : ""} '
        '→ empty list',
      );
      return const [];
    }

    final results = (body['results'] as List<dynamic>?) ?? const [];

    final songs = results
        .whereType<Map<String, dynamic>>()
        .map(Song.fromJamendoJson)
        .where((s) => s.id.isNotEmpty && s.audioUrl.trim().isNotEmpty)
        .toList(growable: false);

    debugPrint('[JamendoService] parsed ${songs.length} playable track(s)');
    return songs;
  }

  void _debugLogBody(String body) {
    if (body.length <= _logBodyMaxChars) {
      debugPrint('[JamendoService] body: $body');
    } else {
      debugPrint(
        '[JamendoService] body (truncated): ${body.substring(0, _logBodyMaxChars)}…',
      );
    }
  }
}
