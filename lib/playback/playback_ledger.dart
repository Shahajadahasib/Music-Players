import '../services/hive_storage_service.dart';

/// Records which recordings have **actually played** in this app (the player
/// reported ready + playing). Only these are labelled "Full track"; a stream
/// that merely answered an HTTP check is "Not verified".
abstract class PlaybackLedger {
  bool hasPlayed(String songId);
  Future<void> recordPlayed(String songId);

  /// The player failed this recording (decode error, expired URL…).
  Future<void> recordFailed(String songId);
}

class MemoryPlaybackLedger implements PlaybackLedger {
  final Set<String> _played = {};
  @override
  bool hasPlayed(String songId) => _played.contains(songId);
  @override
  Future<void> recordPlayed(String songId) async => _played.add(songId);
  @override
  Future<void> recordFailed(String songId) async => _played.remove(songId);
}

class HivePlaybackLedger implements PlaybackLedger {
  @override
  bool hasPlayed(String songId) {
    try {
      return HiveStorageService.playedAt(songId) != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> recordPlayed(String songId) async {
    try {
      await HiveStorageService.markPlayed(songId, DateTime.now());
    } catch (_) {}
  }

  @override
  Future<void> recordFailed(String songId) async {
    try {
      await HiveStorageService.unmarkPlayed(songId);
    } catch (_) {}
  }
}
