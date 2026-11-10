import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/adapters/playlist_adapter.dart';
import '../models/adapters/song_adapter.dart';
import '../models/adapters/user_data_adapter.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../models/user_data.dart';
class HiveStorageService {
  HiveStorageService._();

  static const String songsBoxName = 'songs_box';
  static const String playlistsBoxName = 'playlists_box';
  static const String userDataBoxName = 'user_data_box';
  static const String userDataKey = 'user_data';
  static const String settingsBoxName = 'settings_box';
  static const String historyBoxName = 'history_box';
  static const String matchMemoryBoxName = 'match_memory_box';

  /// Maximum playback-history entries kept on device.
  static const int historyLimit = 500;

  /// Legacy placeholder tracks from an earlier app version (see git history).
  static const Set<String> _legacyDemoSongIds = {'s1', 's2', 's3', 's4'};

  static Future<void> initialize({String? rootPath}) async {
    if (rootPath == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(rootPath);
    }
    _registerAdapters();

    await Future.wait([
      Hive.openBox<Song>(songsBoxName),
      Hive.openBox<Playlist>(playlistsBoxName),
      Hive.openBox<UserData>(userDataBoxName),
      Hive.openBox<dynamic>(settingsBoxName),
      Hive.openBox<Map<dynamic, dynamic>>(historyBoxName),
      Hive.openBox<String>(matchMemoryBoxName),
    ]);

    await _clearLegacyDemoSongsIfNeeded();

    if (!_userDataBox.containsKey(userDataKey)) {
      await _userDataBox.put(userDataKey, const UserData(favorites: []));
    }
  }

  /// Removes installs that only had the old SoundHelix placeholders so
  /// [PlayerController] can refill from Audius trending.
  static Future<void> _clearLegacyDemoSongsIfNeeded() async {
    final keys = _songsBox.keys.cast<String>().toSet();
    if (keys.isEmpty) return;
    if (keys.every(_legacyDemoSongIds.contains)) {
      await _songsBox.clear();
    }
  }

  static Box<Song> get _songsBox => Hive.box<Song>(songsBoxName);
  static Box<Playlist> get _playlistsBox => Hive.box<Playlist>(playlistsBoxName);
  static Box<UserData> get _userDataBox => Hive.box<UserData>(userDataBoxName);

  static ValueListenable<Box<Song>> songsListenable() => _songsBox.listenable();

  static ValueListenable<Box<Playlist>> playlistsListenable() => _playlistsBox.listenable();

  static List<Song> getAllSongs() {
    return _songsBox.values.toList(growable: false);
  }

  static Song? getSongById(String songId) {
    return _songsBox.get(songId);
  }

  static Future<void> saveSongs(List<Song> songs) async {
    final entries = <String, Song>{for (final song in songs) song.id: song};
    await _songsBox.putAll(entries);
  }

  static Future<void> saveSong(Song song) async {
    await _songsBox.put(song.id, song);
  }

  static Future<void> removeSong(String songId) async {
    await _songsBox.delete(songId);
  }

  static List<Playlist> getAllPlaylists() {
    final playlists = _playlistsBox.values.toList(growable: false);
    playlists.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return playlists;
  }

  static Map<String, List<String>> getPlaylistsSongMap() {
    return {
      for (final playlist in getAllPlaylists())
        playlist.id: List<String>.from(playlist.songIds),
    };
  }

  static Future<Playlist> createPlaylist(String name) async {
    final now = DateTime.now();
    final id = 'playlist_${now.microsecondsSinceEpoch}';
    final playlist = Playlist(
      id: id,
      name: name,
      songIds: const [],
      createdAt: now,
    );
    await _playlistsBox.put(id, playlist);
    return playlist;
  }

  static Future<void> upsertPlaylist(Playlist playlist) async {
    await _playlistsBox.put(playlist.id, playlist);
  }

  static Future<bool> renamePlaylist({
    required String playlistId,
    required String newName,
  }) async {
    final current = _playlistsBox.get(playlistId);
    if (current == null) {
      return false;
    }
    await _playlistsBox.put(playlistId, current.copyWith(name: newName));
    return true;
  }

  static Future<bool> deletePlaylist(String playlistId) async {
    if (!_playlistsBox.containsKey(playlistId)) {
      return false;
    }
    await _playlistsBox.delete(playlistId);
    return true;
  }

  static Future<bool> addSongToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final current = _playlistsBox.get(playlistId);
    if (current == null) {
      return false;
    }

