import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

import '../models/song.dart';
import '../services/audio_service.dart';
import '../services/hive_storage_service.dart';
import '../services/audius_service.dart';
import 'player_controller_state.dart';

/// Coordinates playback and search via **Audius** (discovery API).
///
/// **Core state** (see [PlayerControllerState]): [PlayerControllerState.currentSong],
/// [PlayerControllerState.isPlaying], [PlayerControllerState.position],
/// [PlayerControllerState.duration], [PlayerControllerState.searchResults].
///
/// **Core API**
/// - [searchSongs] → [AudiusService]
/// - [playSong], [pause], [resume]
///
/// Uses a single [AudioService.instance] / [AudioPlayer] — never creates a
/// second player. Additional methods (queue, favorites, playlists) support the
/// existing UI and persistence. Search uses [_searchRequestId] so overlapping
/// calls cannot overwrite [PlayerControllerState.searchResults] out of order.
class PlayerController extends StateNotifier<PlayerControllerState> {
  PlayerController() : super(const PlayerControllerState()) {
    _initialize();
  }

  final AudioService _audioService = AudioService.instance;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _streamsBound = false;
  // Tracks the last time position was written to Hive so we can throttle
  // writes to at most once every 5 seconds while the player is active.
  DateTime? _lastPositionSavedAt;
  // True while setAudioSource + play() is in flight. Position-stream events
  // during this window contain just_audio's pre-seek value of 0 and must NOT
  // overwrite state.position (which holds the correct saved offset) or be
  // written to Hive.
  bool _isSettingAudioSource = false;
  // Started when the player enters a buffering/loading state. Fires after
  // 30 seconds of continuous stall to notify the user and offer a retry.
  Timer? _bufferingTimeoutTimer;
  int _searchRequestId = 0;
  /// Last query that finished successfully (including empty results). Used to
  /// skip redundant network calls when the UI requests the same search again.
  String? _lastCompletedSearchQuery;

  AudioPlayer get _player => _audioService.player;

  Future<void> _initialize() async {
    try {
      await _audioService.initialize();
      _hydrateLibraryState();
      _bindPlayerStreams();
      _bindAudioSessionInterruptions();
      await _restoreLastPlayback();
      await _loadTrendingLibraryIfEmpty();
    } catch (error) {
      _setError('Failed to initialize audio engine: $error');
    }
  }

  /// First launch (or after demo migration): fill Hive from Audius trending.
  Future<void> _loadTrendingLibraryIfEmpty() async {
    if (HiveStorageService.getAllSongs().isNotEmpty) return;

    state = state.copyWith(isLibraryLoading: true);
    try {
      final outcome = await AudiusService.instance.trendingTracks(limit: 40);
      if (outcome.errorMessage != null || outcome.tracks.isEmpty) {
        return;
      }
      await HiveStorageService.saveSongs(outcome.tracks);
      _lastCompletedSearchQuery = 'popular';
      state = state.copyWith(
        queue: outcome.tracks,
        searchResults: outcome.tracks,
        clearSearchError: true,
        searchError: null,
      );
    } catch (_) {
      // Offline / failure: leave library empty; user can search.
    } finally {
      state = state.copyWith(isLibraryLoading: false);
    }
  }

