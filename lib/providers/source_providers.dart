import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../search/search_aggregator.dart';
import '../services/hive_storage_service.dart';
import '../sources/audius_source.dart';
import '../sources/internet_archive_source.dart';
import '../sources/itunes_source.dart';
import '../sources/jamendo_source.dart';
import '../sources/music_source.dart';
import 'settings_provider.dart';

/// Every provider this *build* is allowed to use, in playback priority order.
/// Build flags (see [AppConfig]) decide availability; the user can then
/// disable any of them in Settings → Music sources.
final availableSourcesProvider = Provider<List<MusicSource>>((ref) {
  return [
    AudiusSource(),
    if (JamendoSource.isConfigured) JamendoSource(),
    if (AppConfig.internetArchive) InternetArchiveSource(),
    if (AppConfig.itunesMetadata) ItunesSource(),
  ];
});

final enabledSourcesProvider = Provider<List<MusicSource>>((ref) {
  final disabled = ref.watch(settingsProvider.select((s) => s.disabledSources));
  return [
    for (final s in ref.watch(availableSourcesProvider))
      if (!disabled.contains(s.id)) s,
  ];
});

class HiveMatchMemory implements MatchMemory {
  @override
  String? lookup(String songKey) {
    try {
      return HiveStorageService.lookupMatch(songKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> remember(String songKey, String songId) async {
    try {
      await HiveStorageService.rememberMatch(songKey, songId);
    } catch (_) {}
  }
}

final searchAggregatorProvider = Provider<SearchAggregator>((ref) {
  return SearchAggregator(
    sources: () => ref.read(enabledSourcesProvider),
    memory: HiveMatchMemory(),
  );
});

/// Looks up a source by id (for lazy stream resolution and attribution).
final sourceByIdProvider = Provider.family<MusicSource?, String>((ref, id) {
  for (final s in ref.watch(availableSourcesProvider)) {
    if (s.id == id) return s;
  }
  return null;
});
