import 'dart:convert';

import 'package:aurora_license_server/license_codec.dart';
import 'package:aurora_license_server/license_store.dart';
import 'package:aurora_license_server/server.dart';
import 'package:aurora_license_server/store_verifiers.dart';
import 'package:aurora_license_server/stripe.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// TEST-ONLY key material (32 bytes of 0x01). Never use in production.
const testSeed = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=';
const testPublicKey = 'iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w=';
const testVector = 'AURORA1.eyJsaWQiOiJsaWNfdGVzdF92ZWN0b3IiLCJwcmQiOiJwcmVtaXVtX2xpZmV0aW1lIiwiaWF0IjoxNzY3MjI1NjAwfQ'
    '.vhfV3kds2FzsG3Xhwteb8uQhbafQZebM_XKeRng_IdaVpdIWT9lVrn8FCes9OqNiJhfz82EUfkrOo6czU7ObDg';
const secret = 'whsec_test';

class FakeVerifier implements StoreVerifier {
  FakeVerifier(this.verdict);
  StoreVerdict verdict;
  String? lastToken;
  @override
  Future<StoreVerdict> verify({required String productId, required String purchaseId, required String verificationData}) async {
    lastToken = verificationData;
    return verdict;
  }
}

void main() {
  late LicenseCodec codec;
  late LicenseServer server;
  late FakeVerifier google;

  setUp(() async {
    codec = await LicenseCodec.fromSeed(testSeed);
    google = FakeVerifier(StoreVerdict.valid);
    server = LicenseServer(
      codec: codec,
      store: LicenseStore.memory(),
      productId: 'premium_lifetime',
      stripeWebhookSecret: secret,
      googlePlay: google,
    );
  });

  Future<(int, Map<String, dynamic>)> call(String method, String path, {Object? body, Map<String, String>? headers}) async {
    final res = await server.handler(Request(method, Uri.parse('http://localhost$path'),
        body: body == null ? null : (body is String ? body : jsonEncode(body)), headers: headers));
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty || text == 'ok' ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
  }

  group('licence codec', () {
    test('wire format is pinned (shared test vector with the app)', () async {
      expect(await codec.publicKeyBase64(), testPublicKey);
      final key = await codec.issue(licenseId: 'lic_test_vector', product: 'premium_lifetime', issuedAt: DateTime.utc(2026, 1, 1));
      expect(key, testVector);
      expect((await codec.verify(key))?['lid'], 'lic_test_vector');
    });

    test('rejects a bad seed', () {
      expect(LicenseCodec.fromSeed(base64.encode([1, 2, 3])), throwsArgumentError);
    });
  });

  group('stripe signature', () {
    test('accepts valid, rejects tampered, stale and missing', () {
      final now = DateTime.utc(2026, 5, 1);
      final ts = now.millisecondsSinceEpoch ~/ 1000;
      final header = signStripePayload('{"a":1}', secret, ts);
      expect(verifyStripeSignature(payload: '{"a":1}', header: header, secret: secret, now: now), isTrue);
      expect(verifyStripeSignature(payload: '{"a":2}', header: header, secret: secret, now: now), isFalse);
      expect(verifyStripeSignature(payload: '{"a":1}', header: header, secret: 'other', now: now), isFalse);
      expect(verifyStripeSignature(payload: '{"a":1}', header: header, secret: secret, now: now.add(const Duration(minutes: 10))), isFalse);
      expect(verifyStripeSignature(payload: '{"a":1}', header: '', secret: secret, now: now), isFalse);
    });
  });

  group('stripe checkout → licence key', () {
    String event(String type, {String status = 'paid'}) => jsonEncode({
          'type': type,
          'data': {
            'object': {'id': 'cs_test_abcdefgh123', 'payment_status': status, 'customer_details': {'email': 'Buyer@Example.com'}},
          },
        });
    Map<String, String> sig(String payload) =>
        {'stripe-signature': signStripePayload(payload, secret, DateTime.now().millisecondsSinceEpoch ~/ 1000)};

    test('issues a verifiable key once, retrievable by session id', () async {
      var (code, _) = await call('GET', '/v1/licenses/checkout/cs_test_abcdefgh123');
      expect(code, 404);

      final payload = event('checkout.session.completed');
      final (c1, b1) = await call('POST', '/v1/stripe/webhook', body: payload, headers: sig(payload));
      expect(c1, 200);
      expect(b1['issued'], isTrue);
      final (c2, b2) = await call('POST', '/v1/stripe/webhook', body: payload, headers: sig(payload));
      expect(c2, 200);
      expect(b2['duplicate'], isTrue);

      final (c3, b3) = await call('GET', '/v1/licenses/checkout/cs_test_abcdefgh123');
      expect(c3, 200);
      final claims = await codec.verify(b3['licenseKey'] as String);
      expect(claims?['prd'], 'premium_lifetime');
      expect(claims?['cus'], isNot(contains('example')), reason: 'e-mail must be hashed');
    });

    test('rejects unsigned webhooks and ignores unpaid / other events', () async {
      final payload = event('checkout.session.completed');
      expect((await call('POST', '/v1/stripe/webhook', body: payload)).$1, 400);
      final unpaid = event('checkout.session.completed', status: 'unpaid');
      expect((await call('POST', '/v1/stripe/webhook', body: unpaid, headers: sig(unpaid))).$2['pending'], isTrue);
      final other = event('invoice.paid');
      expect((await call('POST', '/v1/stripe/webhook', body: other, headers: sig(other))).$2['ignored'], 'invoice.paid');
    });

    test('validates session id format', () async {
      expect((await call('GET', '/v1/licenses/checkout/..%2Fetc')).$1, 400);
    });
  });

  group('store verification', () {
    Map<String, String> body(String platform, {String product = 'premium_lifetime'}) =>
        {'platform': platform, 'productId': product, 'purchaseId': 'GPA.1', 'verificationData': 'token'};

    test('maps store verdicts to app responses', () async {
      expect((await call('POST', '/v1/licenses/verify-store', body: body('android'))).$2['valid'], isTrue);
      expect(google.lastToken, 'token');
      google.verdict = StoreVerdict.invalid;
      expect((await call('POST', '/v1/licenses/verify-store', body: body('android'))).$2['valid'], isFalse);
      google.verdict = StoreVerdict.unavailable;
      expect((await call('POST', '/v1/licenses/verify-store', body: body('android'))).$1, 503);
    });

    test('wrong product is never valid; unknown store is 503; bad input is 400', () async {
      expect((await call('POST', '/v1/licenses/verify-store', body: body('android', product: 'x'))).$2['valid'], isFalse);
      expect((await call('POST', '/v1/licenses/verify-store', body: body('ios'))).$1, 503);
      expect((await call('POST', '/v1/licenses/verify-store', body: 'not json')).$1, 400);
      expect((await call('POST', '/v1/licenses/verify-store', body: {'platform': 'android'})).$1, 400);
    });
  });

  test('health check', () async {
    expect((await call('GET', '/healthz')).$1, 200);
  });
}
