import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';
import '../playback/fallback_planner.dart';
import '../search/matched_track.dart';
import '../search/search_aggregator.dart';
import '../services/audio_service.dart';
import '../services/hive_storage_service.dart';
import '../sources/music_source.dart';
import 'player_controller_state.dart';

/// Coordinates search, playback, fallback, queue, library and timers.
///
/// Uses the single [AudioService.instance] player. All provider-specific
/// logic lives in `MusicSource`s and the [SearchAggregator]; this class only
/// decides *what* to play and recovers when a stream fails.
class PlayerController extends StateNotifier<PlayerControllerState> {
  PlayerController({
    required SearchAggregator aggregator,
    required MusicSource? Function(String id) sourceById,
    AudioService? audioService,
  })  : _aggregator = aggregator,
        _sourceById = sourceById,
        _audioService = audioService ?? AudioService.instance,
        _planner = FallbackPlanner(aggregator),
        super(const PlayerControllerState()) {
    _initialize();
  }

  final SearchAggregator _aggregator;
  final MusicSource? Function(String id) _sourceById;
  final AudioService _audioService;
  final FallbackPlanner _planner;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  DateTime? _lastPositionSavedAt;

  /// True while a new queue is being loaded; suppresses stale position events
  /// and lets [playPlaylist] handle load errors itself.
  bool _isSettingAudioSource = false;
  bool _handlingError = false;
  Timer? _bufferingTimeoutTimer;
  Timer? _sleepTimer;
  Timer? _noticeTimer;
  int _searchRequestId = 0;

  /// Startup-latency measurement for the current play request.
  Stopwatch? _startupWatch;
  ProcessingState _lastProcessing = ProcessingState.idle;

  /// Index whose play has already been written to history.
  String? _historyRecordedFor;

  /// Catalogue reference for songs started from a matched search result, so a
  /// successful play can be remembered for that song.
  final Map<String, Song> _references = {};

  AudioPlayer get _player => _audioService.player;

  Future<void> _initialize() async {
    try {
      _hydrateLibraryState();
      await _audioService.initialize();
      _bindPlayerStreams();
      final volume = HiveStorageService.readSetting<double>('volume');
      if (volume != null) {
        state = state.copyWith(volume: volume);
        await _player.setVolume(volume);
      }
      await _restoreLastPlayback();
    } catch (error) {
      debugPrint('[PlayerController] init failed: $error');
      _setError('Audio engine unavailable on this device.');
    }
  }

  // ── Hydration / restore ────────────────────────────────────────────────

  void _hydrateLibraryState() {
    try {
      final userData = HiveStorageService.getUserData();
      final lastSong = userData.lastPlayedSong == null
          ? null
          : HiveStorageService.getSongById(userData.lastPlayedSong!);
      state = state.copyWith(
        currentSong: lastSong,
        queue: lastSong == null ? const [] : [lastSong],
        currentIndex: lastSong == null ? null : 0,
        favorites: userData.favorites.toSet(),
        playlists: HiveStorageService.getPlaylistsSongMap(),
        position: userData.lastPosition,
      );
    } catch (error) {
      debugPrint('[PlayerController] hydrate failed: $error');
    }
  }

  /// Prepares the last song WITHOUT starting playback or touching the
  /// network (`preload: false`), so app start stays instant.
  Future<void> _restoreLastPlayback() async {
    final song = state.currentSong;
    if (song == null || !song.canPlay || song.audioUrl.isEmpty) return;
    _isSettingAudioSource = true;
    try {
      await _audioService.setQueue(
        songs: [song],
        initialPosition: state.position,
        preload: false,
      );
    } catch (_) {
      // Non-fatal: the user can still start anything else.
    } finally {
      _isSettingAudioSource = false;
    }
  }

  // ── Player streams ─────────────────────────────────────────────────────

