import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persisted entitlement. Stored in the platform keystore (Keychain /
/// Android Keystore-backed EncryptedSharedPreferences / WebCrypto on web).
class StoredEntitlement {
  const StoredEntitlement({
    required this.kind,
    this.licenseKey = '',
    this.purchaseId = '',
    this.productId = '',
  });

  /// `store` (App Store / Google Play) or `key` (signed licence key).
  final String kind;
  final String licenseKey;
  final String purchaseId;
  final String productId;

  Map<String, String> toJson() => {
        'kind': kind,
        'licenseKey': licenseKey,
        'purchaseId': purchaseId,
        'productId': productId,
      };

  static StoredEntitlement? fromJson(Object? j) {
    if (j is! Map || j['kind'] is! String) return null;
    return StoredEntitlement(
      kind: j['kind'] as String,
      licenseKey: (j['licenseKey'] as String?) ?? '',
      purchaseId: (j['purchaseId'] as String?) ?? '',
      productId: (j['productId'] as String?) ?? '',
    );
  }
}

abstract class LicenseStore {
  Future<StoredEntitlement?> read();
  Future<void> write(StoredEntitlement entitlement);
  Future<void> clear();
}

class SecureLicenseStore implements LicenseStore {
  SecureLicenseStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'aurora.entitlement.v1';

  @override
  Future<StoredEntitlement?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      return StoredEntitlement.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoredEntitlement e) =>
      _storage.write(key: _key, value: jsonEncode(e.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryLicenseStore implements LicenseStore {
  StoredEntitlement? value;
  @override
  Future<StoredEntitlement?> read() async => value;
  @override
  Future<void> write(StoredEntitlement e) async => value = e;
  @override
  Future<void> clear() async => value = null;
}
