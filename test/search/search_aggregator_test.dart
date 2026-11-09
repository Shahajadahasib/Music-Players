
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/search/search_aggregator.dart';
import 'package:music_player_app/sources/music_source.dart';

import '../helpers.dart';

void main() {
  group('SearchAggregator.search', () {
    test('queries all sources concurrently and merges the same song', () async {
      final audius = FakeSource('audius', results: [
        song('a1', title: 'Night Drive', artist: 'Neon Coast', seconds: 200, sourceId: 'audius'),
      ]);
      final catalogue = FakeSource('itunes', fullTracks: false, results: [
        song('i1', title: 'Night Drive', artist: 'Neon Coast', album: 'Synth Roads', seconds: 201,
            sourceId: 'itunes', playability: Playability.none, externalUrl: 'https://music.example/1'),
      ]);
      final agg = SearchAggregator(sources: () => [audius, catalogue]);

      final r = await agg.search('night drive');

      expect(r.tracks, hasLength(1));
      final t = r.tracks.single;
      expect(t.display.sourceId, 'itunes', reason: 'catalogue metadata preferred for display');
      expect(t.display.album, 'Synth Roads');
      expect(t.candidates.single.id, 'a1');
      expect(t.hasFullTrack, isTrue);
      expect(t.externalUrl, 'https://music.example/1');
    });

    test('ranks full tracks above previews above metadata-only for equal relevance', () async {
      final src = FakeSource('mixed', results: [
        song('none', title: 'Blue', artist: 'A', playability: Playability.none),
        song('prev', title: 'Blue', artist: 'B', playability: Playability.preview),
        song('full', title: 'Blue', artist: 'C'),
      ]);
      final r = await SearchAggregator(sources: () => [src]).search('blue');
      expect(r.tracks.map((t) => t.display.id).toList(), ['full', 'prev', 'none']);
      expect(r.tracks[1].previewOnly, isTrue);
      expect(r.tracks[2].isPlayable, isFalse);
    });

    test('does not pick a source just because it answered first', () async {
      final fast = FakeSource('fast', results: [song('f', title: 'Ocean Eyes Karaoke Version', artist: 'Studio')]);
      final slow = FakeSource('slow', delay: const Duration(milliseconds: 30), results: [
        song('s', title: 'Ocean Eyes', artist: 'Billie Eilish'),
      ]);
      final r = await SearchAggregator(sources: () => [fast, slow]).search('ocean eyes billie eilish');
      expect(r.tracks.first.display.id, 's');
    });

    test('one failing provider does not break search and is reported', () async {
      final ok = FakeSource('ok', results: [song('1', title: 'Rain', artist: 'X')]);
      final broken = FakeSource('broken', error: const SourceException('broken', 'HTTP 500', statusCode: 500));
      final r = await SearchAggregator(sources: () => [ok, broken]).search('rain');
      expect(r.tracks, hasLength(1));
      expect(r.failedSources.keys, ['broken']);
      expect(r.allSourcesFailed, isFalse);
    });

    test('slow provider times out without blocking the others', () async {
      final ok = FakeSource('ok', results: [song('1', title: 'Rain', artist: 'X')]);
      final hung = FakeSource('hung', delay: const Duration(seconds: 2));
      final agg = SearchAggregator(
        sources: () => [ok, hung],
        perSourceTimeout: const Duration(milliseconds: 50),
      );
      final r = await agg.search('rain');
      expect(r.tracks, hasLength(1));
      expect(r.failedSources.containsKey('hung'), isTrue);
    });

    test('all providers failing is surfaced as allSourcesFailed (offline)', () async {
      final a = FakeSource('a', error: Exception('socket'));
      final r = await SearchAggregator(sources: () => [a]).search('x');
      expect(r.allSourcesFailed, isTrue);
    });

    test('caches results and de-duplicates concurrent identical searches', () async {
      final src = FakeSource('s', results: [song('1', title: 'Hello', artist: 'Y')]);
      final agg = SearchAggregator(sources: () => [src]);
      await Future.wait([agg.search('hello'), agg.search('hello')]);
      expect(src.calls, 1);
      final cached = await agg.search('  HELLO ');
      expect(cached.fromCache, isTrue);
      expect(src.calls, 1);
    });

    test('cache expires after the TTL', () async {
      var now = DateTime(2026, 1, 1);
      final src = FakeSource('s', results: [song('1', title: 'Hello', artist: 'Y')]);
      final agg = SearchAggregator(
        sources: () => [src],
        cacheTtl: const Duration(minutes: 10),
        clock: () => now,
      );
      await agg.search('hello');
      now = now.add(const Duration(minutes: 11));
      await agg.search('hello');
      expect(src.calls, 2);
    });

    test('failed searches are not cached', () async {
      final src = FakeSource('s', error: Exception('down'));
      final agg = SearchAggregator(sources: () => [src]);
      await agg.search('hello');
      src.error = null;
      src.results = [song('1', title: 'Hello', artist: 'Y')];
      final r = await agg.search('hello');
      expect(r.tracks, hasLength(1));
    });

    test('respects per-provider rate limits', () async {
      final itunes = FakeSource('itunes', fullTracks: false);
      final agg = SearchAggregator(
        sources: () => [itunes],
        rateLimits: {'itunes': RateLimiter(2, const Duration(minutes: 1))},
      );
      await agg.search('a');
      await agg.search('b');
      final third = await agg.search('c');
      expect(itunes.calls, 2);
      expect(third.failedSources.containsKey('itunes'), isTrue);
    });

    test('remembered successful match is preferred among full tracks', () async {
      final a = FakeSource('a', results: [song('a1', title: 'Glow', artist: 'Z', seconds: 180)]);
      final b = FakeSource('b', results: [song('b1', title: 'Glow', artist: 'Z', seconds: 181)]);
      final memory = InMemoryMatchMemory();
      final agg = SearchAggregator(sources: () => [a, b], memory: memory);
      expect((await agg.search('glow')).tracks.single.candidates.first.id, 'a1');
      await agg.rememberSuccess(song('x', title: 'Glow', artist: 'Z'), song('b1', title: 'Glow', artist: 'Z'));
      agg.clearCache();
      expect((await agg.search('glow')).tracks.single.candidates.first.id, 'b1');
    });
  });

  group('SearchAggregator.findPlayableFor', () {
    test('only returns confident matches from full-track providers', () async {
      final full = FakeSource('full', results: [
        song('ok', title: 'Starlight', artist: 'Muse', seconds: 240),
        song('cover', title: 'Starlight (Cover)', artist: 'Muse', seconds: 240),
        song('other', title: 'Starlight', artist: 'Taylor Swift', seconds: 220),
      ]);
      final meta = FakeSource('itunes', fullTracks: false);
      final agg = SearchAggregator(sources: () => [full, meta]);
      final reference = song('ref', title: 'Starlight', artist: 'Muse', seconds: 240,
          sourceId: 'itunes', playability: Playability.none);

      final found = await agg.findPlayableFor(reference);

      expect(found.map((s) => s.id), ['ok']);
      expect(meta.calls, 0, reason: 'metadata providers are not queried for stream lookups');
    });

    test('excludes already-tried ids', () async {
      final full = FakeSource('full', results: [
        song('x1', title: 'Echo', artist: 'Q'),
        song('x2', title: 'Echo', artist: 'Q'),
      ]);
      final agg = SearchAggregator(sources: () => [full]);
      final found = await agg.findPlayableFor(song('r', title: 'Echo', artist: 'Q'), excludeIds: {'x1'});
      expect(found.map((s) => s.id), ['x2']);
    });
  });

  test('featured interleaves providers and drops unplayable items', () async {
    final a = FakeSource('a', featured: [song('a1'), song('a2')]);
    final b = FakeSource('b', featured: [song('b1', playability: Playability.none), song('b2')]);
    final out = await SearchAggregator(sources: () => [a, b]).featured();
    expect(out.map((s) => s.id), ['a1', 'a2', 'b2']);
  });
}
