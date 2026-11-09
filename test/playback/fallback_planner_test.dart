import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/playback/fallback_planner.dart';
import 'package:music_player_app/search/search_aggregator.dart';

import '../helpers.dart';

void main() {
  test('tries known candidates first, then a fresh search, then gives up', () async {
    final alt = FakeSource('alt', results: [song('found', title: 'Aurora', artist: 'Sky')]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [alt]));
    final failed = song('first', title: 'Aurora', artist: 'Sky');
    planner.registerCandidates(failed, [failed, song('known', title: 'Aurora', artist: 'Sky')]);

    expect((await planner.nextFor(failed))?.id, 'known');
    expect((await planner.nextFor(song('known', title: 'Aurora', artist: 'Sky')))?.id, 'found');
    expect(await planner.nextFor(song('found', title: 'Aurora', artist: 'Sky')), isNull);
  });

  test('never falls back to a different recording', () async {
    final alt = FakeSource('alt', results: [song('k', title: 'Aurora (Karaoke)', artist: 'Sky')]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [alt]));
    expect(await planner.nextFor(song('x', title: 'Aurora', artist: 'Sky')), isNull);
  });

  test('retries the same source once only after a mid-stream drop', () {
    final planner = FallbackPlanner(SearchAggregator(sources: () => []));
    final s = song('a');
    expect(planner.shouldRetrySame(s, hadStarted: false), isFalse);
    expect(planner.shouldRetrySame(s, hadStarted: true), isTrue);
    expect(planner.shouldRetrySame(s, hadStarted: true), isFalse);
    planner.markSuccess(s);
    expect(planner.shouldRetrySame(s, hadStarted: true), isTrue);
  });

  test('local files have no alternative source', () async {
    final alt = FakeSource('alt', results: [song('remote', title: 'Mine', artist: '')]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [alt]));
    final local = song('local:1', title: 'Mine', artist: '', playability: Playability.local);
    expect(await planner.nextFor(local), isNull);
    expect(alt.calls, 0);
  });

  test('network failure during lookup yields null instead of throwing', () async {
    final down = FakeSource('down', error: Exception('offline'));
    final planner = FallbackPlanner(SearchAggregator(sources: () => [down]));
    expect(await planner.nextFor(song('a', title: 'T', artist: 'A')), isNull);
  });

  test('caps attempts per song', () async {
    final many = FakeSource('m', results: [
      for (var i = 0; i < 10; i++) song('c$i', title: 'Loop', artist: 'L'),
    ]);
    final planner = FallbackPlanner(SearchAggregator(sources: () => [many]), maxAttemptsPerSong: 3);
    var current = song('start', title: 'Loop', artist: 'L');
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
