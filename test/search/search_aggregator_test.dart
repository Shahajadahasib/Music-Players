import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/search/matched_track.dart';
import 'package:music_player_app/search/search_aggregator.dart';
import 'package:music_player_app/sources/music_source.dart';

import '../helpers.dart';

/// Catalogue (metadata-only, like iTunes) answer for "Perfect – Ed Sheeran".
FakeSource catalogue({List<Song>? results}) => FakeSource('itunes',
    fullTracks: false,
    results: results ??
        [
          song('itunes:1', title: 'Perfect', artist: 'Ed Sheeran', album: '÷', seconds: 263,
              sourceId: 'itunes', playability: Playability.none, externalUrl: 'https://music.apple.test/1'),
        ]);

Song original(String id, String source) =>
    song(id, title: 'Perfect', artist: 'Ed Sheeran', seconds: 263, sourceId: source);

void main() {
  const query = 'perfect ed sheeran';

  group('sequential search for a specific song', () {
    test('7/8/9. stops at the first provider with a verified original; later providers are not asked', () async {
      final meta = catalogue();
      final audius = FakeSource('audius', results: [original('au1', 'audius')]);
      final jamendo = FakeSource('jamendo', results: [original('ja1', 'jamendo')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final verifier = FakeVerifier();
      final agg = SearchAggregator(sources: () => [audius, jamendo, archive, meta], verifier: verifier);

      final r = await agg.search(query);

      expect(meta.calls, 1, reason: 'metadata is looked up first, independently');
      expect(audius.calls, 1);
      expect(jamendo.calls, 0, reason: 'no unnecessary requests after a verified match');
      expect(archive.calls, 0);
      expect(verifier.checked, ['au1']);
      final best = r.bestMatch!;
      expect(best.display.id, 'itunes:1', reason: 'catalogue metadata is shown');
      expect(best.best.id, 'au1');
      expect(best.verifiedIds, {'au1'});
      expect(r.attempts.map((a) => '${a.sourceId}:${a.outcome.name}'),
          ['itunes:results', 'audius:verified']);
    });

    test('moves to the next provider only when the current one has no acceptable original', () async {
      final audius = FakeSource('audius', results: [
        song('cover', title: 'Perfect (Violin Cover)', artist: 'Strings Guy', seconds: 250, sourceId: 'audius'),
        song('other', title: 'Perfect', artist: 'Simple Plan', seconds: 280, sourceId: 'audius'),
      ]);
      final jamendo = FakeSource('jamendo', results: []);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final agg = SearchAggregator(sources: () => [audius, jamendo, archive, catalogue()], verifier: FakeVerifier());

      final r = await agg.search(query);

      expect([audius.calls, jamendo.calls, archive.calls], [1, 1, 1]);
      expect(r.bestMatch!.best.id, 'ia1');
      // The cover and the other artist are listed separately, never merged
      // into the original.
      final others = r.tracks.where((t) => !t.isBestMatch).map((t) => t.display.id);
      expect(others, containsAll(['cover', 'other']));
      expect(r.bestMatch!.candidates.map((c) => c.id), ['ia1']);
    });

    test('uploads naming the artist but published by someone else are hidden (likely re-uploads)', () async {
      final audius = FakeSource('audius', results: [
        song('reup', title: 'Ed Sheeran - Perfect (Lyrics)', artist: 'The biggest song', seconds: 263, sourceId: 'audius'),
        song('reup2', title: 'Perfect - Ed Sheeran (DJ Edit)', artist: 'Some DJ', seconds: 200, sourceId: 'audius'),
        song('own', title: 'My Perfect Day', artist: 'Indie Band', seconds: 200, sourceId: 'audius'),
      ]);
      final r = await SearchAggregator(sources: () => [audius, catalogue()], verifier: FakeVerifier()).search(query);
      final ids = r.tracks.map((t) => t.display.id).toList();
      expect(ids, isNot(contains('reup')));
      expect(ids, isNot(contains('reup2')));
      expect(r.bestMatch!.originalUnavailable, isTrue);
    });

    test('catalogue duplicates of the same recording fold into the best match', () async {
      final meta = catalogue(results: [
        song('itunes:1', title: 'Perfect', artist: 'Ed Sheeran', album: '÷', seconds: 263,
            sourceId: 'itunes', playability: Playability.none),
        song('itunes:2', title: 'Perfect', artist: 'Ed Sheeran', album: 'Hits', seconds: 263,
            sourceId: 'itunes', playability: Playability.none),
        song('itunes:3', title: 'Perfect Duet', artist: 'Ed Sheeran & Beyoncé', seconds: 259,
            sourceId: 'itunes', playability: Playability.none),
      ]);
      final r = await SearchAggregator(sources: () => [FakeSource('audius'), meta]).search(query);
      expect(r.tracks.map((t) => t.display.id), isNot(contains('itunes:2')));
      expect(r.bestMatch!.references.map((s) => s.id), contains('itunes:2'));
      expect(r.tracks.map((t) => t.display.id), contains('itunes:3'), reason: 'a different recording');
    });

    test('13. no valid original anywhere → "original unavailable", covers are not substituted', () async {
      final audius = FakeSource('audius', results: [
        song('cover', title: 'Perfect - Piano Version', artist: 'Ed Sheeran', seconds: 263, sourceId: 'audius'),
      ]);
      final archive = FakeSource('archive', results: [
        song('inst', title: 'Perfect (Instrumental)', artist: 'Ed Sheeran', seconds: 263, sourceId: 'archive'),
      ]);
      final agg = SearchAggregator(sources: () => [audius, archive, catalogue()], verifier: FakeVerifier());

      final r = await agg.search(query);

      final best = r.bestMatch!;
      expect(best.originalUnavailable, isTrue);
      expect(best.isPlayable, isFalse);
      expect(best.externalUrl, 'https://music.apple.test/1');
      expect(r.attempts.where((a) => a.outcome == AttemptOutcome.noMatch).map((a) => a.sourceId),
          ['audius', 'archive']);
    });

    test('an exact match whose stream fails verification is not offered; next provider is asked', () async {
      final audius = FakeSource('audius', results: [original('au-dead', 'audius')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final verifier = FakeVerifier(unavailable: {'au-dead'});
      final agg = SearchAggregator(sources: () => [audius, archive, catalogue()], verifier: verifier);

      final r = await agg.search(query);

      expect(verifier.checked, ['au-dead', 'ia1']);
      expect(r.bestMatch!.best.id, 'ia1');
      expect(r.attempts.firstWhere((a) => a.sourceId == 'audius').outcome, AttemptOutcome.unplayable);
    });

    test('another stream of the same recording on the same provider is tried before moving on', () async {
      final audius = FakeSource('audius', results: [original('au-dead', 'audius'), original('au-ok', 'audius')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final agg = SearchAggregator(
        sources: () => [audius, archive, catalogue()],
        verifier: FakeVerifier(unavailable: {'au-dead'}),
      );
      final r = await agg.search(query);
      expect(r.bestMatch!.best.id, 'au-ok');
      expect(archive.calls, 0);
    });
  });

  group('which catalogue song (if any) the query names', () {
    final agg = SearchAggregator(sources: () => []);
    Song cat(String id, String title, String artist) =>
        song(id, title: title, artist: artist, sourceId: 'itunes', playability: Playability.none);

    test('title + artist named → that song', () {
      final p = cat('p', 'Perfect', 'Ed Sheeran');
      expect(agg.pickReference('perfect ed sheeran', [cat('x', 'Perfect', 'Simple Plan'), p])?.id, 'p');
    });

    test('a one-word title without the artist is an open search', () {
      expect(agg.pickReference('perfect', [cat('p', 'Perfect', 'Ed Sheeran')]), isNull);
      expect(agg.pickReference('blue', [cat('b', 'Blue Hour', 'X')]), isNull);
    });

    test('an artist word that is also the title word does not count ("lofi" by "LoFi Hip Hop")', () {
      expect(agg.pickReference('lofi', [cat('l', 'Lofi', 'LoFi Hip Hop')]), isNull);
    });

    test('a multi-word title owned by one artist is specific; a title many artists perform is not', () {
      // Shape of the real iTunes answer: the original first, the owner's
      // remixes, and one-off covers by many other artists.
      final shape = [
        cat('s1', 'Shape of You', 'Ed Sheeran'), cat('s2', 'Shape of You (NOTD Remix)', 'Ed Sheeran'),
        cat('s3', 'Shape of You (Acoustic)', 'Ed Sheeran'), cat('s4', 'Shape of You', 'Fame on Fire'),
        cat('s5', 'Shape of You', 'Walk Off the Earth'), cat('s6', 'Shape of You', 'Eat Your Heart Out'),
      ];
      expect(agg.pickReference('shape of you', shape)?.id, 's1');
      final sonata = [cat('m1', 'Moonlight Sonata', 'Global Journey'), cat('m2', 'Moonlight Sonata', 'Daniel Barenboim'),
        cat('m3', 'Moonlight Sonata', 'Lang Lang')];
      expect(agg.pickReference('moonlight sonata', sonata), isNull);
      expect(agg.pickReference('moonlight sonata beethoven', sonata), isNull,
          reason: 'unexplained query words (composer) → not a specific recording');
    });
  });

  group('free-text search', () {
    test('discovery searches gather results across providers, one at a time', () async {
      final audius = FakeSource('audius', results: [song('l1', title: 'Lofi Morning', artist: 'Beats', sourceId: 'audius')]);
      final archive = FakeSource('archive', results: [song('l2', title: 'Lofi Night', artist: 'X', sourceId: 'archive')]);
      final agg = SearchAggregator(sources: () => [audius, archive], verifier: FakeVerifier());
      final r = await agg.search('lofi');
      expect([audius.calls, archive.calls], [1, 1], reason: 'one result is not enough for a useful list');
      expect(r.bestMatch, isNull);
      expect(r.tracks.map((t) => t.display.id), containsAll(['l1', 'l2']));
    });

    test('discovery stops once enough results are collected (no extra requests)', () async {
      final audius = FakeSource('audius', results: [
        for (var i = 0; i < 5; i++) song('l$i', title: 'Lofi Mix $i', artist: 'Beats $i', sourceId: 'audius'),
      ]);
      final archive = FakeSource('archive', results: [song('x', title: 'Lofi Night', artist: 'X', sourceId: 'archive')]);
      final agg = SearchAggregator(sources: () => [audius, archive], verifier: FakeVerifier(), discoveryTarget: 5);
      await agg.search('lofi');
      expect(archive.calls, 0);
    });

    test('asks the next provider when the first has nothing relevant', () async {
      final audius = FakeSource('audius', results: []);
      final archive = FakeSource('archive', results: [song('l2', title: 'Lofi Night', artist: 'X', sourceId: 'archive')]);
      final r = await SearchAggregator(sources: () => [audius, archive]).search('lofi');
      expect(archive.calls, 1);
      expect(r.tracks.single.display.id, 'l2');
    });

    test('ranks full tracks above metadata-only results for equal relevance', () async {
      final meta = FakeSource('itunes', fullTracks: false, results: [
        song('none', title: 'Blue Hour', artist: 'A', sourceId: 'itunes', playability: Playability.none),
      ]);
      final audius = FakeSource('audius', results: [song('full', title: 'Blue Sky', artist: 'C', sourceId: 'audius')]);
      final r = await SearchAggregator(sources: () => [audius, meta]).search('blue');
      expect(r.tracks.map((t) => t.display.id).toList(), ['full', 'none']);
    });
  });

  group('timeouts, failures and rate limits', () {
    test('10a. a slow provider times out and the next provider is asked', () async {
      final hung = FakeSource('audius', delay: const Duration(seconds: 2), results: [original('late', 'audius')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final agg = SearchAggregator(
        sources: () => [hung, archive, catalogue()],
        perSourceTimeout: const Duration(milliseconds: 50),
        verifier: FakeVerifier(),
      );
      final r = await agg.search(query);
      expect(r.bestMatch!.best.id, 'ia1');
      expect(r.failedSources.containsKey('audius'), isTrue);
      expect(r.attempts.first.sourceId, 'itunes');
      expect(r.attempts[1].outcome, AttemptOutcome.timeout);
    });

    test('10b. rate-limited providers are skipped without a request', () async {
      final meta = catalogue();
      final agg = SearchAggregator(
        sources: () => [FakeSource('audius'), meta],
        rateLimits: {'itunes': RateLimiter(2, const Duration(minutes: 1))},
      );
      await agg.search('a');
      await agg.search('b');
      final third = await agg.search('c');
      expect(meta.calls, 2);
      expect(third.attempts.first.outcome, AttemptOutcome.rateLimited);
    });

    test('a provider error is reported with its cause and does not stop the others', () async {
      final broken = FakeSource('audius', error: const SourceException('audius', 'HTTP 500', statusCode: 500));
      final archive = FakeSource('archive', results: [song('1', title: 'Rain', artist: 'X', sourceId: 'archive')]);
      final agg = SearchAggregator(sources: () => [broken, archive]);
      final r = await agg.search('rain');
      expect(r.tracks, hasLength(1));
      expect(r.failedSources.keys, ['audius']);
      expect(agg.lastFailureDetails['audius'], contains('HTTP 500'));
    });

    test('all providers failing is reported as offline and not cached', () async {
      final a = FakeSource('audius', error: Exception('socket'));
      final agg = SearchAggregator(sources: () => [a]);
      expect((await agg.search('x')).allSourcesFailed, isTrue);
      a.error = null;
      a.results = [song('1', title: 'X ray', artist: 'Y', sourceId: 'audius')];
      expect((await agg.search('x')).tracks, hasLength(1));
    });
  });

  group('caching, de-duplication and cancellation', () {
    test('12. identical searches are de-duplicated and cached', () async {
      final audius = FakeSource('audius', results: [song('1', title: 'Hello', artist: 'Y', sourceId: 'audius')]);
      final agg = SearchAggregator(sources: () => [audius]);
      await Future.wait([agg.search('hello'), agg.search('hello')]);
      expect(audius.calls, 1);
      expect((await agg.search('  HELLO ')).fromCache, isTrue);
      expect(audius.calls, 1);
    });

    test('cache expires after the TTL', () async {
      var now = DateTime(2026, 1, 1);
      final audius = FakeSource('audius', results: [song('1', title: 'Hello', artist: 'Y', sourceId: 'audius')]);
      final agg = SearchAggregator(sources: () => [audius], cacheTtl: const Duration(minutes: 10), clock: () => now);
      await agg.search('hello');
      now = now.add(const Duration(minutes: 11));
      await agg.search('hello');
      expect(audius.calls, 2);
    });

    test('a cancelled search sends no further provider requests', () async {
      final meta = catalogue();
      final audius = FakeSource('audius', results: [original('au1', 'audius')]);
      var cancelled = false;
      meta.onSearch = () => cancelled = true; // a newer query arrives meanwhile
      final r = await SearchAggregator(sources: () => [audius, meta]).search(query, isCancelled: () => cancelled);
      expect(r.cancelled, isTrue);
      expect(audius.calls, 0);
    });
  });

  group('discover (catalogue tap / album / fallback)', () {
    final ref = song('itunes:1', title: 'Perfect', artist: 'Ed Sheeran', seconds: 263,
        sourceId: 'itunes', playability: Playability.none);

    test('stops after the first verified original and caches the result', () async {
      final audius = FakeSource('audius', results: [original('au1', 'audius')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final meta = catalogue();
      final agg = SearchAggregator(sources: () => [audius, archive, meta], verifier: FakeVerifier());

      final d = await agg.discover(ref);
      expect(d.playable!.id, 'au1');
      expect(archive.calls, 0);
      expect(meta.calls, 0, reason: 'metadata providers are not used to find streams');

      final again = await agg.discover(ref);
      expect(again.fromCache, isTrue);
      expect(audius.calls, 1, reason: '12. cached successful match is reused');
    });

    test('a cached match whose stream is now known to be gone is not reused', () async {
      final audius = FakeSource('audius', results: [original('au1', 'audius')]);
      final verifier = FakeVerifier();
      final agg = SearchAggregator(sources: () => [audius], verifier: verifier);
      await agg.discover(ref);
      verifier.unavailable.add('au1');
      final d = await agg.discover(ref);
      expect(d.fromCache, isFalse);
      expect(d.found, isFalse);
    });

    test('after the player fails a discovered stream, discovery finds another source of the same recording', () async {
      final audius = FakeSource('audius', results: [original('au1', 'audius')]);
      final archive = FakeSource('archive', results: [original('ia1', 'archive')]);
      final verifier = FakeVerifier();
      final agg = SearchAggregator(sources: () => [audius, archive], verifier: verifier);
      expect((await agg.discover(ref)).playable!.id, 'au1');
      expect(archive.calls, 0);
      verifier.markUnplayable('au1'); // player could not decode it
      final d = await agg.discover(ref);
      expect(d.fromCache, isFalse);
      expect(d.playable!.id, 'ia1');
    });

    test('remembered successful match is preferred', () async {
      final audius = FakeSource('audius', results: [original('au1', 'audius'), original('au2', 'audius')]);
      final memory = InMemoryMatchMemory();
      final agg = SearchAggregator(sources: () => [audius], memory: memory, verifier: FakeVerifier());
      await agg.rememberSuccess(ref, original('au2', 'audius'));
      expect((await agg.discover(ref)).playable!.id, 'au2');
    });

    test('13. nothing exact anywhere → not found, with an explanation', () async {
      final audius = FakeSource('audius', results: [
        song('cover', title: 'Perfect (Violin Cover)', artist: 'Ed Sheeran', sourceId: 'audius'),
      ]);
      final d = await SearchAggregator(sources: () => [audius], verifier: FakeVerifier()).discover(ref);
      expect(d.found, isFalse);
      expect(d.explanation, contains('Original recording unavailable'));
    });

    test('featured interleaves providers and drops unplayable items', () async {
      final a = FakeSource('a', featured: [song('a1'), song('a2')]);
      final b = FakeSource('b', featured: [song('b1', playability: Playability.none), song('b2')]);
      final out = await SearchAggregator(sources: () => [a, b]).featured();
      expect(out.map((s) => s.id), ['a1', 'a2', 'b2']);
    });
  });
}
