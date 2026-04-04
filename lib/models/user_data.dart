import 'package:equatable/equatable.dart';

class UserData extends Equatable {
  const UserData({
    required this.favorites,
    this.lastPlayedSong,
    this.lastPosition = Duration.zero,
  });

  final List<String> favorites;
  final String? lastPlayedSong;
  final Duration lastPosition;

  UserData copyWith({
    List<String>? favorites,
    String? lastPlayedSong,
    bool clearLastPlayedSong = false,
    Duration? lastPosition,
  }) {
    return UserData(
      favorites: favorites ?? this.favorites,
      lastPlayedSong: clearLastPlayedSong ? null : (lastPlayedSong ?? this.lastPlayedSong),
      lastPosition: lastPosition ?? this.lastPosition,
    );
  }

  @override
  List<Object?> get props => [favorites, lastPlayedSong, lastPosition];
}
