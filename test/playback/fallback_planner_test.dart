import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/playback/fallback_planner.dart';
import 'package:music_player_app/search/search_aggregator.dart';

import '../helpers.dart';

Song perfect(String id, String source) =>
    song(id, title: 'Perfect', artist: 'Ed Sheeran', seconds: 263, sourceId: source);

void main() {
  test('11. retries the same source once, then falls back to the same recording elsewhere', () async {
    final audius = FakeSource('audius', results: [perfect('au1', 'audius')]);
    final archive = FakeSource('archive', results: [perfect('ia1', 'archive')]);
    final agg = SearchAggregator(sources: () => [audius, archive], verifier: FakeVerifier());
    final planner = FallbackPlanner(agg);
    final failed = perfect('au1', 'audius');

    expect(planner.shouldRetrySame(failed), isTrue);
    expect(planner.shouldRetrySame(failed), isFalse, reason: 'only once');

    final next = await planner.nextFor(failed);
    expect(next?.id, 'ia1', reason: 'same recording from the next authorised provider');
  });

  test('known sources of the same recording are verified before use', () async {
    final verifier = FakeVerifier(unavailable: {'known-dead'});
    final agg = SearchAggregator(sources: () => [], verifier: verifier);
    final planner = FallbackPlanner(agg);
    final failed = perfect('au1', 'audius');
    planner.registerCandidates(failed, [failed, perfect('known-dead', 'audius'), perfect('known-ok', 'archive')]);

    expect((await planner.nextFor(failed))?.id, 'known-ok');
    expect(verifier.checked, ['known-dead', 'known-ok']);
  });

  test('never falls back to a cover, an instrumental or another artist', () async {
    final audius = FakeSource('audius', results: [
      song('violin', title: 'Perfect (Violin Cover)', artist: 'Ed Sheeran', seconds: 263, sourceId: 'audius'),
      song('inst', title: 'Perfect (Instrumental)', artist: 'Ed Sheeran', seconds: 263, sourceId: 'audius'),
      song('other', title: 'Perfect', artist: 'Simple Plan', seconds: 263, sourceId: 'audius'),
    ]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [audius], verifier: FakeVerifier()));

    expect(await planner.nextFor(perfect('orig', 'archive')), isNull);
    expect(planner.explanation, contains('Original recording unavailable'));
  });

  test('uses the catalogue reference to find the same recording', () async {
    final audius = FakeSource('audius', results: [perfect('au2', 'audius')]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [audius], verifier: FakeVerifier()));
    final reference = song('itunes:1', title: 'Perfect', artist: 'Ed Sheeran', seconds: 263,
        sourceId: 'itunes', playability: Playability.none);
    expect((await planner.nextFor(perfect('au1', 'audius'), reference: reference))?.id, 'au2');
  });

  test('does not retry a stream the verifier knows is gone', () {
    final agg = SearchAggregator(sources: () => [], verifier: FakeVerifier(unavailable: {'gone'}));
    expect(FallbackPlanner(agg).shouldRetrySame(perfect('gone', 'audius')), isFalse);
  });

  test('local files have no alternative source', () async {
    final audius = FakeSource('audius', results: [song('remote', title: 'Mine', artist: 'Me')]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [audius]));
    final local = song('local:1', title: 'Mine', artist: 'Me', playability: Playability.local);
    expect(await planner.nextFor(local), isNull);
    expect(audius.calls, 0);
  });

  test('network failure during lookup yields null with an explanation', () async {
    final down = FakeSource('audius', error: Exception('offline'));
    final planner = FallbackPlanner(SearchAggregator(sources: () => [down]));
    expect(await planner.nextFor(perfect('a', 'archive')), isNull);
    expect(planner.explanation, contains('could not be reached'));
  });

  test('caps attempts per song', () async {
    final many = FakeSource('audius', results: [for (var i = 0; i < 10; i++) perfect('c$i', 'audius')]);
    final planner = FallbackPlanner(
      SearchAggregator(sources: () => [many], verifier: FakeVerifier()),
      maxAttemptsPerSong: 3,
    );
    var current = perfect('start', 'archive');
    var tries = 0;
    while (true) {
      final next = await planner.nextFor(current);
      if (next == null) break;
      current = next;
      tries++;
    }
    expect(tries, 2);
  });
}
