import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/services/api_client.dart';
import 'package:music_player_app/sources/audius_source.dart';
import 'package:music_player_app/sources/internet_archive_source.dart';
import 'package:music_player_app/sources/itunes_source.dart';
import 'package:music_player_app/sources/jamendo_source.dart';
import 'package:music_player_app/sources/music_source.dart';

/// Response *shapes* follow each provider's public documentation. Values are
/// synthetic test fixtures, not real catalogue data.
void main() {
  group('Audius', () {
    final body = {
      'data': [
        {
          'id': 'abc',
          'title': 'Open Track',
          'user': {'id': 'u1', 'name': 'Indie Artist'},
          'artwork': {'480x480': 'https://img.test/480.jpg'},
          'duration': 181,
          'permalink': '/indie/open-track',
          'is_streamable': true,
        },
        {'id': 'gated', 'title': 'Gated', 'stream_conditions': {'usdc_purchase': {}}},
        {'id': 'nostream', 'title': 'Off', 'is_streamable': false},
        {'id': 'locked', 'title': 'Locked', 'access': {'stream': false}},
        {'title': 'no id'},
      ],
    };

    test('parses playable tracks and excludes gated / non-streamable ones', () {
      final songs = AudiusSource.parseTracks(body, host: 'api.audius.co');
      expect(songs, hasLength(1));
      final s = songs.single;
      expect(s.id, 'abc');
      expect(s.artist, 'Indie Artist');
      expect(s.artistId, 'u1');
      expect(s.playability, Playability.full);
      expect(s.duration, const Duration(seconds: 181));
      expect(s.externalUrl, 'https://audius.co/indie/open-track');
      final uri = Uri.parse(s.audioUrl);
      expect(uri.path, '/v1/tracks/abc/stream');
      expect(uri.queryParameters['app_name'], isNotEmpty);
    });

    test('sends app_name and maps HTTP errors to SourceException', () async {
      late Uri seen;
      final client = MockClient((req) async {
        seen = req.url;
        return http.Response('{"error":"rate"}', 429);
      });
      final src = AudiusSource(client: ApiClient(client: client, retries: 0), host: 'api.audius.co');
      await expectLater(
        src.searchTracks('lofi'),
        throwsA(isA<SourceException>().having((e) => e.isRateLimited, 'rate limited', isTrue)),
      );
      expect(seen.queryParameters['query'], 'lofi');
      expect(seen.queryParameters['app_name'], isNotEmpty);
    });

    test('empty query makes no request', () async {
      var calls = 0;
      final src = AudiusSource(
        client: ApiClient(client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        })),
      );
      expect(await src.searchTracks('   '), isEmpty);
      expect(calls, 0);
    });
  });

  group('iTunes catalogue', () {
    final body = {
      'resultCount': 2,
      'results': [
        {'wrapperType': 'collection', 'collectionId': 9},
        {
          'wrapperType': 'track',
          'kind': 'song',
          'trackId': 42,
          'trackName': 'Catalogue Song',
          'artistName': 'Band',
          'collectionName': 'Album',
          'artistId': 7,
          'collectionId': 9,
          'artworkUrl100': 'https://is1.test/image/100x100bb.jpg',
          'trackTimeMillis': 215000,
          'previewUrl': 'https://audio.test/preview.m4a',
          'trackViewUrl': 'https://music.apple.test/song/42',
        },
      ],
    };

    test('is metadata-only by default (no preview playback)', () {
      final s = ItunesSource.parseResults(body, previews: false).single;
      expect(s.id, 'itunes:42');
      expect(s.playability, Playability.none);
      expect(s.audioUrl, isEmpty);
      expect(s.coverUrl, 'https://is1.test/image/600x600bb.jpg');
      expect(s.albumId, '9');
      expect(s.externalUrl, contains('/song/42'));
    });

    test('exposes previews only when explicitly enabled', () {
      final s = ItunesSource.parseResults(body, previews: true).single;
      expect(s.playability, Playability.preview);
      expect(s.audioUrl, 'https://audio.test/preview.m4a');
    });
  });

  group('Internet Archive', () {
    test('keeps only commercially reusable licences', () {
      expect(InternetArchiveSource.isCommercialLicence('http://creativecommons.org/publicdomain/zero/1.0/'), isTrue);
      expect(InternetArchiveSource.isCommercialLicence('https://creativecommons.org/licenses/by/4.0/'), isTrue);
      expect(InternetArchiveSource.isCommercialLicence('https://creativecommons.org/licenses/by-sa/3.0/'), isTrue);
      expect(InternetArchiveSource.isCommercialLicence('https://creativecommons.org/licenses/by-nc/4.0/'), isFalse);
      expect(InternetArchiveSource.isCommercialLicence('https://creativecommons.org/licenses/by-nc-sa/4.0/'), isFalse);
      expect(InternetArchiveSource.isCommercialLicence(''), isFalse);
    });

    test('parses search docs and drops NC items even if the server returns them', () {
      final songs = InternetArchiveSource.parseSearch({
        'response': {
          'docs': [
            {'identifier': 'ok_item', 'title': 'Prelude', 'creator': ['Composer'], 'licenseurl': 'https://creativecommons.org/licenses/by/4.0/'},
            {'identifier': 'nc_item', 'title': 'NC', 'licenseurl': 'https://creativecommons.org/licenses/by-nc/4.0/'},
          ],
        },
      });
      expect(songs.map((s) => s.id), ['archive:ok_item']);
      expect(songs.single.audioUrl, isEmpty, reason: 'resolved lazily');
      expect(songs.single.license, contains('/by/4.0'));
    });

    test('resolves the first MP3 file of an item', () async {
      final src = InternetArchiveSource(
        client: ApiClient(client: MockClient((req) async {
          expect(req.url.path, '/metadata/ok_item');
          return http.Response(jsonEncode({
            'files': [
              {'name': 'cover.jpg', 'format': 'JPEG'},
              {'name': 'track 01.ogg', 'format': 'Ogg Vorbis'},
              {'name': 'track 01.mp3', 'format': 'VBR MP3'},
            ],
          }), 200);
        })),
      );
      final uri = await src.resolveStream(const Song(
        id: 'archive:ok_item', title: '', artist: '', album: '', audioUrl: '', coverUrl: '',
        sourceId: 'archive',
      ));
      expect(uri.toString(), 'https://archive.org/download/ok_item/track%2001.mp3');
    });
  });

  group('Jamendo', () {
    test('is disabled unless a commercial agreement is configured', () {
      expect(JamendoSource.isConfigured, isFalse);
      expect(JamendoSource.sourceInfo.commercialStatus, CommercialStatus.requiresAgreement);
    });

    test('parses tracks with prefixed ids and licence', () {
      final songs = JamendoSource.parseTracks({
        'headers': {'status': 'success'},
        'results': [
          {'id': 5, 'name': 'CC Song', 'artist_name': 'CC', 'audio': 'https://mp3.test/5.mp3', 'duration': '120',
           'license_ccurl': 'http://creativecommons.org/licenses/by/3.0/', 'shareurl': 'https://jamendo.test/5'},
          {'id': 6, 'name': 'No audio', 'audio': ''},
        ],
      });
      expect(songs.single.id, 'jamendo:5');
      expect(songs.single.duration, const Duration(seconds: 120));
      expect(songs.single.license, contains('/by/3.0'));
    });

    test('API-level errors become SourceException', () {
      expect(
        () => JamendoSource.parseTracks({'headers': {'status': 'failed', 'error_message': 'bad client'}}),
        throwsA(isA<SourceException>()),
      );
    });
  });

  group('ApiClient', () {
    test('retries once on 5xx then succeeds', () async {
      var calls = 0;
      final c = ApiClient(client: MockClient((_) async {
        calls++;
        return calls == 1 ? http.Response('oops', 503) : http.Response('{"ok":true}', 200);
      }));
      expect(await c.get(Uri.parse('https://x.test')), {'ok': true});
      expect(calls, 2);
    });

    test('does not retry 4xx', () async {
      var calls = 0;
      final c = ApiClient(client: MockClient((_) async {
        calls++;
        return http.Response('nope', 404);
      }));
      await expectLater(c.get(Uri.parse('https://x.test')), throwsA(isA<ApiException>()));
      expect(calls, 1);
    });

    test('times out slow responses as a network error', () async {
      final c = ApiClient(
        timeout: const Duration(milliseconds: 20),
        retries: 0,
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        c.get(Uri.parse('https://x.test')),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue)),
      );
    });

    test('rejects malformed JSON', () async {
      final c = ApiClient(client: MockClient((_) async => http.Response('<html>', 200)));
      await expectLater(c.get(Uri.parse('https://x.test')), throwsA(isA<ApiException>()));
    });
  });
}
