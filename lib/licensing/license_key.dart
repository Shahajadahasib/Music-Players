import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Offline-verifiable licence key:
///
///   `AURORA1.<base64url(payload JSON)>.<base64url(Ed25519 signature)>`
///
/// The licence server signs the payload with its **private** key; the app
/// only embeds the **public** key, which can verify but never create keys.
/// Verification needs no network, so paying users are never locked out by a
/// server outage.
class LicensePayload {
  const LicensePayload({
    required this.licenseId,
    required this.product,
    required this.issuedAt,
    this.customerRef = '',
  });

  final String licenseId;
  final String product;
  final DateTime issuedAt;

  /// Opaque customer reference (e.g. hashed e-mail). Never the raw e-mail.
  final String customerRef;

  Map<String, Object> toJson() => {
        'lid': licenseId,
        'prd': product,
        'iat': issuedAt.millisecondsSinceEpoch ~/ 1000,
        if (customerRef.isNotEmpty) 'cus': customerRef,
      };

  static LicensePayload? fromJson(Object? json) {
    if (json is! Map) return null;
    final lid = json['lid'], prd = json['prd'], iat = json['iat'];
    if (lid is! String || prd is! String || iat is! int) return null;
    if (lid.isEmpty || lid.length > 128 || prd.isEmpty || prd.length > 64) return null;
    return LicensePayload(
      licenseId: lid,
      product: prd,
      issuedAt: DateTime.fromMillisecondsSinceEpoch(iat * 1000, isUtc: true),
      customerRef: json['cus'] is String ? json['cus'] as String : '',
    );
  }
}

class LicenseKeyCodec {
  static const String prefix = 'AURORA1';
  static final _ed = Ed25519();

  /// Verifies [key] against [publicKeyBase64]. Returns the payload when the
  /// signature is valid and the product matches, otherwise null.
  static Future<LicensePayload?> verify(
    String key, {
    required String publicKeyBase64,
    String? expectedProduct,
  }) async {
    final cleaned = key.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.length > 2048 || publicKeyBase64.isEmpty) return null;
    final parts = cleaned.split('.');
    if (parts.length != 3 || parts[0] != prefix) return null;
    try {
      final payloadBytes = _b64d(parts[1]);
      final sig = _b64d(parts[2]);
      final pk = base64.decode(publicKeyBase64);
      if (sig.length != 64 || pk.length != 32) return null;
      final ok = await _ed.verify(
        utf8.encode('$prefix.${parts[1]}'),
        signature: Signature(
          sig,
          publicKey: SimplePublicKey(pk, type: KeyPairType.ed25519),
        ),
      );
      if (!ok) return null;
      final payload = LicensePayload.fromJson(jsonDecode(utf8.decode(payloadBytes)));
      if (payload == null) return null;
      if (expectedProduct != null && payload.product != expectedProduct) return null;
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Signs a payload. Used by the licence server / tests — the app never has
  /// the private key.
  static Future<String> sign(LicensePayload payload, SimpleKeyPair keyPair) async {
    final body = _b64e(utf8.encode(jsonEncode(payload.toJson())));
    final sig = await _ed.sign(utf8.encode('$prefix.$body'), keyPair: keyPair);
    return '$prefix.$body.${_b64e(sig.bytes)}';
  }

  static String _b64e(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _b64d(String s) => base64Url.decode(base64Url.normalize(s));
}
