import 'dart:convert';
import 'dart:io';

/// Minimal durable storage for issued licences, keyed by Stripe checkout
/// session id. A JSON file is enough for a single small instance; swap for a
/// database (Postgres, Firestore, …) when running more than one replica.
class LicenseStore {
  LicenseStore(this._file);

  final File _file;
  Map<String, dynamic> _data = {'sessions': <String, dynamic>{}, 'revoked': <String>[]};

  static Future<LicenseStore> open(String dir) async {
    final d = Directory(dir);
    await d.create(recursive: true);
    final store = LicenseStore(File('${d.path}/licenses.json'));
    if (await store._file.exists()) {
      store._data = jsonDecode(await store._file.readAsString()) as Map<String, dynamic>;
    }
    return store;
  }

  /// In-memory store for tests.
  factory LicenseStore.memory() => _MemoryLicenseStore();

  Map<String, dynamic> get _sessions => _data['sessions'] as Map<String, dynamic>;

  String? keyForSession(String sessionId) =>
      (_sessions[sessionId] as Map<String, dynamic>?)?['key'] as String?;

  Future<void> saveSession(String sessionId, String key, String licenseId) async {
    _sessions[sessionId] = {
      'key': key,
      'lid': licenseId,
      'at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persist();
  }

  List<String> get revoked => List<String>.from(_data['revoked'] as List);

  Future<void> revoke(String licenseId) async {
    (_data['revoked'] as List).add(licenseId);
    await _persist();
  }

  Future<void> _persist() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data));
    await tmp.rename(_file.path); // atomic replace
  }
}

class _MemoryLicenseStore extends LicenseStore {
  _MemoryLicenseStore() : super(File('/dev/null'));
  @override
  Future<void> _persist() async {}
}
