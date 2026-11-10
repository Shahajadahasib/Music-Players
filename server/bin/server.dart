import 'dart:io';

import 'package:aurora_license_server/license_codec.dart';
import 'package:aurora_license_server/license_store.dart';
import 'package:aurora_license_server/server.dart';
import 'package:aurora_license_server/store_verifiers.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Configuration comes only from environment variables / your secret manager.
Future<void> main() async {
  final env = Platform.environment;
  String req(String k) {
    final v = env[k];
    if (v == null || v.isEmpty) {
      stderr.writeln('Missing required environment variable $k');
      exit(64);
    }
    return v;
  }

  final codec = await LicenseCodec.fromSeed(req('LICENSE_SIGNING_KEY'));
  final store = await LicenseStore.open(env['DATA_DIR'] ?? 'data');

  StoreVerifier? google;
  if ((env['GOOGLE_SERVICE_ACCOUNT_JSON'] ?? '').isNotEmpty) {
    google = GooglePlayVerifier(
      packageName: req('ANDROID_PACKAGE_NAME'),
      serviceAccountJson: env['GOOGLE_SERVICE_ACCOUNT_JSON']!,
    );
  }
  StoreVerifier? apple;
  if ((env['APPLE_PRIVATE_KEY'] ?? '').isNotEmpty) {
    apple = AppStoreVerifier(
      issuerId: req('APPLE_ISSUER_ID'),
      keyId: req('APPLE_KEY_ID'),
      privateKeyPem: env['APPLE_PRIVATE_KEY']!,
      bundleId: req('APPLE_BUNDLE_ID'),
      sandbox: env['APPLE_ENVIRONMENT'] == 'sandbox',
    );
  }

  final server = LicenseServer(
    codec: codec,
    store: store,
    productId: env['PRODUCT_ID'] ?? 'premium_lifetime',
    stripeWebhookSecret: env['STRIPE_WEBHOOK_SECRET'] ?? '',
    googlePlay: google,
    appStore: apple,
    allowedOrigin: env['ALLOWED_ORIGIN'] ?? '',
  );
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(server.handler);
  final s = await io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Licence server on :${s.port} — public key ${await codec.publicKeyBase64()}');
}
