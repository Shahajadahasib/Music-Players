import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/song.dart';

/// Thrown when a song has no usable audio URL.
class AudioUrlException implements Exception {
  const AudioUrlException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Singleton façade over the app's **single** [AudioPlayer].
///
/// * Every source carries a [MediaItem] tag so `just_audio_background` can
///   drive the Android notification, iOS lock screen / Control Center, the
///   browser Media Session, Bluetooth and headset buttons.
/// * `handleInterruptions` (default) makes just_audio pause on phone calls /
///   focus loss, duck for navigation prompts, resume afterwards, and pause
///   when headphones are unplugged ("becoming noisy").
class AudioService {
  AudioService._internal()
      : _player = AudioPlayer(
          // Load the next track ahead of time → near-gapless transitions.
          useLazyPreparation: true,
          audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
              // Start quickly (1.5 s buffered) but keep a 50 s cushion.
              bufferForPlaybackDuration: Duration(milliseconds: 1500),
              bufferForPlaybackAfterRebufferDuration: Duration(seconds: 4),
              maxBufferDuration: Duration(seconds: 50),
            ),
            darwinLoadControl: DarwinLoadControl(
              automaticallyWaitsToMinimizeStalling: true,
              preferredForwardBufferDuration: Duration(seconds: 30),
            ),
          ),
        );

  static final AudioService instance = AudioService._internal();

  final AudioPlayer _player;
  bool _isInitialized = false;

  /// Directory holding imported local files (mobile). Set at startup.
  static String? localMusicDir;

  /// Web-only: in-memory data URIs for files picked this session.
  static final Map<String, Uri> webLocalUris = {};

  AudioPlayer get player => _player;

  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _isInitialized = true;
  }

  Future<void> pause() => _player.pause();

  Future<void> resume() async {
    if (_player.playing) return;
    await _player.play();
  }

  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);

  Future<void> setQueue({
    required List<Song> songs,
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
    bool preload = true,
  }) async {
    if (songs.isEmpty) return;
    await _player.setAudioSources(
      songs.map(audioSourceFor).toList(growable: false),
      initialIndex: initialIndex.clamp(0, songs.length - 1),
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  Future<void> insert(int index, Song song) =>
      _player.insertAudioSource(index, audioSourceFor(song));

  Future<void> add(Song song) => _player.addAudioSource(audioSourceFor(song));

  Future<void> removeAt(int index) => _player.removeAudioSourceAt(index);

  Future<void> move(int from, int to) => _player.moveAudioSource(from, to);

  /// Replaces the source at [index] (used when falling back to another
  /// provider for the same song).
  Future<void> replace(int index, Song song) async {
    await _player.insertAudioSource(index + 1, audioSourceFor(song));
    await _player.removeAudioSourceAt(index);
  }

  /// Builds the audio source for [song], tagged for system media controls.
  static AudioSource audioSourceFor(Song song) {
    final uri = uriFor(song);
    final tag = MediaItem(
      id: song.id,
      title: song.title.isEmpty ? 'Unknown title' : song.title,
      artist: song.artist.isEmpty ? null : song.artist,
      album: song.album.isEmpty ? null : song.album,
      duration: song.isPreview ? null : song.duration,
      artUri: song.coverUrl.startsWith('https://') ? Uri.parse(song.coverUrl) : null,
      extras: {'sourceId': song.sourceId},
    );
    return AudioSource.uri(uri, tag: tag);
  }

  static Uri uriFor(Song song) {
    if (!song.canPlay) {
      throw const AudioUrlException('This track is not available to stream.');
    }
    if (song.isLocal) {
      if (kIsWeb) {
        final u = webLocalUris[song.id];
        if (u != null) return u;
        throw const AudioUrlException(
          'Local files on the web must be re-opened each session.',
        );
      }
      const prefix = 'local-file:';
      if (song.audioUrl.startsWith(prefix) && localMusicDir != null) {
        return Uri.file('$localMusicDir/${song.audioUrl.substring(prefix.length)}');
      }
    }
    final uri = Uri.tryParse(song.audioUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const AudioUrlException('This track has no valid audio stream.');
    }
    return uri;
  }

  Future<void> disposePlayer() => _player.dispose();
}
