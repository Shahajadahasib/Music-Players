import 'dart:async';

import 'package:music_player_app/models/song.dart';
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
  });

  final String id_;
  List<Song> results;
  final bool fullTracks;
  Object? error;
  Duration delay;
  final List<Song> featured;
  int calls = 0;
  final List<String> queries = [];

  @override
  SourceInfo get info => SourceInfo(
        id: id_,
        displayName: 'Fake $id_',
        fullTracks: fullTracks,
        previews: !fullTracks,
        commercialStatus: CommercialStatus.permitted,
        attribution: 'Fake',
        homepage: 'https://example.test',
      );

  @override
  Future<List<Song>> searchTracks(String query, {int limit = 25}) async {
    calls++;
    queries.add(query);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return results;
  }

  @override
  Future<List<Song>> featuredTracks({int limit = 30}) async => featured;
}
