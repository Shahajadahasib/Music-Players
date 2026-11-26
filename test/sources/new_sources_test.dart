import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/providers/source_providers.dart';
import 'package:music_player_app/services/api_client.dart';
import 'package:music_player_app/sources/audius_source.dart';
import 'package:music_player_app/sources/freetouse_source.dart';
import 'package:music_player_app/sources/internet_archive_source.dart';
import 'package:music_player_app/sources/itunes_source.dart';
import 'package:music_player_app/sources/jamendo_source.dart';
import 'package:music_player_app/sources/music_source.dart';
import 'package:music_player_app/sources/musicbrainz_source.dart';
import 'package:music_player_app/sources/radio_source.dart';
import 'package:music_player_app/sources/youtube_source.dart';

import '../helpers.dart';

/// Response *shapes* follow each provider's public documentation (and, for
/// Free To Use, a live response inspected during research). Values are
/// synthetic fixtures.
void main() {
  group('Capabilities are declared explicitly', () {
    test('every provider has a kind and capabilities consistent with it', () {
      final infos = [
        AudiusSource.sourceInfo,
        JamendoSource.sourceInfo,
        InternetArchiveSource.sourceInfo,
        ItunesSource.sourceInfo,
        FreeToUseSource.sourceInfo,
        MusicBrainzSource.sourceInfo,
        YouTubeSource.sourceInfo,
        RadioSource.sourceInfo,
      ];
      for (final i in infos) {
        expect(i.capabilities, isNotEmpty, reason: i.id);
        switch (i.kind) {
          case SourceKind.fullTrack:
            expect(i.can(SourceCapability.fullTrackStream), isTrue, reason: i.id);
          case SourceKind.metadata:
            expect(i.can(SourceCapability.fullTrackStream), isFalse, reason: i.id);
          case SourceKind.externalPlayer:
            expect(i.can(SourceCapability.externalPlayer), isTrue, reason: i.id);
            expect(i.can(SourceCapability.fullTrackStream), isFalse, reason: i.id);
            expect(i.can(SourceCapability.previewAudio), isFalse, reason: i.id);
          case SourceKind.radio:
            expect(i.can(SourceCapability.liveRadio), isTrue, reason: i.id);
        }
      }
      expect(MusicBrainzSource.sourceInfo.kind, SourceKind.metadata);
      expect(YouTubeSource.sourceInfo.kind, SourceKind.externalPlayer);
      expect(RadioSource.sourceInfo.kind, SourceKind.radio);
      expect(FreeToUseSource.sourceInfo.kind, SourceKind.fullTrack);
    });

    test('licence-gated providers are off by default', () {
      expect(FreeToUseSource.isConfigured, isFalse, reason: 'needs FREETOUSE_COMMERCIAL_LICENSE');
      expect(YouTubeSource.isConfigured, isFalse, reason: 'needs YOUTUBE_API_KEY');
      expect(JamendoSource.isConfigured, isFalse, reason: 'needs a commercial agreement');
    });
  });

  group('Provider priority', () {
    test('orders by configured ids, unlisted keep their order', () {
      final a = FakeSource('audius'), j = FakeSource('jamendo'), ar = FakeSource('archive'), i = FakeSource('itunes');
      final ordered = orderByPriority([a, j, ar, i], 'archive, audius');
      expect(ordered.map((s) => s.id), ['archive', 'audius', 'jamendo', 'itunes']);
      expect(orderByPriority([a, j], '').map((s) => s.id), ['audius', 'jamendo']);
    });
  });

  group('MusicBrainz (metadata only)', () {
    final body = {
      'recordings': [
        {
          'id': 'rec-1',
          'title': 'Bondho Janala',
          'length': 300500,
          'isrcs': ['BDXXX0000001'],
          'artist-credit': [
            {'name': 'Shironamhin', 'joinphrase': ' & '},
            {'name': 'Guest'},
          ],
          'releases': [
            {'id': 'rel-1', 'title': 'Jahaji'},
          ],
        },
        {'id': '', 'title': 'no id'},
        {'id': 'rec-2', 'title': ''},
      ],
    };

    test('parses recordings as metadata-only songs with ISRC and length', () {
      final songs = MusicBrainzSource.parseRecordings(body);
      expect(songs, hasLength(1));
      final s = songs.single;
      expect(s.id, 'musicbrainz:rec-1');
      expect(s.artist, 'Shironamhin & Guest');
      expect(s.album, 'Jahaji');
      expect(s.isrc, 'BDXXX0000001');
      expect(s.duration, const Duration(milliseconds: 300500));
      expect(s.playability, Playability.none);
      expect(s.canPlay, isFalse);
      expect(s.audioUrl, isEmpty);
    });

    test('builds a safe Lucene query', () {
      expect(MusicBrainzSource.buildQuery('a "b" : c'), isNot(contains('""')));
      expect(MusicBrainzSource.buildQuery('Shironamhin'), contains('recording:"Shironamhin"'));
    });

    test('sends a User-Agent and queries /ws/2/recording', () async {
      late http.Request seen;
      final src = MusicBrainzSource(
        client: ApiClient(client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
        }), retries: 0),
        contact: 'test@example.test',
      );
      final r = await src.searchTracks('Bondho Janala');
      expect(r, hasLength(1));
      expect(seen.url.path, '/ws/2/recording');
      expect(seen.headers['User-Agent'], contains('test@example.test'));
    });
  });

  group('Free To Use (full track, licence-gated)', () {
    Map<String, dynamic> track(String id, {int status = 1, bool premium = false, String mp3 = 'https://cdn.test/a.mp3'}) => {
          'id': id,
          'title': 'Track $id',
          'status': status,
          'is_premium': premium,
          'duration': 123.4,
          'files': {'mp3': mp3},
          'thumbnails': {'md': 'https://img.test/$id.jpg'},
          'artists': [
            [0, {'id': 'ar1', 'name': 'Indie One'}],
            [1, {'id': 'ar2', 'name': 'Indie Two'}],
          ],
        };

    test('parses published tracks; premium / unpublished / non-https are not playable', () {
      final songs = FreeToUseSource.parseTracks({
        'data': [
          track('ok'),
          track('prem', premium: true),
          track('draft', status: 0),
          track('http', mp3: 'http://cdn.test/a.mp3'),
        ],
      });
      expect(songs.map((s) => s.id), ['freetouse:ok', 'freetouse:prem', 'freetouse:http']);
      final ok = songs.first;
      expect(ok.artist, 'Indie One, Indie Two');
      expect(ok.artistId, 'ar1');
      expect(ok.duration, const Duration(milliseconds: 123400));
      expect(ok.canPlay, isTrue);
      expect(ok.license, isNotEmpty);
      expect(songs[1].canPlay, isFalse, reason: 'premium tracks are not part of the API licence');
      expect(songs[2].canPlay, isFalse);
    });
  });

  group('YouTube (official external player only)', () {
    final body = {
      'items': [
        {
          'id': {'videoId': 'vid1'},
          'snippet': {
            'title': 'Ed Sheeran - Shape of You (Official Music Video)',
            'channelTitle': 'Ed Sheeran',
            'thumbnails': {'high': {'url': 'https://i.ytimg.test/vid1.jpg'}},
          },
        },
        {
          'id': {'videoId': 'vid2'},
          'snippet': {'title': 'Tom &amp; Jerry&#39;s Song', 'channelTitle': 'SomeArtistVEVO'},
        },
        {'id': {'kind': 'youtube#channel'}, 'snippet': {'title': 'channel'}},
      ],
    };

    test('results open the official player and never carry an audio URL', () {
      final songs = YouTubeSource.parseSearch(body);
      expect(songs, hasLength(2));
      for (final s in songs) {
        expect(s.audioUrl, isEmpty);
        expect(s.playability, Playability.external);
        expect(s.isExternal, isTrue);
        expect(s.canPlay, isFalse, reason: 'must never reach just_audio');
        expect(s.externalUrl, startsWith('https://www.youtube.com/watch?v='));
      }
      expect(songs.first.title, 'Shape of You (Official Music Video)');
      expect(songs.first.artist, 'Ed Sheeran');
      expect(songs[1].title, "Tom & Jerry's Song");
      expect(songs[1].artist, 'SomeArtist');
    });

    test('resolveStream never returns a stream', () async {
      final yt = YouTubeSource(apiKey: 'k', client: ApiClient(client: MockClient((_) async => http.Response('{}', 200)), retries: 0));
      expect(await yt.resolveStream(YouTubeSource.parseSearch(body).first), isNull);
    });

    test('without a key nothing is requested', () async {
      var calls = 0;
      final yt = YouTubeSource(apiKey: '', client: ApiClient(client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }), retries: 0));
      expect(await yt.searchTracks('anything'), isEmpty);
      expect(calls, 0);
    });
  });

  group('Radio Browser (separate radio feature)', () {
    final stations = [
      {
        'stationuuid': 'u1',
        'name': 'Radio One BD',
        'url_resolved': 'https://stream.test/one',
        'favicon': 'https://img.test/one.png',
        'country': 'Bangladesh',
        'language': 'bengali',
        'tags': 'bangla,pop,news',
        'lastcheckok': 1,
      },
      {'stationuuid': 'u2', 'name': 'Dup', 'url_resolved': 'https://stream.test/one', 'lastcheckok': 1},
      {'stationuuid': 'u3', 'name': 'Plain HTTP', 'url_resolved': 'http://stream.test/x', 'lastcheckok': 1},
      {'stationuuid': 'u4', 'name': 'Broken', 'url_resolved': 'https://stream.test/b', 'lastcheckok': 0},
    ];

    test('keeps working https stations once', () {
      final s = RadioSource.parseStations(stations);
      expect(s.map((e) => e.id), ['radio:u1']);
      expect(s.single.isRadio, isTrue);
      expect(s.single.artist, contains('Bangladesh'));
      expect(s.single.duration, isNull);
    });

    test('queries a mirror with https + hidebroken filters', () async {
      final urls = <Uri>[];
      final radio = RadioSource(client: ApiClient(client: MockClient((req) async {
        urls.add(req.url);
        if (req.url.path == '/json/servers') {
          return http.Response(jsonEncode([{'name': 'de1.api.radio-browser.info'}]), 200);
        }
        return http.Response(jsonEncode(stations), 200);
      }), retries: 0));
      final s = await radio.searchByCountry('bd');
      expect(s, hasLength(1));
      final q = urls.last;
      expect(q.host, 'de1.api.radio-browser.info');
      expect(q.queryParameters['countrycode'], 'BD');
      expect(q.queryParameters['is_https'], 'true');
      expect(q.queryParameters['hidebroken'], 'true');
    });
  });

  group('Audius additions', () {
    test('parses licence and ISRC when present', () {
      final s = AudiusSource.parseTracks({
        'data': [
          {
            'id': 'x',
            'title': 'T',
            'user': {'id': 'u', 'name': 'A'},
            'duration': 100,
            'is_streamable': true,
            'license': 'All rights reserved',
            'isrc': 'USXXX2400001',
          },
        ],
      }, host: 'api.audius.co');
      expect(s.single.license, 'All rights reserved');
      expect(s.single.isrc, 'USXXX2400001');
    });

    test('parses artist search', () {
      final a = AudiusSource.parseArtists({
        'data': [
          {'id': 'u1', 'name': 'Indie', 'handle': 'indie', 'follower_count': 10, 'is_verified': true},
          {'name': 'no id'},
        ],
      });
      expect(a, hasLength(1));
      expect(a.single.name, 'Indie');
    });
  });
}