    final updatedSongIds = List<String>.from(current.songIds);
    if (!updatedSongIds.contains(songId)) {
      updatedSongIds.add(songId);
      await _playlistsBox.put(
        playlistId,
        current.copyWith(songIds: updatedSongIds),
      );
    }
    return true;
  }

  static Future<bool> removeSongFromPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    final current = _playlistsBox.get(playlistId);
    if (current == null) {
      return false;
    }

    final updatedSongIds = List<String>.from(current.songIds)
      ..removeWhere((id) => id == songId);
    await _playlistsBox.put(
      playlistId,
      current.copyWith(songIds: updatedSongIds),
    );
    return true;
  }

  static Future<bool> reorderPlaylistSongs({
    required String playlistId,
    required int oldIndex,
    required int newIndex,
  }) async {
    final current = _playlistsBox.get(playlistId);
    if (current == null) {
      return false;
    }

    final updatedSongIds = List<String>.from(current.songIds);
    if (updatedSongIds.isEmpty ||
        oldIndex < 0 ||
        oldIndex >= updatedSongIds.length ||
        newIndex < 0 ||
        newIndex >= updatedSongIds.length) {
      return false;
    }

    final songId = updatedSongIds.removeAt(oldIndex);
    updatedSongIds.insert(newIndex, songId);
    await _playlistsBox.put(
      playlistId,
      current.copyWith(songIds: updatedSongIds),
    );
    return true;
  }

  static UserData getUserData() {
    final userData = _userDataBox.get(userDataKey);
    return userData ?? const UserData(favorites: []);
  }

  static Future<void> saveUserData(UserData userData) async {
    await _userDataBox.put(userDataKey, userData);
  }

  static Future<void> saveFavorites(List<String> favorites) async {
    final current = getUserData();
    await saveUserData(
      current.copyWith(favorites: favorites),
    );
  }

  static Future<void> saveLastPlayback({
    required String songId,
    required Duration position,
  }) async {
    final current = getUserData();
    await saveUserData(
      current.copyWith(
        lastPlayedSong: songId,
        lastPosition: position,
      ),
    );
  }

  // ── Settings (small key/value store) ──────────────────────────────────────

  static Box<dynamic> get _settingsBox => Hive.box<dynamic>(settingsBoxName);

  static T? readSetting<T>(String key) {
    final v = _settingsBox.get(key);
    return v is T ? v : null;
  }

  static Future<void> writeSetting(String key, Object? value) =>
      value == null ? _settingsBox.delete(key) : _settingsBox.put(key, value);

  // ── Playback history ──────────────────────────────────────────────────────

  static Box<Map<dynamic, dynamic>> get _historyBox =>
      Hive.box<Map<dynamic, dynamic>>(historyBoxName);

  static ValueListenable<Box<Map<dynamic, dynamic>>> historyListenable() =>
      _historyBox.listenable();

  /// Appends a play event (most recent last) and trims to [historyLimit].
  static Future<void> addHistory(String songId, DateTime playedAt) async {
    await _historyBox.add({'id': songId, 'at': playedAt.millisecondsSinceEpoch});
    final overflow = _historyBox.length - historyLimit;
    if (overflow > 0) {
      await _historyBox.deleteAll(_historyBox.keys.take(overflow).toList());
    }
  }

  /// Most-recent-first list of (song, playedAt). Skips songs no longer stored.
  static List<({Song song, DateTime playedAt})> getHistory({int? limit}) {
    final out = <({Song song, DateTime playedAt})>[];
    for (final e in _historyBox.values.toList().reversed) {
      final song = _songsBox.get(e['id']);
      final at = e['at'];
      if (song == null || at is! int) continue;
      out.add((song: song, playedAt: DateTime.fromMillisecondsSinceEpoch(at)));
      if (limit != null && out.length >= limit) break;
    }
    return out;
  }

  /// Distinct recently played songs, most recent first.
  static List<Song> getRecentlyPlayed({int limit = 20}) {
    final seen = <String>{};
    final out = <Song>[];
    for (final e in getHistory()) {
      if (seen.add(e.song.id)) out.add(e.song);
      if (out.length >= limit) break;
    }
    return out;
  }

  static Future<void> clearHistory() => _historyBox.clear();

  // ── Match memory ──────────────────────────────────────────────────────────

  static String? lookupMatch(String key) =>
      Hive.box<String>(matchMemoryBoxName).get(key);

  static Future<void> rememberMatch(String key, String songId) =>
      Hive.box<String>(matchMemoryBoxName).put(key, songId);

  /// Erases everything stored on this device (Settings → Delete my data).
  static Future<void> clearAllUserData() async {
    await Future.wait([
      _songsBox.clear(),
      _playlistsBox.clear(),
      _historyBox.clear(),
      _settingsBox.clear(),
      Hive.box<String>(matchMemoryBoxName).clear(),
    ]);
    await _userDataBox.put(userDataKey, const UserData(favorites: []));
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SongAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PlaylistAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(UserDataAdapter());
    }
  }
}
