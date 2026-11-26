import 'text_normalizer.dart';

/// Known spellings of the same artist across scripts and transliterations.
///
/// This is *identity* data (who is who), not search results: it lets a
/// Bengali-script query find Latin-script uploads and vice versa, and lets
/// the matcher accept "James" for "জেমস". Entries are kept conservative —
/// only names that unambiguously refer to the same act. Add more freely.
abstract final class ArtistAliases {
  static const List<List<String>> _groups = [
    // Bangladesh — bands
    ['Shironamhin', 'শিরোনামহীন', 'Shironamheen'],
    ['Warfaze', 'ওয়ারফেজ'],
    ['LRB', 'এলআরবি', 'Love Runs Blind', 'L.R.B.'],
    ['Miles', 'মাইলস'],
    ['Artcell', 'আর্টসেল'],
    ['Aurthohin', 'অর্থহীন', 'Arthohin'],
    ['Nemesis', 'নেমেসিস'],
    ['Cryptic Fate', 'ক্রিপটিক ফেইট'],
    ['Chirkutt', 'চিরকুট', 'Chirkut'],
    ['Meghdol', 'মেঘদল'],
    ['Avoidrafa', 'এভোয়েডরাফা'],
    ['Shunno', 'শূন্য', 'Shunyo'],
    ['Encore', 'এনকোর'],
    ['Indalo', 'ইন্দালো'],
    ['Kaaktaal', 'কাকতাল', 'Kaktal'],
    ['Black', 'ব্ল্যাক'],
    ['The Watson Brothers', 'দ্য ওয়াটসন ব্রাদার্স', 'Watson Brothers'],
    ['Souls', 'সোলস'],
    ['Feedback', 'ফিডব্যাক'],
    ['Renaissance', 'রেনেসাঁ'],
    // Bangladesh — solo
    ['Arnob', 'অর্ণব', 'Shayan Chowdhury Arnob'],
    ['Habib Wahid', 'হাবিব ওয়াহিদ'],
    ['Tahsan', 'তাহসান', 'Tahsan Rahman Khan'],
    ['James', 'জেমস', 'Nagar Baul James', 'Faruk Mahfuz Anam James'],
    ['Ayub Bachchu', 'আইয়ুব বাচ্চু', 'Ayub Bacchu'],
    ['Lalon', 'লালন', 'Lalon Shah', 'লালন শাহ', 'Lalon Fakir', 'লালন ফকির'],
    ['Minar Rahman', 'মিনার রহমান'],
    ['Kona', 'কনা'],
    ['Asif Akbar', 'আসিফ আকবর'],
    ['Bappa Mazumder', 'বাপ্পা মজুমদার', 'Bappa Majumder'],
    // West Bengal / India
    ['Anupam Roy', 'অনুপম রায়'],
    ['Rupam Islam', 'রূপম ইসলাম'],
    ['Fossils', 'ফসিলস'],
    ['Cactus', 'ক্যাকটাস'],
    ['Chandrabindoo', 'চন্দ্রবিন্দু', 'Chandrabindu'],
    ['Nachiketa', 'নচিকেতা', 'Nachiketa Chakraborty'],
    ['Srikanto Acharya', 'শ্রীকান্ত আচার্য', 'Srikanta Acharya'],
    ['Shreya Ghoshal', 'শ্রেয়া ঘোষাল'],
    ['Somlata', 'সোমলতা', 'Somlata Acharyya'],
    ['Iman Chakraborty', 'ইমন চক্রবর্তী', 'Iman Chakrabarty'],
    ['Kabir Suman', 'কবীর সুমন', 'Suman Chattopadhyay'],
    ['Hemanta Mukherjee', 'হেমন্ত মুখোপাধ্যায়', 'Hemant Kumar', 'Hemanta Mukhopadhyay'],
    ['Manna Dey', 'মান্না দে'],
    ['Kishore Kumar', 'কিশোর কুমার'],
    ['Arijit Singh', 'অরিজিৎ সিং'],
    // Composers / traditions (used as artist credits on many recordings)
    ['Rabindranath Tagore', 'রবীন্দ্রনাথ ঠাকুর'],
    ['Kazi Nazrul Islam', 'কাজী নজরুল ইসলাম'],
  ];

  static final Map<String, int> _index = () {
    final m = <String, int>{};
    for (var i = 0; i < _groups.length; i++) {
      for (final name in _groups[i]) {
        m[TextNormalizer.basic(name)] = i;
      }
    }
    return m;
  }();

  /// Group id for a (normalised) artist name, or null when unknown.
  static int? groupOf(String artist) => _index[TextNormalizer.basic(artist)];

  /// True when both names are known spellings of the same artist.
  static bool sameArtist(String a, String b) {
    final ga = groupOf(a);
    return ga != null && ga == groupOf(b);
  }

  /// Other spellings of [artist] (empty when unknown).
  static List<String> aliasesOf(String artist) {
    final g = groupOf(artist);
    if (g == null) return const [];
    final self = TextNormalizer.basic(artist);
    return [for (final n in _groups[g]) if (TextNormalizer.basic(n) != self) n];
  }

  /// Alternative queries in the other script(s): "শিরোনামহীন হাসনাহেনা" →
  /// "Shironamhin হাসনাহেনা" plus a fully transliterated variant. Used so a
  /// Bengali-script query can find Latin-script uploads (and vice versa).
  static List<String> queryVariants(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final out = <String>[q];
    final basic = TextNormalizer.basic(q);
    // Longest alias occurring in the query wins.
    String? hit;
    int? group;
    for (final entry in _index.entries) {
      if (entry.key.length < 3) continue;
      if (' $basic '.contains(' ${entry.key} ') && (hit == null || entry.key.length > hit.length)) {
        hit = entry.key;
        group = entry.value;
      }
    }
    if (hit != null && group != null) {
      final names = _groups[group];
      String swap(String name) => basic.replaceFirst(hit!, TextNormalizer.basic(name));
      if (TextNormalizer.containsBengali(hit)) {
        // Bengali artist → the canonical Latin name (how most catalogues
        // credit the artist).
        out.add(swap(names.first));
      } else {
        // Latin artist → another Latin spelling first ("LRB" → "Love Runs
        // Blind"; ignoring mere punctuation variants), then the Bengali one.
        final latin = names.where((n) =>
            !TextNormalizer.containsBengali(n) &&
            TextNormalizer.basic(n).replaceAll(' ', '') != hit!.replaceAll(' ', ''));
        if (latin.isNotEmpty) out.add(swap(latin.first));
        final bn = names.where(TextNormalizer.containsBengali);
        if (bn.isNotEmpty) out.add(swap(bn.first));
      }
    }
    if (TextNormalizer.containsBengali(q)) {
      final latin = TextNormalizer.basic(TextNormalizer.bengaliToLatin(out.last));
      if (!out.contains(latin)) out.add(latin);
    }
    // At most three requests per provider for one search.
    return out.toSet().take(3).toList();
  }
}