  /// Pauses automatically on phone calls, other apps stealing audio focus, etc.
  void _bindAudioSessionInterruptions() {
    AudioSession.instance.then((session) {
      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            // Another app (phone, navigation, etc.) has taken audio focus.
            if (state.isPlaying) {
              _player.pause();
            }
          }
        }),
      );
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          // Headphones unplugged — pause to avoid blasting audio through speaker.
          if (state.isPlaying) {
            _player.pause();
          }
        }),
      );
    });
  }

  /// Pre-loads the last played song into the audio engine at the saved
  /// position WITHOUT starting playback.
  ///
  /// Using [preload: false] keeps app start instant — no network request is
  /// made until the user explicitly presses play. The [initialPosition] is
  /// stored by just_audio and applied when play() is eventually called.
  ///
  /// Silently no-ops when there is no previous session data (fresh install or
  /// cleared storage) so there is no risk of a crash.
  Future<void> _restoreLastPlayback() async {
    final song = state.currentSong;
    if (song == null) return;

    final songs = state.queue.isNotEmpty ? state.queue : [song];
    final idx = songs.indexWhere((s) => s.id == song.id);

    _isSettingAudioSource = true;
    _lastPositionSavedAt = DateTime.now();

    try {
      await _audioService.setQueue(
        songs: songs,
        initialIndex: idx < 0 ? 0 : idx,
        initialPosition: state.position,
        preload: false,
      );
      // Do NOT call _player.play() — the user must press play explicitly.
    } catch (_) {
      // Non-fatal: startup should never fail because of a playback restore
      // error. The user can still tap any song to begin playback normally.
    } finally {
      _isSettingAudioSource = false;
    }
  }

  void _hydrateLibraryState() {
    final userData = HiveStorageService.getUserData();
    final playlistsMap = HiveStorageService.getPlaylistsSongMap();
    final lastSong = userData.lastPlayedSong == null
        ? null
        : HiveStorageService.getSongById(userData.lastPlayedSong!);

    // Restore the full song library as the default queue so that next/previous
    // navigation works immediately after a restart without requiring the user
    // to tap from the list first.
    final restoredQueue = HiveStorageService.getAllSongs();

    state = state.copyWith(
      currentSong: lastSong,
      queue: restoredQueue,
      favorites: userData.favorites.toSet(),
      playlists: playlistsMap,
      position: userData.lastPosition,
    );
  }

  void _bindPlayerStreams() {
    if (_streamsBound) {
      return;
    }
    _streamsBound = true;

    _subscriptions.add(
      _audioService.durationStream.listen((totalDuration) {
        if (totalDuration == null) {
          return;
        }
        state = state.copyWith(duration: totalDuration);
      }),
    );

    _subscriptions.add(
      _audioService.positionStream.listen((position) {
        // Suppress all position events while the audio source is being loaded.
        // just_audio fires position=0 before seeking to initialPosition, which
        // would override the correct saved position in both state and Hive.
        if (_isSettingAudioSource) return;

        // Only cap position to duration when duration is known; capping to
        // Duration.zero (the value right after playPlaylist resets it) would
        // incorrectly lock position at 0.
        final safePosition =
            state.duration > Duration.zero && position > state.duration
                ? state.duration
                : position;
        state = state.copyWith(position: safePosition);

        // Throttle: persist position to Hive at most once every 5 seconds
        // while the player is active. This ensures minimal progress is lost
        // if the app is killed without an explicit pause or seek.
        if (state.isPlaying) {
          final now = DateTime.now();
          if (_lastPositionSavedAt == null ||
              now.difference(_lastPositionSavedAt!) >=
                  const Duration(seconds: 5)) {
            _lastPositionSavedAt = now;
            _persistCurrentPlayback();
          }
        }
      }),
    );

    _subscriptions.add(
      _audioService.playerStateStream.listen((playerState) {
        final isBuffering =
            playerState.processingState == ProcessingState.buffering ||
                playerState.processingState == ProcessingState.loading;

        state = state.copyWith(
          isPlaying: playerState.playing,
          processingState: playerState.processingState,
          isBuffering: isBuffering,
        );

        // Start a 30-second stall timer when the player is buffering. If the
        // audio hasn't resumed by then, surface an error so the user can retry
        // rather than staring at a frozen UI indefinitely.
        if (isBuffering && !_isSettingAudioSource) {
          _bufferingTimeoutTimer ??= Timer(const Duration(seconds: 30), () {
            _bufferingTimeoutTimer = null;
            if (state.isBuffering) {
              _setError(
                'Playback stalled. Check your connection and tap Retry.',
              );
            }
          });
        } else {
          _bufferingTimeoutTimer?.cancel();
          _bufferingTimeoutTimer = null;
        }
      }),
    );

    _subscriptions.add(
      _player.processingStateStream.listen((processingState) async {
        if (processingState == ProcessingState.completed) {
          await _handleTrackCompletion();
        }
      }),
    );

    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        if (index == null || index < 0 || index >= state.queue.length) {
          return;
        }
        final currentSong = state.queue[index];

        final sourceDuration = _player.sequenceState.currentSource?.duration;
        state = state.copyWith(
          currentSong: currentSong,
          duration: sourceDuration ?? state.duration,
          position: Duration.zero,
        );
        _persistLastPlayback(currentSong.id, Duration.zero);
      }),
    );

    _subscriptions.add(
      _player.shuffleModeEnabledStream.listen((isEnabled) {
        state = state.copyWith(isShuffle: isEnabled);
      }),
    );

    _subscriptions.add(
      _player.loopModeStream.listen((mode) {
        state = state.copyWith(repeatMode: mode);
      }),
    );
  }

  Future<List<Song>> searchSongs(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      _lastCompletedSearchQuery = null;
      state = state.copyWith(
        searchResults: const [],
        isSearchLoading: false,
        clearSearchError: true,
      );
      return const [];
    }

    if (normalizedQuery == _lastCompletedSearchQuery &&
        state.searchError == null &&
        !state.isSearchLoading) {
      return state.searchResults;
    }

    final requestId = ++_searchRequestId;

    state = state.copyWith(
      isSearchLoading: true,
      clearSearchError: true,
    );

    try {
      final outcome = await AudiusService.instance.searchTracks(normalizedQuery);
      if (requestId != _searchRequestId) return state.searchResults;

      if (outcome.errorMessage == null) {
        _lastCompletedSearchQuery = normalizedQuery;
      }

      state = state.copyWith(
        searchResults: outcome.tracks,
        isSearchLoading: false,
        clearSearchError: outcome.errorMessage == null,
        searchError: outcome.errorMessage,
      );
      return outcome.tracks;
    } catch (error) {
      if (requestId != _searchRequestId) return state.searchResults;
      state = state.copyWith(
        searchResults: const [],
        isSearchLoading: false,
        searchError: 'Search failed. Please try again.',
      );
      return const [];
    }
  }

  Future<void> playSong(Song song) async {
    // Already playing this exact song — nothing to do.
    if (state.currentSong?.id == song.id && state.isPlaying) return;

    // Same song but paused — resume from current position, never restart.
    if (state.currentSong?.id == song.id) {
      await resume();
      return;
    }

    await _persistSong(song);
    final existingIndex = state.queue.indexWhere((item) => item.id == song.id);
    if (existingIndex == -1) {
      await playPlaylist([song], startIndex: 0);
      return;
    }

    await _playFromQueueIndex(existingIndex);
  }

  Future<void> playPlaylist(
    List<Song> songs, {
    int startIndex = 0,
    Duration startPosition = Duration.zero,
  }) async {
    if (songs.isEmpty) {
      _setError('Cannot play an empty playlist.');
      return;
    }

    state = state.copyWith(
      queue: songs,
      currentSong: songs[startIndex.clamp(0, songs.length - 1)],
      position: startPosition,
      duration: Duration.zero,
      clearError: true,
    );

    // Block position-stream writes until the audio source is fully loaded and
    // seeked to startPosition. Resets the throttle timestamp so that the
    // first real position event after loading does not carry a stale time.
    _isSettingAudioSource = true;
    _lastPositionSavedAt = DateTime.now();

    try {
      await HiveStorageService.saveSongs(songs);
      await _audioService.setQueue(
        songs: songs,
        initialIndex: startIndex,
        initialPosition: startPosition,
        preload: true,
      );
      // setQueue has finished: the audio source is loaded and seeked to
      // startPosition. Re-enable position tracking NOW so the slider starts
      // updating the instant play() fires — not after the Hive write below.
      _isSettingAudioSource = false;
      await _player.play();
      final currentSong = songs[startIndex.clamp(0, songs.length - 1)];
      await _persistLastPlayback(currentSong.id, startPosition);
    } on AudioUrlException catch (error) {
      _isSettingAudioSource = false;
      _setError(error.message);
    } catch (error) {
      _isSettingAudioSource = false;
      final msg = error.toString().toLowerCase();
      if (msg.contains('socket') ||
          msg.contains('connection') ||
          msg.contains('network') ||
          msg.contains('host') ||
          msg.contains('unreachable')) {
        _setError('Network error. Check your connection and tap Retry.');
      } else {
        _setError('Playback failed. Tap Retry to try again.');
      }
    }
  }

  Future<void> pause() async {
    try {
      await _audioService.pause();
      await _persistCurrentPlayback();
    } catch (error) {
      _setError('Unable to pause audio: $error');
    }
  }

  Future<void> resume() async {
    if (_player.audioSource == null) {
      // Audio source is not loaded — this happens after a cold start when
      // _hydrateLibraryState restored currentSong/position from Hive but
      // the audio engine is still idle.
      final currentSong = state.currentSong;
      if (currentSong == null) return;

      // Use the in-memory queue if available, otherwise fall back to a
      // single-song queue so playback is never stuck.
      final songs =
          state.queue.isNotEmpty ? state.queue : [currentSong];
      final idx = songs.indexWhere((s) => s.id == currentSong.id);

      // Seek to the persisted position so the user resumes exactly where
      // they left off rather than restarting from the beginning.
      await playPlaylist(
        songs,
        startIndex: idx < 0 ? 0 : idx,
        startPosition: state.position,
      );
      return;
    }

    try {
      await _audioService.resume();
    } catch (error) {
      _setError('Unable to resume audio: $error');
    }
  }

  Future<void> seek(Duration position) async {
    final boundedPosition = position < Duration.zero
        ? Duration.zero
        : (position > state.duration ? state.duration : position);

    try {
      await _audioService.seek(boundedPosition);
      state = state.copyWith(position: boundedPosition);
      await _persistCurrentPlayback();
    } catch (error) {
      _setError('Unable to seek audio: $error');
    }
  }

  Future<void> next() async {
    try {
      if (_player.hasNext) {
        await _player.seekToNext();
        if (!_player.playing) {
          await _player.play();
        }
      }
    } catch (error) {
      _setError('Unable to play next track: $error');
    }
  }

  Future<void> previous() async {
    try {
      if (_player.hasPrevious) {
        await _player.seekToPrevious();
      } else {
        await _player.seek(Duration.zero);
      }
      if (!_player.playing) {
        await _player.play();
      }
    } catch (error) {
      _setError('Unable to play previous track: $error');
    }
  }

  Future<void> toggleShuffle() async {
    final nextValue = !state.isShuffle;
    try {
      await _player.setShuffleModeEnabled(nextValue);
      if (nextValue && state.queue.length > 1) {
        await _player.shuffle();
      }
      state = state.copyWith(isShuffle: nextValue);
    } catch (error) {
      _setError('Unable to toggle shuffle: $error');
    }
  }

  Future<void> toggleRepeat() async {
    final nextMode = switch (state.repeatMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };

    try {
      await _player.setLoopMode(nextMode);
      state = state.copyWith(repeatMode: nextMode);
    } catch (error) {
      _setError('Unable to toggle repeat: $error');
    }
  }

  Future<void> toggleFavorite(Song song) async {
    final updatedFavorites = Set<String>.from(state.favorites);
    if (updatedFavorites.contains(song.id)) {
      updatedFavorites.remove(song.id);
    } else {
      updatedFavorites.add(song.id);
    }
    state = state.copyWith(favorites: updatedFavorites);
    try {
      await HiveStorageService.saveFavorites(updatedFavorites.toList());
    } catch (error) {
      _setError('Unable to save favorites: $error');
    }
  }

  Future<void> addToPlaylist(Song song, String playlistId) async {
    await _persistSong(song);
    final updatedPlaylists = Map<String, List<String>>.from(state.playlists);
    final currentSongs = List<String>.from(updatedPlaylists[playlistId] ?? const []);
    if (!currentSongs.contains(song.id)) {
      currentSongs.add(song.id);
    }
    updatedPlaylists[playlistId] = currentSongs;
    state = state.copyWith(playlists: updatedPlaylists);
    try {
      final added = await HiveStorageService.addSongToPlaylist(
        playlistId: playlistId,
        songId: song.id,
      );
      if (!added) {
        _setError('Playlist not found.');
      }
    } catch (error) {
      _setError('Unable to save playlist updates: $error');
    }
  }

  Future<String?> createPlaylist(String name) async {
    try {
      final playlist = await HiveStorageService.createPlaylist(name);
      _refreshPlaylistsFromStorage();
      return playlist.id;
    } catch (error) {
      _setError('Unable to create playlist: $error');
      return null;
    }
  }

  Future<void> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    try {
      final success = await HiveStorageService.renamePlaylist(
        playlistId: playlistId,
        newName: newName,
      );
      if (!success) {
        _setError('Playlist not found.');
        return;
      }
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to rename playlist: $error');
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      final success = await HiveStorageService.deletePlaylist(playlistId);
      if (!success) {
        _setError('Playlist not found.');
        return;
      }
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to delete playlist: $error');
    }
  }

  Future<void> removeFromPlaylist({
    required Song song,
    required String playlistId,
  }) async {
    try {
      final success = await HiveStorageService.removeSongFromPlaylist(
        playlistId: playlistId,
        songId: song.id,
      );
      if (!success) {
        _setError('Playlist not found.');
        return;
      }
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to remove song from playlist: $error');
    }
  }

  Future<void> reorderPlaylistSongs({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    try {
      final success = await HiveStorageService.reorderPlaylistSongs(
        playlistId: playlistId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      if (!success) {
        _setError('Unable to reorder playlist songs.');
        return;
      }
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to reorder playlist songs: $error');
    }
  }

  Future<void> retryPlayback() async {
    final currentSong = state.currentSong;
    if (currentSong == null) {
      _setError('Nothing to retry.');
      return;
    }

    // Always do a fresh playPlaylist so the audio source is fully rebuilt —
    // calling resume() or playSong() would reuse the failed/stalled source.
    clearError();
    _bufferingTimeoutTimer?.cancel();
    _bufferingTimeoutTimer = null;

    final songs = state.queue.isNotEmpty ? state.queue : [currentSong];
    final idx = songs.indexWhere((s) => s.id == currentSong.id);
    await playPlaylist(
      songs,
      startIndex: idx < 0 ? 0 : idx,
      startPosition: state.position,
    );
  }

  Future<void> _playFromQueueIndex(int index) async {
    try {
      if (_player.audioSource == null) {
        await _audioService.setQueue(
          songs: state.queue,
          initialIndex: index,
          preload: true,
        );
      } else {
        await _player.seek(Duration.zero, index: index);
      }
      await _player.play();
    } on AudioUrlException catch (error) {
      _setError(error.message);
    } catch (error) {
      final msg = error.toString().toLowerCase();
      if (msg.contains('socket') ||
          msg.contains('connection') ||
          msg.contains('network') ||
          msg.contains('host') ||
          msg.contains('unreachable')) {
        _setError('Network error. Check your connection and tap Retry.');
      } else {
        _setError('Playback failed. Tap Retry to try again.');
      }
    }
  }

  Future<void> _handleTrackCompletion() async {
    try {
      if (_player.hasNext) {
        await _player.seekToNext();
        await _player.play();
        return;
      }

      if (state.repeatMode == LoopMode.off) {
        await _player.seek(Duration.zero);
        await _player.pause();
      }
    } catch (error) {
      _setError('Unable to continue playback: $error');
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _persistSong(Song song) async {
    try {
      await HiveStorageService.saveSong(song);
    } catch (_) {
      // Intentionally ignored. Playback should not fail because song cache failed.
    }
  }

  void _refreshPlaylistsFromStorage() {
    state = state.copyWith(playlists: HiveStorageService.getPlaylistsSongMap());
  }

  Future<void> _persistCurrentPlayback() async {
    final currentSong = state.currentSong;
    if (currentSong == null) {
      return;
    }
    await _persistLastPlayback(currentSong.id, state.position);
  }

  Future<void> _persistLastPlayback(String songId, Duration position) async {
    try {
      await HiveStorageService.saveLastPlayback(songId: songId, position: position);
    } catch (error) {
      _setError('Unable to save playback state: $error');
    }
  }

  void _setError(String message) {
    state = state.copyWith(errorMessage: message);
  }

  @override
  void dispose() {
    _bufferingTimeoutTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
