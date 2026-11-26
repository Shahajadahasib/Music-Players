import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/playback/playback_ledger.dart';
import 'package:music_player_app/search/matched_track.dart';
import 'package:music_player_app/search/provider_health.dart';
import 'package:music_player_app/search/search_aggregator.dart';
import 'package:music_player_app/sources/jamendo_source.dart';
import 'package:music_player_app/sources/music_source.dart';

import '../helpers.dart';

/// Multi-source rules: provider kinds, Bangla query variants, provider
/// health, official external players. All providers are in-memory fakes.
void main() {
  FakeSource catalogue(List<Song> results) => FakeSource('itunes', fullTracks: false, results: results);

  Song cat(String title, String artist, int s) => song('itunes:$title', title: title, artist: artist, seconds: s,
      sourceId: 'itunes', playability: Playability.none, externalUrl: 'https://music.apple.test/$title');

  Song yt(String id, String title, String artist) => song('youtube:$id', title: title, artist: artist,
      sourceId: 'youtube', playability: Playability.external, audioUrl: '',
      externalUrl: 'https://www.youtube.com/watch?v=$id');

  group('Bangla search', () {
    test('a Bengali-script query finds the Latin-script upload (query variants)', () async {
      final audius = FakeSource('audius');
      audius.onSearch = () {
        final q = audius.queries.last;
        audius.results = q.contains('shironamhin')
            ? [song('au1', title: 'Hashimukh', artist: 'Shironamhin', seconds: 240, sourceId: 'audius')]
            : [];
      };
      final agg = SearchAggregator(sources: () => [audius], verifier: FakeVerifier());
      final r = await agg.search('শিরোনামহীন');
      expect(audius.queries.first, 'শিরোনামহীন', reason: 'original query first');
      expect(audius.queries.any((q) => q.contains('shironamhin')), isTrue);
      expect(r.tracks.map((t) => t.best.id), contains('au1'));
    });

    test('variants are tried on one provider before moving to the next', () async {
      final audius = FakeSource('audius');
      final archive = FakeSource('archive');
      final agg = SearchAggregator(sources: () => [audius, archive], verifier: FakeVerifier());
      await agg.search('জেমস');
      expect(audius.calls, greaterThan(1));
      expect(archive.calls, greaterThan(0));
      expect(audius.queries.toSet().length, audius.calls, reason: 'no duplicate requests');
    });
  });

  group('Provider kinds', () {
    test('metadata-only providers never become playable candidates', () async {
      final meta = catalogue([cat('Hello', 'Adele', 295)]);
      final agg = SearchAggregator(sources: () => [meta], verifier: FakeVerifier());
      final r = await agg.search('hello adele');
      expect(r.playableSongs, isEmpty);
      expect(r.bestMatch?.originalUnavailable, isTrue);
    });

    test('external-player providers are not asked when an in-app original was found', () async {
      final youtube = FakeSource('youtube', fullTracks: false, kind: SourceKind.externalPlayer,
          results: [yt('v1', 'Hello', 'Adele')]);
      final audius = FakeSource('audius', results: [song('au', title: 'Hello', artist: 'Adele', seconds: 295, sourceId: 'audius')]);
      final agg = SearchAggregator(
          sources: () => [audius, youtube, catalogue([cat('Hello', 'Adele', 295)])], verifier: FakeVerifier());
      final r = await agg.search('hello adele');
      expect(r.bestMatch!.best.id, 'au');
      expect(youtube.calls, 0);
      expect(r.bestMatch!.externalOption, isNull);
    });

    test('official external player is offered when no authorised stream has the original', () async {
      final youtube = FakeSource('youtube', fullTracks: false, kind: SourceKind.externalPlayer, results: [
        yt('cover', 'Hello (Piano Cover)', 'Adele'),
        yt('v1', 'Hello (Official Music Video)', 'Adele'),
      ]);
      final audius = FakeSource('audius', results: [
        song('c', title: 'Hello (Cover)', artist: 'Someone', seconds: 290, sourceId: 'audius'),
      ]);
      final agg = SearchAggregator(
          sources: () => [audius, youtube, catalogue([cat('Hello', 'Adele', 295)])], verifier: FakeVerifier());
      final r = await agg.search('hello adele');
      final best = r.bestMatch!;
      expect(best.originalUnavailable, isTrue);
      expect(best.externalOption?.id, 'youtube:v1', reason: 'covers are not offered as the original');
      expect(best.candidates.any((c) => c.isExternal), isFalse, reason: 'never queued for the audio player');
      expect(r.playableSongs.any((s) => s.isExternal), isFalse);
      expect(r.attempts.last.outcome, AttemptOutcome.external);
    });

    test('an external result by a different artist is not offered', () async {
      final youtube = FakeSource('youtube', fullTracks: false, kind: SourceKind.externalPlayer,
          results: [yt('v2', 'Hello', 'Lionel Richie')]);
      final agg = SearchAggregator(
          sources: () => [youtube, catalogue([cat('Hello', 'Adele', 295)])], verifier: FakeVerifier());
      final r = await agg.search('hello adele');
      expect(r.bestMatch!.externalOption, isNull);
    });

    test('discover() returns the external option when nothing plays in-app', () async {
      final youtube = FakeSource('youtube', fullTracks: false, kind: SourceKind.externalPlayer,
          results: [yt('v1', 'Hello', 'Adele')]);
      final agg = SearchAggregator(sources: () => [FakeSource('audius'), youtube], verifier: FakeVerifier());
      final d = await agg.discover(cat('Hello', 'Adele', 295));
      expect(d.found, isFalse);
      expect(d.external?.externalUrl, startsWith('https://www.youtube.com/'));
    });
  });

  group('Provider health', () {
    test('circuit opens after repeated failures and closes after the cooldown', () {
      var now = DateTime(2026, 1, 1);
      final h = ProviderHealth(failureThreshold: 2, cooldown: const Duration(minutes: 1), clock: () => now);
      h.recordFailure('a', 'timeout');
      expect(h.isPaused('a'), isFalse);
      h.recordFailure('a', 'timeout');
      expect(h.isPaused('a'), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(h.isPaused('a'), isFalse, reason: 'trial request allowed after cooldown');
      h.recordSuccess('a');
      expect(h.statusOf('a').consecutiveFailures, 0);
    });

    test('a paused provider is skipped without a request', () async {
      final health = ProviderHealth(failureThreshold: 1);
      final down = FakeSource('down', error: const SourceException('down', 'HTTP 503', statusCode: 503));
      final up = FakeSource('up', results: [song('u', title: 'Lofi Mix', artist: 'B', sourceId: 'up')]);
      final agg = SearchAggregator(sources: () => [down, up], verifier: FakeVerifier(), health: health);
      await agg.search('lofi');
      expect(down.calls, 1);
      agg.clearCache();
      final r = await agg.search('lofi beats');
      expect(down.calls, 1, reason: 'circuit open');
      expect(r.attempts.first.outcome, AttemptOutcome.paused);
      expect(up.calls, 2);
    });

    test('rate limiting is not counted as a provider failure', () async {
      final health = ProviderHealth(failureThreshold: 1);
      final limited = FakeSource('rl', error: const SourceException('rl', 'HTTP 429', statusCode: 429));
      final agg = SearchAggregator(sources: () => [limited], verifier: FakeVerifier(), health: health);
      await agg.search('anything');
      expect(health.isPaused('rl'), isFalse);
    });
  });

  group('Playback ledger', () {
    test('"Full track" only after real playback; a later failure revokes it', () async {
      final l = MemoryPlaybackLedger();
      expect(l.hasPlayed('x'), isFalse);
      await l.recordPlayed('x');
      expect(l.hasPlayed('x'), isTrue);
      await l.recordFailed('x');
      expect(l.hasPlayed('x'), isFalse);
    });
  });

  group('Licences', () {
    test('Jamendo: NC / ND-only licences are never streamed commercially', () {
      expect(JamendoSource.allowsCommercialStreaming('https://creativecommons.org/licenses/by/3.0/'), isTrue);
      expect(JamendoSource.allowsCommercialStreaming('https://creativecommons.org/licenses/by-nc/3.0/'), isFalse);
      expect(JamendoSource.allowsCommercialStreaming('https://creativecommons.org/licenses/by-nc-sa/3.0/'), isFalse);
      expect(JamendoSource.allowsCommercialStreaming(''), isFalse, reason: 'unknown licence = not verified');
    });
  });
}
