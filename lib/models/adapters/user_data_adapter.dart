import 'package:hive_flutter/hive_flutter.dart';

import '../user_data.dart';

class UserDataAdapter extends TypeAdapter<UserData> {
  @override
  final int typeId = 2;

  @override
  UserData read(BinaryReader reader) {
    final favorites = reader.readStringList();
    final hasLastPlayedSong = reader.readBool();
    final lastPlayedSong = hasLastPlayedSong ? reader.readString() : null;
    final lastPositionMillis = reader.readInt();

    return UserData(
      favorites: favorites,
      lastPlayedSong: lastPlayedSong,
      lastPosition: Duration(milliseconds: lastPositionMillis),
    );
  }

  @override
  void write(BinaryWriter writer, UserData obj) {
    writer.writeStringList(obj.favorites);
    writer.writeBool(obj.lastPlayedSong != null);
    if (obj.lastPlayedSong != null) {
      writer.writeString(obj.lastPlayedSong!);
    }
    writer.writeInt(obj.lastPosition.inMilliseconds);
  }
}
