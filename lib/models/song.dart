import 'package:equatable/equatable.dart';

class Song extends Equatable {
  /// Parses a single track item from the Jamendo `/v3.0/tracks/` JSON response.
  ///
  /// Expected shape (with `audioformat=mp32`):
  /// ```json
  /// {
  ///   "id": "1234",
  ///   "name": "Track Name",
  ///   "artist_name": "Artist",
  ///   "album_name": "Album",
  ///   "audio": "https://mp3d.jamendo.com/...",
  ///   "image": "https://usercontent.jamendo.com/...",
  ///   "duration": 245
  /// }
  /// ```
  factory Song.fromJamendoJson(Map<String, dynamic> json) {
    // Jamendo returns `id` as either an int or a string depending on
    // the API version; normalise to String.
    final rawId = json['id'];
    final id = rawId?.toString() ?? '';

    // `duration` is in whole seconds.
    final durationSeconds = json['duration'];
    final Duration? duration;
    if (durationSeconds is int) {
      duration = Duration(seconds: durationSeconds);
    } else if (durationSeconds is String) {
      final parsed = int.tryParse(durationSeconds);
      duration = parsed != null ? Duration(seconds: parsed) : null;
    } else {
      duration = null;
    }

    return Song(
      id: id,
      title: (json['name'] as String?) ?? '',
      artist: (json['artist_name'] as String?) ?? '',
      album: (json['album_name'] as String?) ?? '',
      audioUrl: (json['audio'] as String?) ?? '',
      coverUrl: (json['image'] as String?) ?? '',
      duration: duration,
    );
  }

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.audioUrl,
    required this.coverUrl,
    this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String audioUrl;
  final String coverUrl;
  final Duration? duration;

  Song copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? audioUrl,
    String? coverUrl,
    Duration? duration,
    bool clearDuration = false,
  }) {
    return Song(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      audioUrl: audioUrl ?? this.audioUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: clearDuration ? null : (duration ?? this.duration),
    );
  }

  @override
  List<Object?> get props => [id, title, artist, album, audioUrl, coverUrl, duration];
}
