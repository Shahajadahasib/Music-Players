import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/search/artist_aliases.dart';
import 'package:music_player_app/search/text_normalizer.dart';
import 'package:music_player_app/search/track_matcher.dart';

import '../helpers.dart';

/// Bangla (Unicode + transliteration) and English matching dataset.
/// All titles/durations are synthetic fixtures used to exercise the rules;
/// the live dataset is in test_live/.
void main() {
  const matcher = TrackMatcher();

  Song withIsrc(Song s, String isrc) => s.copyWith(isrc: isrc);

  group('Bengali text normalisation', () {
    test('Bengali text survives normalisation (not stripped as punctuation)', () {
      expect(TextNormalizer.basic('শিরোনামহীন'), isNotEmpty);
      expect(TextNormalizer.basic('বন্ধ জানালা!'), 'বন্ধ জানালা');
      expect(TextNormalizer.containsBengali('Hasan রাজা'), isTrue);
      expect(TextNormalizer.containsBengali('Shironamhin'), isFalse);
    });

    test('Bengali version keywords are recognised', () {
      expect(TextNormalizer.versionTags('বন্ধ জানালা (কভার)'), isNotEmpty);
      expect(TextNormalizer.versionTags('বন্ধ জানালা লাইভ'), isNotEmpty);
      expect(TextNormalizer.versionTags('বন্ধ জানালা'), isEmpty);
    });

    test('transliteration produces Latin text', () {
      final latin = TextNormalizer.bengaliToLatin('জেমস');
      expect(TextNormalizer.containsBengali(latin), isFalse);
      expect(latin, isNotEmpty);
    });

    // Song-title spellings. (Band names whose English spelling isn't
    // phonetic — Warfaze, Artcell, Miles, James — are covered by the alias
    // table instead.)
    const pairs = {
      'শিরোনামহীন': 'Shironamhin',
      'চিরকুট': 'Chirkutt',
      'মেঘদল': 'Meghdol',
      'অর্ণব': 'Arnob',
      'তাহসান': 'Tahsan',
      'বন্ধ জানালা': 'Bondho Janala',
      'হাসিমুখ': 'Hashimukh',
    };
    for (final e in pairs.entries) {
      test('phonetic key: ${e.key} ≈ ${e.value}', () {
        expect(TextNormalizer.phoneticKey(e.key), TextNormalizer.phoneticKey(e.value));
      });
    }

    test('phonetic key still separates different words', () {
      expect(TextNormalizer.phoneticKey('Perfect'), isNot(TextNormalizer.phoneticKey('Prefect')));
      expect(TextNormalizer.phoneticKey('Miles'), isNot(TextNormalizer.phoneticKey('Meghdol')));
    });
  });

  group('Artist aliases', () {
    test('Bengali and Latin spellings are the same artist', () {
      expect(ArtistAliases.sameArtist('শিরোনামহীন', 'Shironamhin'), isTrue);
      expect(ArtistAliases.sameArtist('LRB', 'Love Runs Blind'), isTrue);
      expect(ArtistAliases.sameArtist('আইয়ুব বাচ্চু', 'Ayub Bachchu'), isTrue);
      expect(ArtistAliases.sameArtist('Ayub Bacchu', 'Ayub Bachchu'), isTrue);
      expect(ArtistAliases.sameArtist('Anupam Roy', 'অনুপম রায়'), isTrue);
    });

    test('different artists are never merged', () {
      expect(ArtistAliases.sameArtist('James', 'Miles'), isFalse);
      expect(ArtistAliases.sameArtist('Warfaze', 'Artcell'), isFalse);
      expect(ArtistAliases.sameArtist('James', 'James Arthur'), isFalse);
    });

    test('query variants add the other script and a transliteration', () {
      final v = ArtistAliases.queryVariants('শিরোনামহীন');
      expect(v.first, 'শিরোনামহীন', reason: 'original query first');
      expect(v, contains('shironamhin'));
      final en = ArtistAliases.queryVariants('James');
      expect(en, contains('জেমস'));
      expect(ArtistAliases.queryVariants('Ed Sheeran'), ['Ed Sheeran'],
          reason: 'no variants for artists without aliases');
    });

    test('a Latin artist also gets its other Latin spelling (how catalogues credit it)', () {
      final v = ArtistAliases.queryVariants('Shei Tumi LRB');
      expect(v.first, 'Shei Tumi LRB');
      expect(v, contains('shei tumi love runs blind'));
      expect(v.length, lessThanOrEqualTo(3), reason: 'bounded requests per provider');
    });

    test('query variants keep the song part of "artist song" queries', () {
      final v = ArtistAliases.queryVariants('শিরোনামহীন হাসিমুখ');
      expect(v, contains('shironamhin হাসিমুখ'), reason: 'artist swapped to Latin, song kept');
      expect(v.any((q) => q.startsWith('shironamhin ') && !TextNormalizer.containsBengali(q)), isTrue,
          reason: 'fully transliterated variant: $v');
    });
  });

  group('Shironamhin / Bangla dataset — exact recording rules', () {
    final ref = song('itunes:1', title: 'Bondho Janala', artist: 'Shironamhin', seconds: 300, sourceId: 'itunes');

    test('same song in Bengali script with agreeing duration is exact', () {
      final c = song('a1', title: 'বন্ধ জানালা', artist: 'শিরোনামহীন', seconds: 302);
      expect(matcher.matchRecording(ref, c).isExact, isTrue, reason: '${matcher.matchRecording(ref, c)}');
    });

    test('Latin spelling variant of the artist is accepted', () {
      final c = song('a2', title: 'Bondho Janala', artist: 'Shironamheen', seconds: 299);
      expect(matcher.matchRecording(ref, c).isExact, isTrue);
    });

    test('transliterated title without a known duration is not confirmed', () {
      final c = song('a3', title: 'বন্ধ জানালা', artist: 'শিরোনামহীন');
      expect(matcher.matchRecording(ref, c).verdict, RecordingVerdict.transliterationUnconfirmed);
    });

    test('transliterated title with a different length is rejected', () {
      final c = song('a4', title: 'বন্ধ জানালা', artist: 'শিরোনামহীন', seconds: 200);
      expect(matcher.matchRecording(ref, c).isExact, isFalse);
    });

    test('covers, karaoke and live versions are rejected (English and Bengali tags)', () {
      for (final t in ['Bondho Janala (Cover)', 'Bondho Janala - Karaoke', 'Bondho Janala (Live)', 'বন্ধ জানালা (কভার)',
          'Bondho Janala Guitar Cover', 'Bondho Janala (Instrumental)']) {
        final c = song(t, title: t, artist: 'Shironamhin', seconds: 300);
        expect(matcher.matchRecording(ref, c).isExact, isFalse, reason: t);
      }
    });

    test('a different uploader is not the original artist', () {
      for (final a in ['Shironamhin Fan', 'Random Uploader', 'Artcell']) {
        final c = song(a, title: 'Bondho Janala', artist: a, seconds: 300);
        expect(matcher.matchRecording(ref, c).isExact, isFalse, reason: a);
      }
    });

    test('a different Shironamhin song is not this one', () {
      final c = song('a5', title: 'Hashimukh', artist: 'Shironamhin', seconds: 300);
      expect(matcher.matchRecording(ref, c).isExact, isFalse);
    });

    test('Bengali-script reference finds the Latin-script upload', () {
      final bnRef = song('itunes:2', title: 'জাহাজী', artist: 'শিরোনামহীন', seconds: 280, sourceId: 'itunes');
      final c = song('a6', title: 'Jahaji', artist: 'Shironamhin', seconds: 281);
      expect(matcher.matchRecording(bnRef, c).isExact, isTrue, reason: '${matcher.matchRecording(bnRef, c)}');
    });
  });

  group('ISRC', () {
    final ref = withIsrc(song('itunes:3', title: 'Shape of You', artist: 'Ed Sheeran', seconds: 233), 'GBAHS1600463');

    test('same ISRC is the same recording', () {
      final c = withIsrc(song('b1', title: 'Shape Of You', artist: 'Ed Sheeran', seconds: 234), 'GB-AHS-16-00463');
      expect(matcher.matchRecording(ref, c).isExact, isTrue);
    });

    test('different ISRC is a different recording even with the same title', () {
      final c = withIsrc(song('b2', title: 'Shape of You', artist: 'Ed Sheeran', seconds: 233), 'GBAHS1700001');
      expect(matcher.matchRecording(ref, c).verdict, RecordingVerdict.differentIsrc);
    });

    test('a missing ISRC falls back to title/artist/duration rules', () {
      final c = song('b3', title: 'Shape of You', artist: 'Ed Sheeran', seconds: 233);
      expect(matcher.matchRecording(ref, c).isExact, isTrue);
    });
  });

  group('English dataset', () {
    Song r(String title, String artist, int s) => song('ref:$title', title: title, artist: artist, seconds: s);

    final cases = <({Song ref, Song cand, bool exact})>[
      (ref: r('Shape of You', 'Ed Sheeran', 233), cand: song('e1', title: 'Shape of You', artist: 'Ed Sheeran', seconds: 234), exact: true),
      (ref: r('Shape of You', 'Ed Sheeran', 233), cand: song('e2', title: 'Shape of You (Piano Cover)', artist: 'Ed Sheeran', seconds: 233), exact: false),
      (ref: r('Shape of You', 'Ed Sheeran', 233), cand: song('e3', title: 'Shape of You', artist: 'Ed Sheeran Fan', seconds: 233), exact: false),
      (ref: r('Love Story', 'Taylor Swift', 235), cand: song('e4', title: "Love Story (Taylor's Version)", artist: 'Taylor Swift', seconds: 235), exact: false),
      (ref: r('Yellow', 'Coldplay', 269), cand: song('e5', title: 'Yellow (Live in Buenos Aires)', artist: 'Coldplay', seconds: 290), exact: false),
      (ref: r('Hello', 'Adele', 295), cand: song('e6', title: 'Hello', artist: 'Adele', seconds: 295), exact: true),
      (ref: r('Believer', 'Imagine Dragons', 204), cand: song('e7', title: 'Believer (Nightcore)', artist: 'Imagine Dragons', seconds: 170), exact: false),
      (ref: r('Numb', 'Linkin Park', 185), cand: song('e8', title: 'Numb', artist: 'Linkin Park', seconds: 187), exact: true),
      (ref: r('Lose Yourself', 'Eminem', 326), cand: song('e9', title: 'Lose Yourself (Karaoke Version)', artist: 'Eminem', seconds: 326), exact: false),
      (ref: r('Blinding Lights', 'The Weeknd', 200), cand: song('e10', title: 'Blinding Lights (Sped Up)', artist: 'The Weeknd', seconds: 160), exact: false),
      (ref: r('Bohemian Rhapsody', 'Queen', 355), cand: song('e11', title: 'Bohemian Rhapsody - Remastered 2011', artist: 'Queen', seconds: 354), exact: true),
      (ref: r('Billie Jean', 'Michael Jackson', 294), cand: song('e12', title: 'Billie Jean', artist: 'Michael Jackson', seconds: 200), exact: false),
      // Valid titles that merely contain version words.
      (ref: r('Piano Man', 'Billy Joel', 337), cand: song('e13', title: 'Piano Man', artist: 'Billy Joel', seconds: 338), exact: true),
      (ref: r('Live and Let Die', 'Wings', 192), cand: song('e14', title: 'Live and Let Die', artist: 'Wings', seconds: 192), exact: true),
      (ref: r('Acoustic #3', 'The Goo Goo Dolls', 200), cand: song('e15', title: 'Acoustic #3', artist: 'The Goo Goo Dolls', seconds: 200), exact: true),
    ];
    for (final c in cases) {
      test('${c.ref.title} vs "${c.cand.title}" by ${c.cand.artist} → ${c.exact ? 'exact' : 'rejected'}', () {
        final m = matcher.matchRecording(c.ref, c.cand);
        expect(m.isExact, c.exact, reason: '$m');
      });
    }
  });
}