  void _bindPlayerStreams() {
    _subscriptions.add(_audioService.durationStream.listen((d) {
      if (d != null) state = state.copyWith(duration: d);
    }));

    _subscriptions.add(_audioService.positionStream.listen((position) {
      if (_isSettingAudioSource) return;
      final safe = state.duration > Duration.zero && position > state.duration
          ? state.duration
          : position;
      state = state.copyWith(position: safe);
      if (state.isPlaying) {
        final now = DateTime.now();
        if (_lastPositionSavedAt == null ||
            now.difference(_lastPositionSavedAt!) >= const Duration(seconds: 5)) {
          _lastPositionSavedAt = now;
          _persistCurrentPlayback();
        }
      }
    }));

    _subscriptions.add(_player.bufferedPositionStream.listen((b) {
      state = state.copyWith(bufferedPosition: b);
    }));

    _subscriptions.add(_audioService.playerStateStream.listen(_onPlayerState));

    _subscriptions.add(_player.errorStream.listen((e) {
      if (_isSettingAudioSource) return; // handled by playPlaylist
      _onPlaybackError(e.index ?? _player.currentIndex, e);
    }));

    _subscriptions.add(_player.currentIndexStream.listen((index) {
      if (index == null || index < 0 || index >= state.queue.length) return;
      final song = state.queue[index];
      state = state.copyWith(
        currentSong: song,
        currentIndex: index,
        duration: _player.sequenceState.currentSource?.duration ??
            (song.isPreview ? Duration.zero : song.duration ?? Duration.zero),
        position: Duration.zero,
      );
      _persistLastPlayback(song.id, Duration.zero);
    }));

    _subscriptions.add(_player.sequenceStateStream.listen((_) {
      state = state.copyWith(effectiveOrder: _player.effectiveIndices);
    }));

    _subscriptions.add(_player.positionDiscontinuityStream.listen((d) {
      if (d.reason == PositionDiscontinuityReason.autoAdvance &&
          state.sleepAtEndOfTrack) {
        _player.pause();
        state = state.copyWith(clearSleepTimer: true, notice: 'Sleep timer ended');
      }
    }));

    _subscriptions.add(_player.shuffleModeEnabledStream.listen((on) {
      state = state.copyWith(isShuffle: on);
    }));
    _subscriptions.add(_player.loopModeStream.listen((mode) {
      state = state.copyWith(repeatMode: mode);
    }));
  }

