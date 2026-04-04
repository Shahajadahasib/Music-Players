import 'package:hive_flutter/hive_flutter.dart';

import '../song.dart';

class SongAdapter extends TypeAdapter<Song> {
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

    return Song(
      id: id,
      title: title,
      artist: artist,
      album: album,
      audioUrl: audioUrl,
      coverUrl: coverUrl,
      duration: duration,
    );
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
  }
}
