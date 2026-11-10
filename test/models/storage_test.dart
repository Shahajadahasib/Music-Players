import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:music_player_app/models/adapters/song_adapter.dart';
import 'package:music_player_app/models/song.dart';
import 'package:music_player_app/services/hive_storage_service.dart';
import 'package:music_player_app/services/local_music_service.dart';

/// Writes songs exactly like v1.0 of the app did (no provider fields).
class LegacySongAdapter extends TypeAdapter<Song> {
  @override
  final int typeId = 0;
  @override
  Song read(BinaryReader reader) => throw UnimplementedError();
  @override
  void write(BinaryWriter w, Song s) {
    w.writeString(s.id);
    w.writeString(s.title);
    w.writeString(s.artist);
    w.writeString(s.album);
    w.writeString(s.audioUrl);
    w.writeString(s.coverUrl);
    w.writeBool(s.duration != null);
    if (s.duration != null) w.writeInt(s.duration!.inMilliseconds);
  }
}

void main() {
  test('SongAdapter reads libraries saved by v1.0 and round-trips v2', () async {
    final dir = await Directory.systemTemp.createTemp('song_adapter_');
    Hive.init(dir.path);
    Hive.registerAdapter(LegacySongAdapter());
    var box = await Hive.openBox<Song>('legacy');
    await box.put('x', const Song(
      id: 'x', title: 'Old', artist: 'A', album: '', audioUrl: 'https://s.test/x', coverUrl: '',
      duration: Duration(seconds: 90),
    ));
    await box.close();
    Hive.resetAdapters();

    Hive.registerAdapter(SongAdapter());
    box = await Hive.openBox<Song>('legacy');
    final old = box.get('x')!;
    expect(old.title, 'Old');
    expect(old.duration, const Duration(seconds: 90));
    expect(old.sourceId, 'audius', reason: 'v1 only stored Audius tracks');
    expect(old.playability, Playability.full);

    const v2 = Song(
      id: 'archive:a', title: 'New', artist: 'B', album: 'C', audioUrl: '', coverUrl: '',
      sourceId: 'archive', playability: Playability.full, externalUrl: 'https://e.test',
      license: 'CC BY 4.0', artistId: '1', albumId: '2',
    );
    await box.put('y', v2);
    await box.close();
    box = await Hive.openBox<Song>('legacy');
    expect(box.get('y'), v2);
    await box.close();
    await Hive.close();
    Hive.resetAdapters();
  });

  group('HiveStorageService', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('storage_');
      await HiveStorageService.initialize(rootPath: dir.path);
    });

    Song s(String id) => Song(id: id, title: 't$id', artist: 'a', album: '', audioUrl: 'https://x.test', coverUrl: '');

    test('history is most-recent-first, de-duplicated for "recently played"', () async {
      await HiveStorageService.saveSongs([s('1'), s('2')]);
      await HiveStorageService.addHistory('1', DateTime(2026, 1, 1));
      await HiveStorageService.addHistory('2', DateTime(2026, 1, 2));
      await HiveStorageService.addHistory('1', DateTime(2026, 1, 3));
      expect(HiveStorageService.getHistory().map((e) => e.song.id), ['1', '2', '1']);
      expect(HiveStorageService.getRecentlyPlayed().map((e) => e.id), ['1', '2']);
    });

    test('history is capped', () async {
      await HiveStorageService.clearHistory();
      for (var i = 0; i < HiveStorageService.historyLimit + 20; i++) {
        await HiveStorageService.addHistory('1', DateTime(2026, 1, 1).add(Duration(minutes: i)));
      }
      expect(HiveStorageService.getHistory().length, HiveStorageService.historyLimit);
    });

    test('playlists: create, add, reorder, remove, rename, delete', () async {
      final pl = await HiveStorageService.createPlaylist('Mix');
      await HiveStorageService.addSongToPlaylist(playlistId: pl.id, songId: '1');
      await HiveStorageService.addSongToPlaylist(playlistId: pl.id, songId: '2');
      await HiveStorageService.addSongToPlaylist(playlistId: pl.id, songId: '2'); // no duplicates
      expect(HiveStorageService.getPlaylistsSongMap()[pl.id], ['1', '2']);
      await HiveStorageService.reorderPlaylistSongs(playlistId: pl.id, oldIndex: 1, newIndex: 0);
      expect(HiveStorageService.getPlaylistsSongMap()[pl.id], ['2', '1']);
      await HiveStorageService.removeSongFromPlaylist(playlistId: pl.id, songId: '2');
      await HiveStorageService.renamePlaylist(playlistId: pl.id, newName: 'Renamed');
      expect(HiveStorageService.getAllPlaylists().single.name, 'Renamed');
      expect(await HiveStorageService.deletePlaylist(pl.id), isTrue);
      expect(HiveStorageService.getAllPlaylists(), isEmpty);
    });

    test('settings and match memory persist; delete-all wipes everything', () async {
      await HiveStorageService.writeSetting('themeMode', 'light');
      await HiveStorageService.rememberMatch('k', 'v');
      await HiveStorageService.saveFavorites(['1']);
      expect(HiveStorageService.readSetting<String>('themeMode'), 'light');
      expect(HiveStorageService.lookupMatch('k'), 'v');
      await HiveStorageService.clearAllUserData();
      expect(HiveStorageService.readSetting<String>('themeMode'), isNull);
      expect(HiveStorageService.lookupMatch('k'), isNull);
      expect(HiveStorageService.getUserData().favorites, isEmpty);
      expect(HiveStorageService.getAllSongs(), isEmpty);
    });
  });

  test('local file names are parsed into artist / title', () {
    expect(LocalMusicService.parseFileName('Nina Simone - Feeling Good.mp3'), (artist: 'Nina Simone', title: 'Feeling Good'));
    expect(LocalMusicService.parseFileName('my_recording.m4a'), (title: 'my recording', artist: ''));
  });
}
