import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Verifies the `Stripe-Signature` header of a webhook request
/// (https://docs.stripe.com/webhooks#verify-manually): HMAC-SHA256 over
/// `timestamp.rawBody` with the endpoint secret, compared in constant
/// time, with a replay window.
bool verifyStripeSignature({
  required String payload,
  required String header,
  required String secret,
  Duration tolerance = const Duration(minutes: 5),
  DateTime? now,
}) {
  if (secret.isEmpty || header.isEmpty) return false;
  int? timestamp;
  final signatures = <String>[];
  for (final part in header.split(',')) {
    final kv = part.split('=');
    if (kv.length != 2) continue;
    if (kv[0].trim() == 't') timestamp = int.tryParse(kv[1].trim());
    if (kv[0].trim() == 'v1') signatures.add(kv[1].trim());
  }
  if (timestamp == null || signatures.isEmpty) return false;
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if ((current - timestamp).abs() > tolerance.inSeconds) return false;

  final expected = Hmac(sha256, utf8.encode(secret))
      .convert(utf8.encode('$timestamp.$payload'))
      .toString();
  return signatures.any((s) => _constantTimeEquals(s, expected));
}

String signStripePayload(String payload, String secret, int timestamp) {
  final mac = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode('$timestamp.$payload'));
  return 't=$timestamp,v1=$mac';
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
