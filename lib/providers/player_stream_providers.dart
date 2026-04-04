import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song.dart';
import 'player_provider.dart';

final playerPositionProvider = Provider<Duration>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.position));
});

final playerDurationProvider = Provider<Duration>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.duration));
});

final currentSongProvider = Provider<Song?>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.currentSong));
});

final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.isPlaying));
});

final isBufferingProvider = Provider<bool>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.isBuffering));
});

final favoritesProvider = Provider<Set<String>>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.favorites));
});

final queueProvider = Provider<List<Song>>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.queue));
});

final playerErrorMessageProvider = Provider<String?>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.errorMessage));
});

final searchResultsProvider = Provider<List<Song>>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.searchResults));
});

final isSearchLoadingProvider = Provider<bool>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.isSearchLoading));
});

final searchErrorProvider = Provider<String?>((ref) {
  return ref.watch(playerControllerProvider.select((state) => state.searchError));
});