  void _onPlayerState(PlayerState ps) {
    final processing = ps.processingState;
    final isBuffering = processing == ProcessingState.buffering ||
        processing == ProcessingState.loading;

    // Rebuffer = was playing smoothly, then stalled.
    if (_lastProcessing == ProcessingState.ready &&
        processing == ProcessingState.buffering &&
        ps.playing) {
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          rebufferCount: state.diagnostics.rebufferCount + 1,
        ),
      );
    }
    _lastProcessing = processing;

    state = state.copyWith(
      isPlaying: ps.playing,
      processingState: processing,
      isBuffering: isBuffering,
    );

    if (processing == ProcessingState.ready && ps.playing) {
      _onStartedPlaying();
    }
    if (processing == ProcessingState.completed) {
      _handleQueueCompleted();
    }

    if (isBuffering && ps.playing && !_isSettingAudioSource) {
      _bufferingTimeoutTimer ??= Timer(const Duration(seconds: 20), () {
        _bufferingTimeoutTimer = null;
        if (state.isBuffering && state.currentIndex != null) {
          // Treat a long stall like a failure → try another source.
          _onPlaybackError(state.currentIndex, null);
        }
      });
    } else {
      _bufferingTimeoutTimer?.cancel();
      _bufferingTimeoutTimer = null;
    }
  }

  void _onStartedPlaying() {
    final watch = _startupWatch;
    if (watch != null) {
      _startupWatch = null;
      final samples = [...state.diagnostics.startupSamplesMs, watch.elapsedMilliseconds];
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          startupSamplesMs:
              samples.length > 50 ? samples.sublist(samples.length - 50) : samples,
        ),
      );
    }
    final song = state.currentSong;
    final idx = state.currentIndex;
    if (song == null || idx == null) return;
    final marker = '$idx:${song.id}';
    if (_historyRecordedFor == marker) return;
    _historyRecordedFor = marker;
    _planner.markSuccess(song);
    final ref = _references[song.id];
    if (ref != null) unawaited(_aggregator.rememberSuccess(ref, song));
    if (!(kIsWeb && song.isLocal)) {
      unawaited(_safe(() => HiveStorageService.saveSong(song)));
      unawaited(_safe(() => HiveStorageService.addHistory(song.id, DateTime.now())));
    }
  }

  // ── Search ─────────────────────────────────────────────────────────────

  Future<AggregatedSearchResult?> search(String query) async {
    final q = query.trim();
    final requestId = ++_searchRequestId;
    if (q.isEmpty) {
      state = state.copyWith(
        clearSearchResult: true,
        searchResults: const [],
        isSearchLoading: false,
        clearSearchError: true,
      );
      return null;
    }
    state = state.copyWith(isSearchLoading: true, clearSearchError: true);
    try {
      final result = await _aggregator.search(q);
      if (requestId != _searchRequestId) return result;
      state = state.copyWith(
        searchResult: result,
        searchResults: result.playableSongs,
        isSearchLoading: false,
        searchError: result.allSourcesFailed
            ? 'Music services are unreachable. Check your connection and try again.'
            : null,
        clearSearchError: !result.allSourcesFailed,
      );
      return result;
    } catch (error) {
      if (requestId != _searchRequestId) return null;
      state = state.copyWith(
        isSearchLoading: false,
        searchError: 'Search failed. Please try again.',
      );
      return null;
    }
  }

  /// Back-compat name used by older widgets.
  Future<void> searchSongs(String query) => search(query);

  // ── Starting playback ──────────────────────────────────────────────────

  /// Plays search results starting at [index]. Catalogue-only tracks in the
  /// list are skipped; if the tapped one is catalogue-only, an authorised
  /// stream for the same recording is looked up first.
  Future<bool> playMatched(
    List<MatchedTrack> tracks,
    int index, {
    bool reportUnavailable = true,
  }) async {
    if (index < 0 || index >= tracks.length) return false;
    final tapped = tracks[index];
    final queue = <Song>[];
    var start = 0;
    for (var i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      Song? song;
      if (t.isPlayable) {
        song = t.best;
        _planner.registerCandidates(song, t.candidates);
        _references[song.id] = t.display;
      } else if (i == index) {
        song = await _resolveCatalogueTrack(t.display, report: reportUnavailable);
        if (song == null) return false;
      }
      if (song == null) continue;
      if (i == index) start = queue.length;
      queue.add(song);
    }
    if (queue.isEmpty) return false;
    _references.putIfAbsent(queue[start].id, () => tapped.display);
    await playPlaylist(queue, startIndex: start);
    return true;
  }

  /// Plays a single song (resolving a catalogue-only song if needed).
  Future<bool> playSong(Song song) async {
    if (state.currentSong?.id == song.id && _player.audioSource != null) {
      if (!state.isPlaying) await resume();
      return true;
    }
    final playable = song.canPlay ? song : await _resolveCatalogueTrack(song);
    if (playable == null) return false;
    final idx = state.queue.indexWhere((s) => s.id == playable.id);
    if (idx >= 0 && _player.audioSource != null) {
      await jumpTo(idx);
      return true;
    }
    await playPlaylist([playable]);
    return true;
  }

  Future<Song?> _resolveCatalogueTrack(Song reference, {bool report = true}) async {
    state = state.copyWith(isResolving: true, clearError: true);
    try {
      final found = await _aggregator.findPlayableFor(reference);
      if (found.isEmpty) {
        if (!report) return null;
        _setError(
          '“${reference.title}” isn’t available from an authorised streaming '
          'source in this app.',
        );
        return null;
      }
      final best = found.first;
      _planner.registerCandidates(best, found);
      _references[best.id] = reference;
      return best;
    } catch (_) {
      _setError('Couldn’t look up a stream. Check your connection.');
      return null;
    } finally {
      state = state.copyWith(isResolving: false);
    }
  }

  Future<void> playPlaylist(
    List<Song> songs, {
    int startIndex = 0,
    Duration startPosition = Duration.zero,
  }) async {
    var playable = songs.where((s) => s.canPlay).toList();
    if (playable.isEmpty) {
      _setError('Nothing playable in this list.');
      return;
    }
    final requested = songs[startIndex.clamp(0, songs.length - 1)];
    var start = playable.indexWhere((s) => s.id == requested.id);
    if (start < 0) start = 0;

    _startupWatch = Stopwatch()..start();
    state = state.copyWith(isResolving: true, clearError: true);
    playable = await _resolveLazyStreams(playable, mustResolve: playable[start]);
    state = state.copyWith(isResolving: false);
    start = playable.indexWhere((s) => s.id == requested.id);
    if (start < 0) start = 0;
    if (playable.isEmpty) {
      _setError('Couldn’t reach the music source. Try again.');
      return;
    }

    state = state.copyWith(
      queue: playable,
      currentSong: playable[start],
      currentIndex: start,
      position: startPosition,
      duration: Duration.zero,
      clearError: true,
    );
    _isSettingAudioSource = true;
    _lastPositionSavedAt = DateTime.now();
    try {
      unawaited(_safe(() => HiveStorageService.saveSongs(
            [for (final s in playable) if (!(kIsWeb && s.isLocal)) s],
          )));
      await _audioService.setQueue(
        songs: playable,
        initialIndex: start,
        initialPosition: startPosition,
      );
      _isSettingAudioSource = false;
      unawaited(_player.play());
      await _persistLastPlayback(playable[start].id, startPosition);
    } on AudioUrlException catch (e) {
      _isSettingAudioSource = false;
      _setError(e.message);
    } on PlayerException catch (e) {
      _isSettingAudioSource = false;
      await _onPlaybackError(e.index ?? start, e);
    } on PlayerInterruptedException {
      _isSettingAudioSource = false; // superseded by a newer request
    } catch (e) {
      _isSettingAudioSource = false;
      debugPrint('[PlayerController] load failed: $e');
      await _onPlaybackError(start, null);
    }
  }

  /// Resolves streams for providers that need a lookup (Internet Archive).
  Future<List<Song>> _resolveLazyStreams(List<Song> songs, {required Song mustResolve}) async {
    final out = <Song>[];
    final futures = songs.map((s) async {
      if (s.isLocal || s.audioUrl.isNotEmpty) return s;
      final source = _sourceById(s.sourceId);
      if (source == null) return null;
      try {
        final uri = await source.resolveStream(s).timeout(const Duration(seconds: 8));
        return uri == null ? null : s.copyWith(audioUrl: uri.toString());
      } catch (_) {
        return null;
      }
    });
    for (final s in await Future.wait(futures)) {
      if (s != null) out.add(s);
    }
    return out;
  }

  // ── Failure recovery / fallback ────────────────────────────────────────

  Future<void> _onPlaybackError(int? index, PlayerException? error) async {
    if (_handlingError) return;
    if (index == null || index < 0 || index >= state.queue.length) {
      _setError('Playback failed. Tap retry.');
      return;
    }
    _handlingError = true;
    try {
      final failed = state.queue[index];
      debugPrint('[PlayerController] playback error on ${failed.id}: $error');
      final hadStarted = state.currentIndex == index &&
          state.position > const Duration(seconds: 2);

      // 1. Transient mid-stream drop → retry same source from where it was.
      if (_planner.shouldRetrySame(failed, hadStarted: hadStarted)) {
        final resumeAt = state.position;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        try {
          await _audioService.replace(index, failed);
          await _player.seek(resumeAt, index: index);
          await _player.play();
          return;
        } catch (_) {/* fall through to alternatives */}
      }

      // 2/3. Another authorised source for the same recording.
      state = state.copyWith(isResolving: true);
      var alt = await _planner.nextFor(failed);
      while (alt != null) {
        final resolved = (await _resolveLazyStreams([alt], mustResolve: alt));
        if (resolved.isNotEmpty) {
          final next = resolved.first;
          try {
            await _audioService.replace(index, next);
            final q = [...state.queue]..[index] = next;
            final ref = _references[failed.id];
            if (ref != null) _references[next.id] = ref;
            state = state.copyWith(
              queue: q,
              currentSong: state.currentIndex == index ? next : state.currentSong,
              diagnostics: state.diagnostics.copyWith(
                fallbackCount: state.diagnostics.fallbackCount + 1,
              ),
            );
            await _player.seek(Duration.zero, index: index);
            unawaited(_player.play());
            _showNotice(next.isPreview
                ? 'Full track unavailable — playing a preview'
                : 'Switched to ${_sourceName(next.sourceId)} for this song');
            return;
          } catch (_) {/* try the next alternative */}
        }
        alt = await _planner.nextFor(failed);
      }

      // 4. Give up on this song.
      state = state.copyWith(
        diagnostics: state.diagnostics.copyWith(
          failedCount: state.diagnostics.failedCount + 1,
        ),
      );
      if (_player.hasNext) {
        await _player.seekToNext();
        unawaited(_player.play());
        _showNotice('Couldn’t play “${failed.title}” — skipped');
      } else {
        await _player.pause();
        _setError('Couldn’t play “${failed.title}”. Check your connection and retry.');
      }
    } finally {
      state = state.copyWith(isResolving: false);
      _handlingError = false;
    }
  }

  String _sourceName(String id) => _sourceById(id)?.info.displayName ?? id;

  // ── Transport ──────────────────────────────────────────────────────────

  Future<void> pause() async {
    try {
      await _audioService.pause();
      await _persistCurrentPlayback();
    } catch (error) {
      _setError('Unable to pause.');
    }
  }

  Future<void> resume() async {
    if (_player.audioSource == null || _player.processingState == ProcessingState.idle) {
      final current = state.currentSong;
      if (current == null) return;
      final songs = state.queue.isNotEmpty ? state.queue : [current];
      final idx = songs.indexWhere((s) => s.id == current.id);
      await playPlaylist(songs, startIndex: idx < 0 ? 0 : idx, startPosition: state.position);
      return;
    }
    try {
      await _audioService.resume();
    } catch (error) {
      _setError('Unable to resume.');
    }
  }

  Future<void> togglePlayPause() => state.isPlaying ? pause() : resume();

  Future<void> seek(Duration position) async {
    var target = position < Duration.zero ? Duration.zero : position;
    if (state.duration > Duration.zero && target > state.duration) {
      target = state.duration;
    }
    try {
      await _audioService.seek(target);
      state = state.copyWith(position: target);
      await _persistCurrentPlayback();
    } catch (error) {
      _setError('Unable to seek.');
    }
  }

  Future<void> next() async {
    try {
      if (_player.hasNext) {
        await _player.seekToNext();
        if (!_player.playing) unawaited(_player.play());
      }
    } catch (error) {
      _setError('Unable to skip.');
    }
  }

  /// Restarts the current track if more than 3 s in, otherwise goes back.
  Future<void> previous() async {
    try {
      if (state.position > const Duration(seconds: 3) || !_player.hasPrevious) {
        await _player.seek(Duration.zero);
      } else {
        await _player.seekToPrevious();
      }
      if (!_player.playing) unawaited(_player.play());
    } catch (error) {
      _setError('Unable to go back.');
    }
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    try {
      _startupWatch = Stopwatch()..start();
      await _player.seek(Duration.zero, index: index);
      if (!_player.playing) unawaited(_player.play());
    } catch (_) {
      _setError('Unable to play that track.');
    }
  }

  Future<void> toggleShuffle() async {
    final next = !state.isShuffle;
    try {
      if (next) await _player.shuffle();
      await _player.setShuffleModeEnabled(next);
      state = state.copyWith(isShuffle: next, effectiveOrder: _player.effectiveIndices);
    } catch (error) {
      _setError('Unable to change shuffle.');
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
      _setError('Unable to change repeat.');
    }
  }

  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: v);
    try {
      await _player.setVolume(v);
      await HiveStorageService.writeSetting('volume', v);
    } catch (_) {}
  }

  Future<void> _handleQueueCompleted() async {
    if (state.repeatMode != LoopMode.off) return;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
      if (state.sleepAtEndOfTrack) state = state.copyWith(clearSleepTimer: true);
    } catch (_) {}
  }

  // ── Queue editing ──────────────────────────────────────────────────────

  Future<void> addToQueue(Song song) async {
    if (!song.canPlay) {
      final resolved = await _resolveCatalogueTrack(song);
      if (resolved == null) return;
      song = resolved;
    }
    if (_player.audioSource == null || state.queue.isEmpty) {
      await playPlaylist([song]);
      return;
    }
    final list = await _resolveLazyStreams([song], mustResolve: song);
    if (list.isEmpty) return;
    try {
      await _audioService.add(list.first);
      state = state.copyWith(queue: [...state.queue, list.first]);
      _showNotice('Added to queue');
    } catch (_) {
      _setError('Couldn’t add to queue.');
    }
  }

  Future<void> playNext(Song song) async {
    if (!song.canPlay) {
      final resolved = await _resolveCatalogueTrack(song);
      if (resolved == null) return;
      song = resolved;
    }
    final current = state.currentIndex;
    if (_player.audioSource == null || current == null) {
      await playPlaylist([song]);
      return;
    }
    final list = await _resolveLazyStreams([song], mustResolve: song);
    if (list.isEmpty) return;
    try {
      final at = current + 1;
      await _audioService.insert(at, list.first);
      final q = [...state.queue]..insert(at, list.first);
      state = state.copyWith(queue: q);
      _showNotice('Playing next');
    } catch (_) {
      _setError('Couldn’t update the queue.');
    }
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length || index == state.currentIndex) return;
    try {
      await _audioService.removeAt(index);
      final q = [...state.queue]..removeAt(index);
      final cur = state.currentIndex;
      state = state.copyWith(
        queue: q,
        currentIndex: cur != null && index < cur ? cur - 1 : cur,
      );
    } catch (_) {
      _setError('Couldn’t update the queue.');
    }
  }

  /// Moves an item in playlist order (used by the queue editor when shuffle
  /// is off).
  Future<void> moveInQueue(int from, int to) async {
    if (from == to || from < 0 || to < 0 || from >= state.queue.length || to >= state.queue.length) {
      return;
    }
    try {
      await _audioService.move(from, to);
      final q = [...state.queue];
      final item = q.removeAt(from);
      q.insert(to, item);
      state = state.copyWith(queue: q, currentIndex: _player.currentIndex);
    } catch (_) {
      _setError('Couldn’t reorder the queue.');
    }
  }

  // ── Sleep timer ────────────────────────────────────────────────────────

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () async {
      await pause();
      state = state.copyWith(clearSleepTimer: true, notice: 'Sleep timer ended');
    });
    state = state.copyWith(
      sleepTimerEndsAt: DateTime.now().add(duration),
      sleepAtEndOfTrack: false,
    );
  }

  void setSleepAtEndOfTrack() {
    _sleepTimer?.cancel();
    state = state.copyWith(clearSleepTimer: true);
    state = state.copyWith(sleepAtEndOfTrack: true);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    state = state.copyWith(clearSleepTimer: true);
  }

  // ── Favourites & playlists ─────────────────────────────────────────────

  Future<void> toggleFavorite(Song song) async {
    final updated = Set<String>.from(state.favorites);
    if (!updated.remove(song.id)) {
      updated.add(song.id);
      await _persistSong(song);
    }
    state = state.copyWith(favorites: updated);
    try {
      await HiveStorageService.saveFavorites(updated.toList());
    } catch (error) {
      _setError('Unable to save favourites.');
    }
  }

  Future<void> addToPlaylist(Song song, String playlistId) async {
    await _persistSong(song);
    try {
      final added = await HiveStorageService.addSongToPlaylist(
        playlistId: playlistId,
        songId: song.id,
      );
      if (!added) _setError('Playlist not found.');
      _refreshPlaylistsFromStorage();
      _showNotice('Added to playlist');
    } catch (error) {
      _setError('Unable to save playlist.');
    }
  }

  Future<String?> createPlaylist(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      _setError('Playlist names must be 1–100 characters.');
      return null;
    }
    try {
      final playlist = await HiveStorageService.createPlaylist(trimmed);
      _refreshPlaylistsFromStorage();
      return playlist.id;
    } catch (error) {
      _setError('Unable to create playlist.');
      return null;
    }
  }

  Future<void> renamePlaylist({required String playlistId, required String newName}) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed.length > 100) {
      _setError('Playlist names must be 1–100 characters.');
      return;
    }
    try {
      if (!await HiveStorageService.renamePlaylist(playlistId: playlistId, newName: trimmed)) {
        _setError('Playlist not found.');
      }
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to rename playlist.');
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      await HiveStorageService.deletePlaylist(playlistId);
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to delete playlist.');
    }
  }

  Future<void> removeFromPlaylist({required Song song, required String playlistId}) async {
    try {
      await HiveStorageService.removeSongFromPlaylist(playlistId: playlistId, songId: song.id);
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to update playlist.');
    }
  }

  Future<void> reorderPlaylistSongs({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    try {
      await HiveStorageService.reorderPlaylistSongs(
        playlistId: playlistId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      _refreshPlaylistsFromStorage();
    } catch (error) {
      _setError('Unable to reorder playlist.');
    }
  }

  Future<void> retryPlayback() async {
    final current = state.currentSong;
    if (current == null) return;
    clearError();
    _bufferingTimeoutTimer?.cancel();
    _bufferingTimeoutTimer = null;
    final songs = state.queue.isNotEmpty ? state.queue : [current];
    final idx = songs.indexWhere((s) => s.id == current.id);
    await playPlaylist(songs, startIndex: idx < 0 ? 0 : idx, startPosition: state.position);
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clearNotice() => state = state.copyWith(clearNotice: true);

  void _showNotice(String message) {
    _noticeTimer?.cancel();
    state = state.copyWith(notice: message);
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) state = state.copyWith(clearNotice: true);
    });
  }

  // ── Persistence helpers ────────────────────────────────────────────────

  Future<void> _persistSong(Song song) async {
    if (kIsWeb && song.isLocal) return;
    await _safe(() => HiveStorageService.saveSong(song));
  }

  void _refreshPlaylistsFromStorage() {
    state = state.copyWith(playlists: HiveStorageService.getPlaylistsSongMap());
  }

  Future<void> _persistCurrentPlayback() async {
    final song = state.currentSong;
    if (song == null) return;
    await _persistLastPlayback(song.id, state.position);
  }

  Future<void> _persistLastPlayback(String songId, Duration position) =>
      _safe(() => HiveStorageService.saveLastPlayback(songId: songId, position: position));

  static Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('[PlayerController] storage error: $e');
    }
  }

  void _setError(String message) {
    if (mounted) state = state.copyWith(errorMessage: message);
  }

  @override
  void dispose() {
    _bufferingTimeoutTimer?.cancel();
    _sleepTimer?.cancel();
    _noticeTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
