/// Normalises music metadata so the same song from different providers can be
/// recognised even when titles/artists are written differently, e.g.
///
///   "Señorita (feat. Camila Cabello) - Remastered 2019"
///   "senorita"  + version tags {remaster}
///
/// Version tags that change *what recording it is* (live, remix, acoustic,
/// instrumental, karaoke, cover, sped up…) are extracted separately so the
/// matcher can refuse to treat a karaoke cover as the original.
abstract final class TextNormalizer {
  static const Map<String, String> _diacritics = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
    'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y',
    'ÿ': 'y', 'ß': 'ss', 'œ': 'oe', 'ł': 'l', 'ś': 's', 'ż': 'z', 'ź': 'z',
    'č': 'c', 'š': 's', 'ž': 'z', 'ř': 'r', 'ğ': 'g', 'ı': 'i', 'ş': 's',
  };

  /// Words that identify a *different recording* than the original, mapped
  /// to a canonical tag. Matching is whole-word, so "Alive" is not "live".
  static const Map<String, String> _versionKeywords = {
    // performances / mixes
    'live': 'live',
    'remix': 'remix',
    'rmx': 'remix',
    'rework': 'remix',
    'bootleg': 'remix',
    'mashup': 'remix',
    'vip mix': 'remix',
    'flip': 'remix',
    'acoustic': 'acoustic',
    'unplugged': 'acoustic',
    'instrumental': 'instrumental',
    'karaoke': 'karaoke',
    'demo': 'demo',
    'edit': 'edit',
    'extended': 'extended',
    // covers / tributes
    'cover': 'cover',
    'covered by': 'cover',
    'tribute': 'cover',
    'in the style of': 'cover',
    'originally performed by': 'cover',
    'made famous by': 'cover',
    'remake': 'cover',
    // re-recordings by the same artist are different recordings
    're-recorded': 'rerecord',
    'rerecorded': 'rerecord',
    're-recording': 'rerecord',
    "taylor's version": 'rerecord',
    'taylors version': 'rerecord',
    // instrument arrangements
    'violin': 'violin',
    'viola': 'violin',
    'cello': 'cello',
    'piano': 'piano',
    'guitar': 'guitar',
    'ukulele': 'guitar',
    'flute': 'flute',
    'saxophone': 'sax',
    'sax': 'sax',
    'harp': 'harp',
    'orchestral': 'orchestral',
    'orchestra': 'orchestral',
    'string quartet': 'orchestral',
    'symphonic': 'orchestral',
    'music box': 'musicbox',
    'lullaby': 'lullaby',
    '8 bit': '8bit',
    '8-bit': '8bit',
    'a cappella': 'acapella',
    'acapella': 'acapella',
    // tempo / effect edits
    'sped up': 'sped',
    'speed up': 'sped',
    'nightcore': 'sped',
    'slowed': 'slowed',
    'reverb': 'slowed',
    'bass boosted': 'bassboost',
    '8d': '8d',
    'lofi': 'lofi',
    'lo-fi': 'lofi',
    'lo fi': 'lofi',
    // Bengali spellings of version words
    'কভার': 'cover',
    'লাইভ': 'live',
    'রিমিক্স': 'remix',
    'কারাওকে': 'karaoke',
    'ইন্সট্রুমেন্টাল': 'instrumental',
  };

  /// Qualifiers that do NOT change the recording and are simply dropped.
  static final RegExp _noiseQualifier = RegExp(
    r'\b(remaster(ed)?( \d{4})?|\d{4} remaster(ed)?|official( music)?( video| audio| lyric video)?|'
    r'lyrics?( video)?|audio|video|hd|hq|explicit|clean|radio edit|single version|album version|'
    r'original mix|mono|stereo|bonus track|deluxe( edition)?)\b',
  );

  // "feat." anywhere; "with" only inside brackets ("Stay With Me" must survive).
  static final RegExp _feat = RegExp(
    r'\s*(\(|\[)\s*(feat\.?|ft\.?|featuring|with)\s+[^\)\]]*(\)|\])'
    r'|\s+\b(feat\.?|ft\.?|featuring)\s+[^\(\[\-]*',
  );
  static final RegExp _brackets = RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]');
  // Unicode-aware: keeps letters, combining marks (Bengali vowel signs) and
  // digits of every script. The old ASCII-only pattern erased Bengali text.
  static final RegExp _nonWord = RegExp(r"[^\p{L}\p{M}\p{N}\s]", unicode: true);
  static final RegExp _nonWordRun = RegExp(r"[^\p{L}\p{M}\p{N}]+", unicode: true);
  static final RegExp _bengali = RegExp(r"[\u0980-\u09FF]");
  static final RegExp _spaces = RegExp(r'\s+');

  static String foldDiacritics(String input) {
    final b = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      b.write(_diacritics[ch] ?? ch);
    }
    return b.toString();
  }

  /// Lower-case, fold accents, `&` → `and`, strip punctuation.
  static String basic(String input) {
    var s = foldDiacritics(input.toLowerCase());
    s = s.replaceAll('&', ' and ').replaceAll('’', "'").replaceAll("'", '');
    s = s.replaceAll(_nonWord, ' ');
    return s.replaceAll(_spaces, ' ').trim();
  }

  /// Version tags (live, remix, violin, …) found anywhere in [title].
  static Set<String> versionTags(String title) {
    final lower = ' ${foldDiacritics(title.toLowerCase()).replaceAll(_nonWordRun, ' ')} ';
    final tags = <String>{};
    for (final entry in _versionKeywords.entries) {
      final key = entry.key.replaceAll(_nonWordRun, ' ');
      if (lower.contains(' $key ')) tags.add(entry.value);
    }
    // "Radio edit" / "single edit" are the same recording, trimmed.
    if (lower.contains(' radio edit ') || lower.contains(' single edit ')) {
      tags.remove('edit');
    }
    return tags;
  }

  /// Version tags present in [candidateTitle] that the [referenceTitle] does
  /// not have and the user's [query] did not ask for. A non-empty result means
  /// the candidate is a *different recording* (cover, remix, live, …).
  static Set<String> unrequestedVersions(
    String candidateTitle,
    String referenceTitle, {
    String query = '',
  }) =>
      versionTags(candidateTitle)
          .difference(versionTags(referenceTitle))
          .difference(versionTags(query));

  /// Canonical comparable title with featured artists, bracketed qualifiers
  /// and " - Remastered 2011" style suffixes removed.
  static String title(String input) {
    var s = foldDiacritics(input.toLowerCase());
    s = s.replaceAll(_feat, ' ');
    // Drop bracketed parts entirely (version info is captured by versionTags).
    s = s.replaceAll(_brackets, ' ');
    // "Song - Remastered 2011" / "Song - Live at Wembley"
    final dash = s.indexOf(' - ');
    if (dash > 0) {
      final tail = s.substring(dash + 3);
      if (_noiseQualifier.hasMatch(tail) || versionTags(tail).isNotEmpty) {
        s = s.substring(0, dash);
      }
    }
    s = s.replaceAll(_noiseQualifier, ' ');
    final out = basic(s);
    return out.isEmpty ? basic(input) : out;
  }

  /// Individual artist names, normalised: "A feat. B & C" → {a, b, c}.
  static Set<String> artists(String input) {
    final s = foldDiacritics(input.toLowerCase())
        .replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring|with|vs\.?|x)\b'), ',')
        .replaceAll(RegExp(r'[&/;+]'), ',')
        .replaceAll(RegExp(r'\band\b'), ',');
    return s
        .split(',')
        .map(basic)
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  static Set<String> tokens(String normalized) =>
      normalized.split(' ').where((t) => t.isNotEmpty).toSet();

  /// Stable key for "this song by this artist" (used for match memory).
  static String songKey(String title, String artist) {
    final a = artists(artist).toList()..sort();
    return '${TextNormalizer.title(title)}|${a.isEmpty ? '' : a.first}';
  }

  // ── Bengali script & transliteration ────────────────────────────────────

  /// True when [input] contains Bengali script.
  static bool containsBengali(String input) => _bengali.hasMatch(input);

  static const Map<String, String> _bnVowels = {
    'অ': 'a', 'আ': 'a', 'ই': 'i', 'ঈ': 'i', 'উ': 'u', 'ঊ': 'u', 'ঋ': 'ri',
    'এ': 'e', 'ঐ': 'oi', 'ও': 'o', 'ঔ': 'ou',
  };
  static const Map<String, String> _bnSigns = {
    'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u', 'ৃ': 'ri', 'ে': 'e',
    'ৈ': 'oi', 'ো': 'o', 'ৌ': 'ou',
  };
  static const Map<String, String> _bnConsonants = {
    'ক': 'k', 'খ': 'kh', 'গ': 'g', 'ঘ': 'gh', 'ঙ': 'ng', 'চ': 'ch', 'ছ': 'chh',
    'জ': 'j', 'ঝ': 'jh', 'ঞ': 'n', 'ট': 't', 'ঠ': 'th', 'ড': 'd', 'ঢ': 'dh',
    'ণ': 'n', 'ত': 't', 'থ': 'th', 'দ': 'd', 'ধ': 'dh', 'ন': 'n', 'প': 'p',
    'ফ': 'ph', 'ব': 'b', 'ভ': 'bh', 'ম': 'm', 'য': 'j', 'র': 'r', 'ল': 'l',
    'শ': 'sh', 'ষ': 'sh', 'স': 's', 'হ': 'h',
    '\u09DC': 'r', '\u09DD': 'rh', '\u09DF': 'y', // ড় ঢ় য় (precomposed)
  };
  static const Map<String, String> _bnOther = {
    'ৎ': 't', 'ং': 'ng', 'ঃ': 'h', 'ঁ': '', '্': '', '়': '',
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4', '৫': '5', '৬': '6',
    '৭': '7', '৮': '8', '৯': '9',
  };

  /// Readable Latin transliteration of Bengali script (other characters are
  /// kept). Consonants carry the inherent vowel unless a vowel sign or
  /// hasanta follows or they end a word. It is approximate by design: it is
  /// used to *compare* spellings, never to claim two recordings are the same.
  static String bengaliToLatin(String input) {
    if (!containsBengali(input)) return input;
    // Normalise precomposed nukta letters (ড় ঢ় য়) to single keys.
    final text = input
        .replaceAll('\u09A1\u09BC', '\u09DC')
        .replaceAll('\u09A2\u09BC', '\u09DD')
        .replaceAll('\u09AF\u09BC', '\u09DF');
    final chars = text.runes.map(String.fromCharCode).toList();
    final out = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final next = i + 1 < chars.length ? chars[i + 1] : '';
      final cons = _bnConsonants[c];
      if (cons != null) {
        final prev = i > 0 ? chars[i - 1] : '';
        // য-ফলা (consonant + ্ + য) is pronounced like "y".
        out.write(c == 'য' && prev == '্' ? 'y' : cons);
        final endOfWord = next.isEmpty || !_isBengaliLetter(next);
        if (!_bnSigns.containsKey(next) && next != '্' && !endOfWord &&
            !_bnOther.containsKey(next)) {
          out.write('a'); // inherent vowel
        }
        continue;
      }
      out.write(_bnVowels[c] ?? _bnSigns[c] ?? _bnOther[c] ?? c);
    }
    return out.toString();
  }

  static bool _isBengaliLetter(String c) => _bnConsonants.containsKey(c) ||
      _bnVowels.containsKey(c) || _bnSigns.containsKey(c) || c == '্' || c == 'ং' || c == 'ঁ' || c == 'ৎ';

  /// Spelling-tolerant key for comparing transliterations, e.g.
  /// "Hashnahena" = "Hasnahena" = "হাসনাহেনা", "Kolorob" = "কলরব",
  /// "Bachchu" = "Bacchu". Vowels a/o (the Bengali inherent vowel), y/w and
  /// aspiration "h" after consonants are ignored; doubled letters collapse.
  /// Equal keys mean "same spelling family", NOT "same recording".
  static String phoneticKey(String input) {
    var s = basic(bengaliToLatin(input));
    s = s
        .replaceAllMapped(RegExp(r'([bcdgjkpstr])h'), (m) => m.group(1)!)
        .replaceAll('ee', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('ph', 'p')
        .replaceAll('f', 'p')
        .replaceAll('v', 'b')
        .replaceAll('z', 'j')
        .replaceAll('q', 'k')
        .replaceAll('x', 'ks')
        .replaceAll(RegExp(r'[aoyw]'), '');
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
