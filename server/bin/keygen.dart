import 'dart:convert';
import 'dart:math';

import 'package:aurora_license_server/license_codec.dart';

/// Generates a new licence signing key.
///   dart run bin/keygen.dart
/// Store LICENSE_SIGNING_KEY in your secret manager (never in git); put
/// LICENSE_PUBLIC_KEY in the app build config.
Future<void> main() async {
  final r = Random.secure();
  final seed = base64.encode(List.generate(32, (_) => r.nextInt(256)));
  final codec = await LicenseCodec.fromSeed(seed);
  print('LICENSE_SIGNING_KEY=$seed');
  print('LICENSE_PUBLIC_KEY=${await codec.publicKeyBase64()}');
}
