@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/playback/stream_verifier.dart';
import 'package:music_player_app/search/search_aggregator.dart';
import 'package:music_player_app/sources/audius_source.dart';
import 'package:music_player_app/sources/freetouse_source.dart';
import 'package:music_player_app/sources/internet_archive_source.dart';
import 'package:music_player_app/sources/itunes_source.dart';
import 'package:music_player_app/sources/music_source.dart';
import 'package:music_player_app/sources/musicbrainz_source.dart';
import 'package:music_player_app/sources/radio_source.dart';

/// LIVE provider checks — real network, results change over time.
///
/// Not part of CI (`flutter test` only runs test/). Run manually:
///
///   flutter test test_live
///
/// These tests *report* what each provider returns for the Bangla and
/// English datasets; they only fail on crashes or rule violations (e.g. a
/// result labelled as the original that isn't), never on "not found",
/// because catalogue coverage is outside this app's control. A provider
/// that is unreachable / rate-limited is reported as such, not as a failure.
void main() {
  // Song + artist queries from the spec's dataset (examples, not hardcoded
  // results): Bangladesh, West Bengal and English.
  const bangla = [
    'Hashnahena Shironamhin', 'Bondho Janala Shironamhin', 'Pakhi Shironamhin', 'Jahaji Shironamhin',
    'Ei Obelay Shironamhin', 'Cafeteria Shironamhin', 'শিরোনামহীন হাসনাহেনা',
    'Obak Bhalobasha Warfaze', 'Boshe Achi Warfaze', 'Shei Tumi LRB', 'Ferari Mon LRB',
    'Firiye Dao Miles', 'Neela Miles', 'Oniket Prantor Artcell', 'Dhushor Shomoy Artcell',
    'Guti Aurthohin', 'Amar Protichhobi Aurthohin', 'Kobe Nemesis', 'Ghor Nemesis', 'Bangladesh Cryptic Fate',
    'Jadur Shohor Chirkutt', 'E Hawa Meghdol', 'Punorjonmo Avoidrafa', 'She Je Boshe Ache Arnob',
    'Hok Kolorob Arnob', 'Maya Habib Wahid', 'Din Gelo Habib Wahid', 'Alo Tahsan', 'Maa James',
    'Bheegi Bheegi James', 'Rupali Guitar Ayub Bachchu', 'জেমস', 'Lalon Shah',
    'Anupam Roy', 'Rupam Islam', 'Fossils', 'Chandrabindoo', 'Nachiketa', 'Arijit Singh',
  ];
  const english = [
    'Perfect Ed Sheeran', 'Shape of You Ed Sheeran', 'Photograph Ed Sheeran', 'Love Story Taylor Swift',
    'Blank Space Taylor Swift', 'Yellow Coldplay', 'Fix You Coldplay', 'Hello Adele', 'Someone Like You Adele',
    'Demons Imagine Dragons', 'Believer Imagine Dragons', 'Numb Linkin Park', 'In the End Linkin Park',
    'Lose Yourself Eminem', 'Blinding Lights The Weeknd', 'Bohemian Rhapsody Queen', 'Billie Jean Michael Jackson',
  ];

  Future<void> report(SearchAggregator agg, String q) async {
    // Stay under Apple's ~20 requests/minute (each query can make 2 calls).
    await Future<void>.delayed(const Duration(seconds: 6));
    final r = await agg.search(q);
    final best = r.bestMatch;
    final line = StringBuffer('[$q] ');
    if (best != null) {
      line.write('best="${best.display.title}" by ${best.display.artist} → ');
      line.write(best.isPlayable ? 'playable via ${best.best.sourceId}' : 'original unavailable');
      if (best.isPlayable) {
        // Rule: whatever is offered as the original must match it exactly.
        expect(agg.matcher.matchRecording(best.display, best.best).isExact || best.display.sourceId == best.best.sourceId,
            isTrue, reason: '$q: ${best.best.title} by ${best.best.artist}');
      }
    } else {
      line.write('${r.tracks.length} results (${r.playableSongs.length} playable)');
    }
    line.write(' | ${r.attempts.join(', ')}');
    // ignore: avoid_print
    print(line);
  }

  group('live search', () {
    final sources = <MusicSource>[AudiusSource(), InternetArchiveSource(), ItunesSource()];
    final agg = SearchAggregator(
      sources: () => sources,
      // Real 2-byte probe of each candidate stream.
      verifier: HttpStreamVerifier(
        sourceById: (id) => sources.where((s) => s.id == id).firstOrNull,
        checkHttp: true,
      ),
    );

    for (final q in bangla) {
      test('Bangla: $q', () => report(agg, q), timeout: const Timeout(Duration(seconds: 90)));
    }
    for (final q in english) {
      test('English: $q', () => report(agg, q), timeout: const Timeout(Duration(seconds: 90)));
    }
  });

  group('live providers', () {
    Future<void> probe(String name, Future<List<Object?>> Function() run) async {
      try {
        final r = await run();
        // ignore: avoid_print
        print('[$name] ${r.length} results');
      } on SourceException catch (e) {
        // ignore: avoid_print
        print('[$name] unavailable: ${e.message}');
      }
    }

    test('Free To Use search (API reachable; playback needs a commercial licence)',
        () => probe('freetouse', () => FreeToUseSource().searchTracks('piano')));
    test('MusicBrainz recording search',
        () => probe('musicbrainz', () => MusicBrainzSource().searchTracks('Shironamhin')));
    test('Radio Browser: Bangladesh', () => probe('radio BD', () => RadioSource().searchByCountry('BD')));
    test('Radio Browser: Bengali language', () => probe('radio bn', () => RadioSource().searchByLanguage('bengali')));
  });
}
