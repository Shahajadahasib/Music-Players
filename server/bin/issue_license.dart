import 'dart:io';
import 'dart:math';

import 'package:aurora_license_server/license_codec.dart';

/// Issues a licence key manually (support cases, press, giveaways).
///   LICENSE_SIGNING_KEY=... dart run bin/issue_license.dart [product]
Future<void> main(List<String> args) async {
  final seed = Platform.environment['LICENSE_SIGNING_KEY'];
  if (seed == null || seed.isEmpty) {
    stderr.writeln('Set LICENSE_SIGNING_KEY');
    exit(64);
  }
  final codec = await LicenseCodec.fromSeed(seed);
  final r = Random.secure();
  final id = 'lic_${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
  print(await codec.issue(licenseId: id, product: args.isEmpty ? 'premium_lifetime' : args.first));
}
