import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/search/text_normalizer.dart';
import 'package:music_player_app/search/track_matcher.dart';

import '../helpers.dart';

void main() {
  group('TextNormalizer', () {
    test('strips featured artists, brackets and remaster suffixes', () {
      expect(TextNormalizer.title('Señorita (feat. Camila Cabello)'), 'senorita');
      expect(TextNormalizer.title('Bohemian Rhapsody - Remastered 2011'), 'bohemian rhapsody');
      expect(TextNormalizer.title('Blinding Lights [Official Audio]'), 'blinding lights');
      expect(TextNormalizer.title('Song ft. Someone'), 'song');
    });

    test('keeps "with" when it is part of the title', () {
      expect(TextNormalizer.title('Stay With Me'), 'stay with me');
      expect(TextNormalizer.title('With or Without You'), 'with or without you');
      expect(TextNormalizer.title('Fine (with Friend)'), 'fine');
    });

    test('extracts version tags that change the recording', () {
      expect(TextNormalizer.versionTags('Song (Live at Wembley)'), {'live'});
      expect(TextNormalizer.versionTags('Song - Karaoke Version'), {'karaoke'});
      expect(TextNormalizer.versionTags('Song (Radio Edit)'), isEmpty);
      expect(TextNormalizer.versionTags('Song (Sped Up)'), {'sped'});
    });

    test('splits artist credits', () {
      expect(TextNormalizer.artists('Daft Punk feat. Pharrell Williams & Nile Rodgers'),
          {'daft punk', 'pharrell williams', 'nile rodgers'});
      expect(TextNormalizer.artists('Beyoncé'), {'beyonce'});
    });

    test('songKey is stable across formatting differences', () {
      expect(
        TextNormalizer.songKey('Levitating (feat. DaBaby)', 'Dua Lipa'),
        TextNormalizer.songKey('LEVITATING', 'dua lipa'),
      );
    });
  });

  group('TrackMatcher.sameSong', () {
    const m = TrackMatcher();

    test('matches the same song across providers despite metadata noise', () {
      final a = song('1', title: 'Bohemian Rhapsody - Remastered 2011', artist: 'Queen', seconds: 354);
      final b = song('2', title: 'Bohemian Rhapsody', artist: 'Queen', seconds: 355);
      expect(m.isSameSong(a, b), isTrue);
    });

    test('rejects a karaoke / live / cover version as the original', () {
      final orig = song('1', title: 'Hello', artist: 'Adele', seconds: 295);
      expect(m.isSameSong(orig, song('2', title: 'Hello (Karaoke Version)', artist: 'Adele', seconds: 295)), isFalse);
      expect(m.isSameSong(orig, song('3', title: 'Hello (Live)', artist: 'Adele', seconds: 300)), isFalse);
    });

    test('rejects same title by a different artist', () {
      final a = song('1', title: 'Hello', artist: 'Adele', seconds: 295);
      final b = song('2', title: 'Hello', artist: 'Lionel Richie', seconds: 245);
      expect(m.isSameSong(a, b), isFalse);
    });

    test('rejects strongly mismatched durations', () {
      final a = song('1', title: 'Intro', artist: 'The XX', seconds: 127);
      final b = song('2', title: 'Intro', artist: 'The XX', seconds: 600);
      expect(m.sameSong(a, b), lessThan(m.sameSong(a, song('3', title: 'Intro', artist: 'The XX', seconds: 128))));
    });

    test('ignores duration for 30-second previews', () {
      final full = song('1', title: 'Midnight City', artist: 'M83', seconds: 244);
      final preview = song('2', title: 'Midnight City', artist: 'M83', seconds: 30, playability: Playability.preview);
      expect(m.isSameSong(full, preview), isTrue);
    });

    test('tolerates small typos', () {
      final a = song('1', title: 'Smells Like Teen Spirit', artist: 'Nirvana');
      final b = song('2', title: 'Smells Like Teen Sprit', artist: 'Nirvana');
      expect(m.isSameSong(a, b), isTrue);
    });
  });

  group('TrackMatcher.relevance', () {
    const m = TrackMatcher();

    test('exact title + artist ranks above partial matches', () {
      final exact = song('1', title: 'Shape of You', artist: 'Ed Sheeran');
      final partial = song('2', title: 'The Shape of Things to Come', artist: 'Someone');
      expect(m.relevance('shape of you ed sheeran', exact),
          greaterThan(m.relevance('shape of you ed sheeran', partial)));
    });

    test('unrequested remixes are penalised', () {
      final orig = song('1', title: 'Titanium', artist: 'David Guetta');
      final remix = song('2', title: 'Titanium (Remix)', artist: 'David Guetta');
      expect(m.relevance('titanium', orig), greaterThan(m.relevance('titanium', remix)));
      // …but not when the user asked for it.
      expect(m.relevance('titanium remix', remix), greaterThanOrEqualTo(m.relevance('titanium remix', orig)));
    });

    test('empty query has zero relevance', () {
      expect(m.relevance('   ', song('1')), 0);
    });
  });
}
