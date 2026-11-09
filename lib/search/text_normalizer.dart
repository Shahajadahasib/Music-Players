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

  /// Tags that identify a *different recording* than the original.
  static const Map<String, String> _versionKeywords = {
    'live': 'live',
    'remix': 'remix',
    'rmx': 'remix',
    'acoustic': 'acoustic',
    'instrumental': 'instrumental',
    'karaoke': 'karaoke',
    'cover': 'cover',
    'tribute': 'cover',
    'sped up': 'sped',
    'speed up': 'sped',
    'nightcore': 'sped',
    'slowed': 'slowed',
    'reverb': 'slowed',
    'demo': 'demo',
    'edit': 'edit',
    'extended': 'extended',
    'unplugged': 'acoustic',
    'orchestral': 'orchestral',
    'piano version': 'piano',
    'lofi': 'lofi',
    'lo-fi': 'lofi',
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
  static final RegExp _nonWord = RegExp(r"[^a-z0-9\s]");
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

  /// Version tags (live, remix, …) found anywhere in [title].
  static Set<String> versionTags(String title) {
    final lower = foldDiacritics(title.toLowerCase());
    final tags = <String>{};
    for (final entry in _versionKeywords.entries) {
      if (RegExp('\\b${RegExp.escape(entry.key)}\\b').hasMatch(lower)) {
        tags.add(entry.value);
      }
    }
    // "Radio edit" is a noise qualifier, not a different recording.
    if (lower.contains('radio edit')) tags.remove('edit');
    return tags;
  }

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
}
