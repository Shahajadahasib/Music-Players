import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/playback/stream_verifier.dart';

import '../helpers.dart';

void main() {
  final track = song('au1', sourceId: 'audius', audioUrl: 'https://stream.test/au1');

  HttpStreamVerifier make(MockClient client, {FakeSource? source, Duration? timeout}) {
    final src = source ?? FakeSource('audius');
    return HttpStreamVerifier(
      sourceById: (id) => id == src.id ? src : null,
      client: client,
      checkHttp: true,
      timeout: timeout ?? const Duration(seconds: 2),
    );
  }

  test('audio response (206 + audio/*) is playable, and only 2 bytes are requested', () async {
    late http.BaseRequest seen;
    final v = make(MockClient((req) async {
      seen = req;
      return http.Response.bytes([0, 1], 206, headers: {'content-type': 'audio/mpeg'});
    }));
    expect((await v.verify(track)).status, StreamStatus.playable);
    expect(seen.headers['Range'], 'bytes=0-1');
  });

  test('403 / 404 / 410 mean the track is not streamable', () async {
    for (final code in [403, 404, 410]) {
      final v = make(MockClient((_) async => http.Response('', code)));
      expect((await v.verify(track)).status, StreamStatus.unavailable, reason: '$code');
    }
  });

  test('a non-audio response (e.g. an HTML error page) is not a stream', () async {
    final v = make(MockClient((_) async =>
        http.Response('<html>', 200, headers: {'content-type': 'text/html; charset=utf-8'})));
    final c = await v.verify(track);
    expect(c.status, StreamStatus.unavailable);
    expect(c.reason, contains('not audio'));
  });

  test('timeouts and 5xx are "unknown", never "playable"', () async {
    final slow = make(
      MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('', 200, headers: {'content-type': 'audio/mpeg'});
      }),
      timeout: const Duration(milliseconds: 50),
    );
    expect((await slow.verify(track)).status, StreamStatus.unknown);
    final broken = make(MockClient((_) async => http.Response('', 503)));
    expect((await broken.verify(track)).status, StreamStatus.unknown);
  });

  test('a track without a resolvable stream or a disabled provider is unavailable', () async {
    final v = make(MockClient((_) async => http.Response('', 200)));
    final noUrl = song('x', sourceId: 'audius', audioUrl: '', playability: Playability.none);
    expect((await v.verify(noUrl)).status, StreamStatus.unavailable);
    final otherProvider = song('y', sourceId: 'jamendo');
    expect((await v.verify(otherProvider)).reason, contains('provider disabled'));
  });

  test('results are cached and identical checks are shared', () async {
    var calls = 0;
    final v = make(MockClient((_) async {
      calls++;
      return http.Response.bytes([0, 1], 206, headers: {'content-type': 'audio/mpeg'});
    }));
    await Future.wait([v.verify(track), v.verify(track)]);
    await v.verify(track);
    expect(calls, 1);
    expect(v.cached('au1')?.isPlayable, isTrue);
  });

  test('web mode trusts a resolved URL (CORS prevents reading the response)', () async {
    final src = FakeSource('audius');
    final v = HttpStreamVerifier(
      sourceById: (_) => src,
      client: MockClient((_) async => fail('no HTTP request on web')),
      checkHttp: false,
    );
    expect((await v.verify(track)).status, StreamStatus.playable);
  });
}
