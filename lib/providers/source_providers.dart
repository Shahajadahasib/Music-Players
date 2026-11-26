import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../playback/playback_ledger.dart';
import '../playback/stream_verifier.dart';
import '../models/song.dart';
import '../search/search_aggregator.dart';
import '../services/hive_storage_service.dart';
import '../search/provider_health.dart';
import '../sources/audius_source.dart';
import '../sources/freetouse_source.dart';
import '../sources/internet_archive_source.dart';
import '../sources/itunes_source.dart';
import '../sources/jamendo_source.dart';
import '../sources/music_source.dart';
import '../sources/musicbrainz_source.dart';
import '../sources/radio_source.dart';
import '../sources/youtube_source.dart';
import 'settings_provider.dart';

/// Every provider this *build* is allowed to use, in playback priority order.
/// Build flags (see [AppConfig]) decide availability; the user can then
/// disable any of them in Settings → Music sources.
final availableSourcesProvider = Provider<List<MusicSource>>((ref) {
  return orderByPriority([
    AudiusSource(),
    if (JamendoSource.isConfigured) JamendoSource(),
    if (FreeToUseSource.isConfigured) FreeToUseSource(),
    if (AppConfig.internetArchive) InternetArchiveSource(),
    if (AppConfig.itunesMetadata) ItunesSource(),
    if (AppConfig.musicBrainzEnabled) MusicBrainzSource(),
    if (YouTubeSource.isConfigured) YouTubeSource(),
  ], AppConfig.providerPriority);
});

/// Orders [sources] by the comma-separated [priority] ids; unlisted sources
/// keep their relative order after the listed ones. Only the order *within a
/// kind* matters to the aggregator (catalogue / full-track / external).
List<MusicSource> orderByPriority(List<MusicSource> sources, String priority) {
  final ids = [
    for (final p in priority.split(',')) if (p.trim().isNotEmpty) p.trim().toLowerCase(),
  ];
  int rank(MusicSource s) {
    final i = ids.indexOf(s.id);
    return i < 0 ? ids.length : i;
  }

  final indexed = [for (var i = 0; i < sources.length; i++) (i, sources[i])];
  indexed.sort((a, b) {
    final r = rank(a.$2).compareTo(rank(b.$2));
    return r != 0 ? r : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Live radio directory — a separate feature, never part of song search.
final radioSourceProvider = Provider<RadioSource?>((ref) {
  return RadioSource.isEnabled ? RadioSource() : null;
});

/// Shared provider health (circuit breaker), shown in Settings diagnostics.
final providerHealthProvider = Provider<ProviderHealth>((ref) => ProviderHealth());

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

/// Recordings that actually played (only these are labelled "Full track").
final playbackLedgerProvider = Provider<PlaybackLedger>((ref) => HivePlaybackLedger());

/// Checks a stream answers with audio before it is offered (pre-filter).
final streamVerifierProvider = Provider<StreamVerifier>((ref) {
  return HttpStreamVerifier(sourceById: (id) => ref.read(sourceByIdProvider(id)));
});

final searchAggregatorProvider = Provider<SearchAggregator>((ref) {
  return SearchAggregator(
    sources: () => ref.read(enabledSourcesProvider),
    memory: HiveMatchMemory(),
    verifier: ref.watch(streamVerifierProvider),
    health: ref.watch(providerHealthProvider),
  );
});

/// Lazily verifies one song's stream (search result badges). Cached by the
/// verifier, so re-renders do not repeat requests.
final streamCheckProvider = FutureProvider.autoDispose.family<StreamCheck, Song>((ref, song) {
  return ref.read(streamVerifierProvider).verify(song);
});

/// Looks up a source by id (for lazy stream resolution and attribution).
final sourceByIdProvider = Provider.family<MusicSource?, String>((ref, id) {
  for (final s in ref.watch(availableSourcesProvider)) {
    if (s.id == id) return s;
  }
  return null;
});
