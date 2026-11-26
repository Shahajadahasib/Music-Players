import 'dart:async';

import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/playback/stream_verifier.dart';
import 'package:music_player_app/sources/music_source.dart';

/// Builds a test song. These are test fixtures only — never shown in the app.
Song song(
  String id, {
  String title = 'Title',
  String artist = 'Artist',
  String album = '',
  int? seconds,
  String sourceId = 'fake',
  Playability playability = Playability.full,
  String audioUrl = 'https://example.test/a.mp3',
  String externalUrl = '',
  String isrc = '',
  String license = '',
}) =>
    Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      audioUrl: playability == Playability.none ? '' : audioUrl,
      coverUrl: '',
      duration: seconds == null ? null : Duration(seconds: seconds),
      sourceId: sourceId,
      playability: playability,
      externalUrl: externalUrl,
      isrc: isrc,
      license: license,
    );

/// In-memory provider used to exercise search, ranking and fallback logic.
class FakeSource extends MusicSource {
  FakeSource(
    this.id_, {
    this.results = const [],
    this.fullTracks = true,
    this.error,
    this.delay = Duration.zero,
    this.featured = const [],
    this.kind,
  });

  /// Overrides the provider kind (default: derived from [fullTracks]).
  final SourceKind? kind;

  final String id_;
  List<Song> results;
  final bool fullTracks;
  Object? error;
  Duration delay;
  final List<Song> featured;
  int calls = 0;
  final List<String> queries = [];

  /// Called on every search (e.g. to simulate a newer query arriving).
  void Function()? onSearch;

  @override
  SourceInfo get info => SourceInfo(
        id: id_,
        displayName: 'Fake $id_',
        fullTracks: fullTracks,
        previews: !fullTracks,
        commercialStatus: CommercialStatus.permitted,
        attribution: 'Fake',
        homepage: 'https://example.test',
        kind: kind,
      );

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    calls++;
    queries.add(query);
    onSearch?.call();
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<List<Song>> featuredTracks({int limit = 30}) async => featured;
}

/// Scripted stream checks: ids in [unavailable] fail, everything else plays.
/// Records every id it was asked about.
class FakeVerifier implements StreamVerifier {
  FakeVerifier({Set<String>? unavailable, Set<String>? unknown})
      : unavailable = unavailable ?? {},
        unknown = unknown ?? {};

  final Set<String> unavailable;
  final Set<String> unknown;
  final List<String> checked = [];

  @override
  Future<StreamCheck> verify(Song song) async {
    checked.add(song.id);
    if (unavailable.contains(song.id)) {
      return const StreamCheck(StreamStatus.unavailable, reason: 'HTTP 403');
    }
    if (unknown.contains(song.id)) {
      return const StreamCheck(StreamStatus.unknown, reason: 'timeout');
    }
    return StreamCheck(StreamStatus.playable, uri: Uri.parse('https://stream.test/${song.id}'));
  }

  @override
  StreamCheck? cached(String songId) =>
      unavailable.contains(songId) ? const StreamCheck(StreamStatus.unavailable) : null;

  @override
  void markUnplayable(String songId, {String reason = ''}) => unavailable.add(songId);
}
