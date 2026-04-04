import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song.dart';

/// Thrown when [play] or [setQueue] receives a URL that cannot be played.
class AudioUrlException implements Exception {
  const AudioUrlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Singleton façade over **one** [AudioPlayer] ([just_audio]).
///
/// **Streams**
/// [durationStream], [positionStream], and [playerStateStream] are each wrapped
/// with a single [Stream.asBroadcastStream] so every consumer shares the same
/// broadcast fan-out instead of re-wrapping on each getter access.
///
/// **Playback**
/// - [play] — serialized; overlapping calls are ignored while a load is in
///   progress to avoid stacked [AudioPlayer.play] invocations.
/// - [resume] — no-op if already playing.
class AudioService {
  AudioService._internal() : _player = AudioPlayer() {
    // One broadcast wrapper per underlying stream — stable identity for
    // multiple listeners without duplicating native subscriptions.
    _durationStream = _player.durationStream.asBroadcastStream();
    _positionStream = _player.positionStream.asBroadcastStream();
    _playerStateStream = _player.playerStateStream.asBroadcastStream();
  }

  static final AudioService instance = AudioService._internal();

  final AudioPlayer _player;
  bool _isInitialized = false;

  /// True while [play] is running [setAudioSource] + [play] to block re-entry.
  bool _playOperationInProgress = false;

  late final Stream<Duration?> _durationStream;
  late final Stream<Duration> _positionStream;
  late final Stream<PlayerState> _playerStateStream;

  /// The single app-wide player — do not construct another [AudioPlayer].
  AudioPlayer get player => _player;

  /// Broadcast stream — safe for multiple listeners without extra wrapping.
  Stream<Duration?> get durationStream => _durationStream;

  /// Broadcast stream — safe for multiple listeners without extra wrapping.
  Stream<Duration> get positionStream => _positionStream;

  /// Broadcast stream — safe for multiple listeners without extra wrapping.
  Stream<PlayerState> get playerStateStream => _playerStateStream;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _isInitialized = true;
  }

  /// Loads [url] as the only source and starts playback.
  ///
  /// Re-entrant calls while a previous [play] is still running are ignored so
  /// [AudioPlayer.play] is not invoked in duplicate for overlapping taps.
  Future<void> play(String url) async {
    if (_playOperationInProgress) {
      return;
    }
    _playOperationInProgress = true;
    try {
      await _player.setAudioSource(_audioSourceFromUrl(url));
      await _player.play();
    } finally {
      _playOperationInProgress = false;
    }
  }

  Future<void> pause() => _player.pause();

  /// Resumes playback; does **not** call [AudioPlayer.play] if already playing.
  Future<void> resume() async {
    if (_player.playing) {
      return;
    }
    await _player.play();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  /// Replaces the current source with a queue of Jamendo (or any HTTP) URLs.
  Future<void> setQueue({
    required List<Song> songs,
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool preload = true,
  }) async {
    if (songs.isEmpty) {
      return;
    }

    final sources = songs.map(_songToAudioSource).toList(growable: false);
    // ignore: deprecated_member_use — queue API until migrated to setAudioSources
    final queue = ConcatenatingAudioSource(children: sources);
    await _player.setAudioSource(
      queue,
      initialIndex: initialIndex.clamp(0, songs.length - 1),
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  AudioSource _songToAudioSource(Song song) {
    return _audioSourceFromUrl(song.audioUrl, tag: song);
  }

  AudioSource _audioSourceFromUrl(String url, {Object? tag}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const AudioUrlException(
        'Invalid audio URL. Use a complete HTTP/HTTPS URL.',
      );
    }

    return AudioSource.uri(uri, tag: tag);
  }

  /// Releases native player resources. Call only on app shutdown or tests —
  /// the singleton must not be used after this.
  Future<void> disposePlayer() async {
    await _player.dispose();
  }
}
