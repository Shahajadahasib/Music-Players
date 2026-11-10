import 'package:hive_flutter/hive_flutter.dart';

import '../song.dart';

/// Binary layout:
///
/// v1 (original app): id, title, artist, album, audioUrl, coverUrl,
///                    hasDuration, [durationMs]
/// v2 (appended):     schemaVersion(=2), sourceId, playabilityIndex,
///                    externalUrl, license, artistId, albumId
///
/// Hive bounds each frame, so a v1 record simply has no bytes left after the
/// duration and is read with v2 defaults (an Audius full-track stream, which
/// is what the original app stored).
class SongAdapter extends TypeAdapter<Song> {
  static const int _schemaVersion = 2;

  @override
  final int typeId = 0;

  @override
  Song read(BinaryReader reader) {
    final id = reader.readString();
    final title = reader.readString();
    final artist = reader.readString();
    final album = reader.readString();
    final audioUrl = reader.readString();
    final coverUrl = reader.readString();
    final hasDuration = reader.readBool();
    final duration = hasDuration ? Duration(milliseconds: reader.readInt()) : null;

    var song = Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      audioUrl: audioUrl,
      coverUrl: coverUrl,
      duration: duration,
    );

    if (reader.availableBytes > 0) {
      final version = reader.readByte();
      if (version >= 2) {
        final sourceId = reader.readString();
        final playabilityIndex = reader.readByte();
        final externalUrl = reader.readString();
        final license = reader.readString();
        final artistId = reader.readString();
        final albumId = reader.readString();
        song = song.copyWith(
          sourceId: sourceId,
          playability: playabilityIndex < Playability.values.length
              ? Playability.values[playabilityIndex]
              : Playability.none,
          externalUrl: externalUrl,
          license: license,
          artistId: artistId,
          albumId: albumId,
        );
      }
    }
    return song;
  }

  @override
  void write(BinaryWriter writer, Song obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.title);
    writer.writeString(obj.artist);
    writer.writeString(obj.album);
    writer.writeString(obj.audioUrl);
    writer.writeString(obj.coverUrl);
    writer.writeBool(obj.duration != null);
    if (obj.duration != null) {
      writer.writeInt(obj.duration!.inMilliseconds);
    }
    writer.writeByte(_schemaVersion);
    writer.writeString(obj.sourceId);
    writer.writeByte(obj.playability.index);
    writer.writeString(obj.externalUrl);
    writer.writeString(obj.license);
    writer.writeString(obj.artistId);
    writer.writeString(obj.albumId);
  }
}
