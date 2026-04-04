import 'package:equatable/equatable.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

class PlayerControllerState extends Equatable {
  const PlayerControllerState({
    this.currentSong,
    this.queue = const [],
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.searchResults = const [],
    this.isSearchLoading = false,
    this.isLibraryLoading = false,
    this.searchError,
    this.isShuffle = false,
    this.repeatMode = LoopMode.off,
    this.processingState = ProcessingState.idle,
    this.errorMessage,
    this.favorites = const {},
    this.playlists = const {},
  });

  final Song? currentSong;
  final List<Song> queue;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final List<Song> searchResults;
  final bool isSearchLoading;
  /// True while fetching Audius trending to fill an empty on-disk library.
  final bool isLibraryLoading;
  final String? searchError;
  final bool isShuffle;
  final LoopMode repeatMode;
  final ProcessingState processingState;
  final String? errorMessage;
  final Set<String> favorites;
  final Map<String, List<String>> playlists;

  PlayerControllerState copyWith({
    Song? currentSong,
    bool clearCurrentSong = false,
    List<Song>? queue,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
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
    Set<String>? favorites,
    Map<String, List<String>>? playlists,
  }) {
    return PlayerControllerState(
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
      queue: queue ?? this.queue,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      searchResults: searchResults ?? this.searchResults,
      isSearchLoading: isSearchLoading ?? this.isSearchLoading,
      isLibraryLoading: isLibraryLoading ?? this.isLibraryLoading,
      searchError: clearSearchError ? null : (searchError ?? this.searchError),
      isShuffle: isShuffle ?? this.isShuffle,
      repeatMode: repeatMode ?? this.repeatMode,
      processingState: processingState ?? this.processingState,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      favorites: favorites ?? this.favorites,
      playlists: playlists ?? this.playlists,
    );
  }

  @override
  List<Object?> get props => [
        currentSong,
        queue,
        isPlaying,
        isBuffering,
        position,
        duration,
        searchResults,
        isSearchLoading,
        isLibraryLoading,
        searchError,
        isShuffle,
        repeatMode,
        processingState,
        errorMessage,
        favorites,
        playlists,
      ];
}
