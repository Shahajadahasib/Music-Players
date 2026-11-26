import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../sources/music_source.dart';

enum StreamStatus {
  /// The provider resolved a stream and it answered with audio.
  playable,

  /// The stream is definitely not available (gated, removed, 401/403/404/410,
  /// not audio, or the provider resolved nothing).
  unavailable,

  /// Could not decide (timeout, 5xx, network). Treated as "not verified".
  unknown,
}

class StreamCheck {
  const StreamCheck(this.status, {this.uri, this.reason = ''});

  final StreamStatus status;
  final Uri? uri;
  final String reason;

  bool get isPlayable => status == StreamStatus.playable;

  @override
  String toString() => '${status.name}${reason.isEmpty ? '' : ' ($reason)'}';
}

/// Confirms that a track can really be streamed before it is offered as a
/// full track. An API returning a track id is not enough.
abstract class StreamVerifier {
  Future<StreamCheck> verify(Song song);

  /// Cached result, if any (used for instant badges).
  StreamCheck? cached(String songId);

  /// Records that the **player** failed to load / play this stream. The
  /// 2-byte HTTP check proves reachability and an audio content type, not
  /// that the codec decodes, so a real player failure overrides it.
  void markUnplayable(String songId, {String reason = ''});
}

/// Accepts everything that resolves to a URL. Used by tests that are not
/// about verification, and as the no-op default.
class TrustingStreamVerifier implements StreamVerifier {
  TrustingStreamVerifier(this.sourceById);
  final MusicSource? Function(String id) sourceById;
  final Map<String, StreamCheck> _failed = {};

  @override
  Future<StreamCheck> verify(Song song) async {
    if (song.isLocal) return const StreamCheck(StreamStatus.playable);
    final failed = _failed[song.id];
    if (failed != null) return failed;
    final uri = await sourceById(song.sourceId)?.resolveStream(song);
    return uri == null
        ? const StreamCheck(StreamStatus.unavailable, reason: 'no stream')
        : StreamCheck(StreamStatus.playable, uri: uri);
  }

  @override
  StreamCheck? cached(String songId) => _failed[songId];

  @override
  void markUnplayable(String songId, {String reason = ''}) =>
      _failed[songId] = StreamCheck(StreamStatus.unavailable, reason: reason);
}

/// Resolves the stream with the owning provider, then requests the first two
/// bytes (`Range: bytes=0-1`, following redirects) and checks the status and
/// `Content-Type`.
///
/// * Results are cached (positive 30 min, negative 10 min) and identical
///   checks in flight are shared.
/// * At most [maxConcurrent] checks run at once.
/// * **Web:** browsers block reading cross-origin audio responses (CORS) even
///   when an `<audio>` element may play them, so on web a resolved URL counts
///   as playable and the real check is the player load (see
///   docs/ARCHITECTURE.md).
class HttpStreamVerifier implements StreamVerifier {
  HttpStreamVerifier({
    required this.sourceById,
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
    this.positiveTtl = const Duration(minutes: 30),
    this.negativeTtl = const Duration(minutes: 10),
    this.maxConcurrent = 3,
    this.checkHttp = !kIsWeb,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  final MusicSource? Function(String id) sourceById;
  final http.Client _client;
  final Duration timeout;
  final Duration positiveTtl;
  final Duration negativeTtl;
  final int maxConcurrent;
  final bool checkHttp;
  final DateTime Function() _clock;

  final Map<String, ({StreamCheck check, DateTime at})> _cache = {};
  final Map<String, Future<StreamCheck>> _inFlight = {};
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue();

  static const _audioTypes = ['audio/', 'application/ogg', 'application/octet-stream', 'video/mp4'];

  @override
  StreamCheck? cached(String songId) {
    final hit = _cache[songId];
    if (hit == null) return null;
    final ttl = hit.check.isPlayable ? positiveTtl : negativeTtl;
    if (_clock().difference(hit.at) > ttl) {
      _cache.remove(songId);
      return null;
    }
    return hit.check;
  }

  @override
  void markUnplayable(String songId, {String reason = ''}) {
    _cache[songId] = (
      check: StreamCheck(StreamStatus.unavailable, reason: reason.isEmpty ? 'player failed' : reason),
      at: _clock(),
    );
  }

  @override
  Future<StreamCheck> verify(Song song) {
    if (song.isLocal) return Future.value(const StreamCheck(StreamStatus.playable));
    if (!song.canPlay) {
      return Future.value(const StreamCheck(StreamStatus.unavailable, reason: 'metadata only'));
    }
    final hit = cached(song.id);
    if (hit != null) return Future.value(hit);
    return _inFlight[song.id] ??= _run(song).then((c) {
      if (c.status != StreamStatus.unknown) _cache[song.id] = (check: c, at: _clock());
      return c;
    }).whenComplete(() {
      _inFlight.remove(song.id);
    });
  }

  Future<StreamCheck> _run(Song song) async {
    await _acquire();
    try {
      final source = sourceById(song.sourceId);
      if (source == null) {
        return const StreamCheck(StreamStatus.unavailable, reason: 'provider disabled');
      }
      final Uri? uri;
      try {
        uri = await source.resolveStream(song).timeout(timeout);
      } on TimeoutException {
        return const StreamCheck(StreamStatus.unknown, reason: 'resolve timeout');
      } on SourceException catch (e) {
        return StreamCheck(
          e.statusCode != null && e.statusCode! < 500 ? StreamStatus.unavailable : StreamStatus.unknown,
          reason: e.message,
        );
      }
      if (uri == null) return const StreamCheck(StreamStatus.unavailable, reason: 'no stream');
      if (!checkHttp) return StreamCheck(StreamStatus.playable, uri: uri, reason: 'resolved');
      return await _probe(uri);
    } catch (e) {
      return StreamCheck(StreamStatus.unknown, reason: '$e');
    } finally {
      _release();
    }
  }

  Future<StreamCheck> _probe(Uri uri) async {
    final req = http.Request('GET', uri)
      ..headers['Range'] = 'bytes=0-1'
      ..followRedirects = true
      ..maxRedirects = 5;
    final http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(timeout);
    } on TimeoutException {
      return StreamCheck(StreamStatus.unknown, uri: uri, reason: 'timeout');
    }
    // Never read the body: servers that ignore Range (and live radio
    // streams, which never end) would otherwise be downloaded in full.
    // Cancelling the subscription closes the connection.
    unawaited(res.stream.listen((_) {}, onError: (_) {}, cancelOnError: true).cancel());
    final code = res.statusCode;
    if (code == 401 || code == 402 || code == 403 || code == 404 || code == 410 || code == 451) {
      return StreamCheck(StreamStatus.unavailable, uri: uri, reason: 'HTTP $code');
    }
    if (code != 200 && code != 206) {
      return StreamCheck(StreamStatus.unknown, uri: uri, reason: 'HTTP $code');
    }
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    if (type.isNotEmpty && !_audioTypes.any(type.startsWith)) {
      return StreamCheck(StreamStatus.unavailable, uri: uri, reason: 'not audio ($type)');
    }
    return StreamCheck(StreamStatus.playable, uri: uri);
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete(); // hand the slot over
    } else {
      _running--;
    }
  }
}
