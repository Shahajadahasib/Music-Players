import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/song.dart';
import 'audio_service.dart';
import 'fs/dir_helper.dart';

/// Imports audio files the user owns from their device.
///
/// * Android / iOS: the picked file is copied into the app's private
///   documents folder (`local_music/`) so it survives restarts and works in
///   the background. Stored as `local-file:<name>` (relative), because iOS
///   changes the absolute container path between app updates.
/// * Web: browsers do not allow persistent file access; the file is played
///   from an in-memory blob URL for the current session only.
///
/// Title/artist are derived from the file name (`Artist - Title.mp3`); ID3
/// tag parsing is listed as a remaining limitation in docs/LIMITATIONS.md.
class LocalMusicService {
  const LocalMusicService();

  static const _dirName = 'local_music';

  /// Call once at startup (mobile) so [AudioService] can resolve local files.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      AudioService.localMusicDir = '${docs.path}/$_dirName';
    } catch (_) {
      // Unsupported platform (tests) — local playback simply unavailable.
    }
  }

  Future<List<Song>> pickAndImport() async {
    final files = await FilePicker.pickFiles(
      type: FileType.audio,
      dialogTitle: 'Add music from this device',
    );
    final out = <Song>[];
    for (final f in files) {
      final song = await _import(f);
      if (song != null) out.add(song);
    }
    return out;
  }

  Future<Song?> _import(PlatformFile file) async {
    final name = file.name;
    final meta = parseFileName(name);
    if (kIsWeb) {
      final id = 'local:web:$name:${file.lengthSync() ?? 0}';
      AudioService.webLocalUris[id] = file.uri;
      return Song(
        id: id,
        title: meta.title,
        artist: meta.artist,
        album: '',
        audioUrl: '',
        coverUrl: '',
        sourceId: 'local',
        playability: Playability.local,
      );
    }
    final dir = AudioService.localMusicDir;
    if (dir == null) return null;
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    await _ensureDir(dir);
    await file.xFile.saveTo('$dir/$safeName');
    return Song(
      id: 'local:$safeName',
      title: meta.title,
      artist: meta.artist,
      album: '',
      audioUrl: 'local-file:$safeName',
      coverUrl: '',
      sourceId: 'local',
      playability: Playability.local,
    );
  }

  Future<void> _ensureDir(String path) => XFileHelper.ensureDirectory(path);

  /// "Artist - Title.mp3" → (artist, title); otherwise title = file name.
  static ({String title, String artist}) parseFileName(String fileName) {
    var base = fileName;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base.replaceAll('_', ' ').trim();
    final parts = base.split(' - ');
    if (parts.length >= 2) {
      return (
        artist: parts.first.trim(),
        title: parts.sublist(1).join(' - ').trim(),
      );
    }
    return (title: base, artist: '');
  }
}
