import 'package:equatable/equatable.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../search/matched_track.dart';

/// Local-only playback quality metrics (never uploaded). Shown in
/// Settings → Diagnostics so startup time / rebuffering can be measured.
class PlaybackDiagnostics extends Equatable {
  const PlaybackDiagnostics({
    this.startupSamplesMs = const [],
    this.rebufferCount = 0,
    this.fallbackCount = 0,
    this.failedCount = 0,
  });

  final List<int> startupSamplesMs;
  final int rebufferCount;
  final int fallbackCount;
  final int failedCount;

  int? get medianStartupMs {
    if (startupSamplesMs.isEmpty) return null;
    final s = [...startupSamplesMs]..sort();
    return s[s.length ~/ 2];
  }

  PlaybackDiagnostics copyWith({
    List<int>? startupSamplesMs,
    int? rebufferCount,
    int? fallbackCount,
    int? failedCount,
  }) =>
      PlaybackDiagnostics(
        startupSamplesMs: startupSamplesMs ?? this.startupSamplesMs,
        rebufferCount: rebufferCount ?? this.rebufferCount,
        fallbackCount: fallbackCount ?? this.fallbackCount,
        failedCount: failedCount ?? this.failedCount,
      );

  @override
  List<Object?> get props =>
      [startupSamplesMs, rebufferCount, fallbackCount, failedCount];
}

class PlayerControllerState extends Equatable {
  const PlayerControllerState({
    this.currentSong,
    this.currentIndex,
    this.queue = const [],
    this.effectiveOrder = const [],
    this.isPlaying = false,
    this.isBuffering = false,
    this.isResolving = false,
    this.position = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.duration = Duration.zero,
    this.searchResult,
    this.searchResults = const [],
    this.isSearchLoading = false,
    this.isLibraryLoading = false,
    this.searchError,
    this.isShuffle = false,
    this.repeatMode = LoopMode.off,
    this.processingState = ProcessingState.idle,
    this.errorMessage,
    this.notice,
    this.favorites = const {},
    this.playlists = const {},
    this.volume = 1.0,
    this.sleepTimerEndsAt,
    this.sleepAtEndOfTrack = false,
    this.diagnostics = const PlaybackDiagnostics(),
  });

  final Song? currentSong;
  final int? currentIndex;

  /// Queue in playlist order (index-aligned with the player's sources).
  final List<Song> queue;

  /// Play order (differs from [queue] order while shuffle is on).
  final List<int> effectiveOrder;
  final bool isPlaying;
  final bool isBuffering;

  /// Looking up an authorised source for a catalogue-only track.
  final bool isResolving;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;
  final AggregatedSearchResult? searchResult;

  /// Flat list of playable search results (ranking order).
  final List<Song> searchResults;
  final bool isSearchLoading;
  final bool isLibraryLoading;
  final String? searchError;
  final bool isShuffle;
  final LoopMode repeatMode;
  final ProcessingState processingState;
  final String? errorMessage;

  /// Non-error, user-facing information ("Switched to another source").
  final String? notice;
  final Set<String> favorites;
  final Map<String, List<String>> playlists;
  final double volume;
  final DateTime? sleepTimerEndsAt;
  final bool sleepAtEndOfTrack;
  final PlaybackDiagnostics diagnostics;

  bool get sleepTimerActive => sleepTimerEndsAt != null || sleepAtEndOfTrack;

  /// Upcoming songs in play order.
  List<({int index, Song song})> get upNext {
    final idx = currentIndex;
    if (idx == null || queue.isEmpty) return const [];
    final order = effectiveOrder.length == queue.length
        ? effectiveOrder
        : List<int>.generate(queue.length, (i) => i);
    final pos = order.indexOf(idx);
    if (pos < 0) return const [];
    return [
      for (final i in order.skip(pos + 1))
        if (i < queue.length) (index: i, song: queue[i]),
    ];
  }

  PlayerControllerState copyWith({
    Song? currentSong,
    bool clearCurrentSong = false,
    int? currentIndex,
    List<Song>? queue,
    List<int>? effectiveOrder,
    bool? isPlaying,
    bool? isBuffering,
    bool? isResolving,
    Duration? position,
    Duration? bufferedPosition,
    Duration? duration,
    AggregatedSearchResult? searchResult,
    bool clearSearchResult = false,
    List<Song>? searchResults,
    bool? isSearchLoading,
    bool? isLibraryLoading,
    String? searchError,
    bool clearSearchError = false,
    bool? isShuffle,
    LoopMode? repeatMode,
    ProcessingState? processingState,
    String? errorMessage,
    bool clearError = false,
    String? notice,
    bool clearNotice = false,
    Set<String>? favorites,
    Map<String, List<String>>? playlists,
    double? volume,
    DateTime? sleepTimerEndsAt,
    bool clearSleepTimer = false,
    bool? sleepAtEndOfTrack,
    PlaybackDiagnostics? diagnostics,
  }) {
    return PlayerControllerState(
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
      currentIndex: clearCurrentSong ? null : (currentIndex ?? this.currentIndex),
      queue: queue ?? this.queue,
      effectiveOrder: effectiveOrder ?? this.effectiveOrder,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isResolving: isResolving ?? this.isResolving,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      duration: duration ?? this.duration,
      searchResult: clearSearchResult ? null : (searchResult ?? this.searchResult),
      searchResults: searchResults ?? this.searchResults,
      isSearchLoading: isSearchLoading ?? this.isSearchLoading,
      isLibraryLoading: isLibraryLoading ?? this.isLibraryLoading,
      searchError: clearSearchError ? null : (searchError ?? this.searchError),
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      processingState: processingState ?? this.processingState,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      notice: clearNotice ? null : (notice ?? this.notice),
      favorites: favorites ?? this.favorites,
      playlists: playlists ?? this.playlists,
      volume: volume ?? this.volume,
      sleepTimerEndsAt:
          clearSleepTimer ? null : (sleepTimerEndsAt ?? this.sleepTimerEndsAt),
      sleepAtEndOfTrack:
          clearSleepTimer ? false : (sleepAtEndOfTrack ?? this.sleepAtEndOfTrack),
      diagnostics: diagnostics ?? this.diagnostics,
    );
  }

  @override
  List<Object?> get props => [
        currentSong,
        currentIndex,
        queue,
        effectiveOrder,
        isPlaying,
        isBuffering,
        isResolving,
        position,
        bufferedPosition,
        duration,
        searchResult,
        searchResults,
        isSearchLoading,
        isLibraryLoading,
        searchError,
        isShuffle,
        repeatMode,
        processingState,
        errorMessage,
        notice,
        favorites,
        playlists,
        volume,
        sleepTimerEndsAt,
        sleepAtEndOfTrack,
        diagnostics,
      ];
}
