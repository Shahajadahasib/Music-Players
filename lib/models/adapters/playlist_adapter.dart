import 'package:hive_flutter/hive_flutter.dart';

import '../playlist.dart';

class PlaylistAdapter extends TypeAdapter<Playlist> {
  @override
  final int typeId = 1;

  @override
  Playlist read(BinaryReader reader) {
    final id = reader.readString();
    final name = reader.readString();
    final songIds = reader.readStringList();
    final createdAtMillis = reader.readInt();

    return Playlist(
      id: id,
      name: name,
      songIds: songIds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
    );
  }

  @override
  void write(BinaryWriter writer, Playlist obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.name);
    writer.writeStringList(obj.songIds);
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
  }
}
