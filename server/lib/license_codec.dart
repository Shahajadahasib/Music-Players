import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Server copy of the app's licence-key format (lib/licensing/license_key.dart
/// in the app). Keep both in sync; test/license_codec_test.dart pins the
/// wire format.
///
///   `AURORA1.base64url(payload JSON).base64url(Ed25519 signature)`
class LicenseCodec {
  LicenseCodec(this._keyPair);

  static const prefix = 'AURORA1';
  final SimpleKeyPair _keyPair;
  static final _ed = Ed25519();

  /// [seedBase64] is the 32-byte Ed25519 private seed (see bin/keygen.dart).
  static Future<LicenseCodec> fromSeed(String seedBase64) async {
    final seed = base64.decode(seedBase64.trim());
    if (seed.length != 32) {
      throw ArgumentError('LICENSE_SIGNING_KEY must be a base64 32-byte seed');
    }
    return LicenseCodec(await _ed.newKeyPairFromSeed(seed));
  }

  Future<String> publicKeyBase64() async =>
      base64.encode((await _keyPair.extractPublicKey()).bytes);

  Future<String> issue({
    required String licenseId,
    required String product,
    String customerRef = '',
    DateTime? issuedAt,
  }) async {
    final payload = {
      'lid': licenseId,
      'prd': product,
      'iat': (issuedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000,
      if (customerRef.isNotEmpty) 'cus': customerRef,
    };
    final body = _b64(utf8.encode(jsonEncode(payload)));
    final sig = await _ed.sign(utf8.encode('$prefix.$body'), keyPair: _keyPair);
    return '$prefix.$body.${_b64(sig.bytes)}';
  }

  Future<Map<String, dynamic>?> verify(String key) async {
    final parts = key.trim().split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    try {
      final pk = await _keyPair.extractPublicKey();
      final ok = await _ed.verify(
        utf8.encode('$prefix.${parts[1]}'),
        signature: Signature(base64Url.decode(base64Url.normalize(parts[2])), publicKey: pk),
      );
      if (!ok) return null;
      return jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
}
