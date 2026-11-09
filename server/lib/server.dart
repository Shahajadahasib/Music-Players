import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'license_codec.dart';
import 'license_store.dart';
import 'store_verifiers.dart';
import 'stripe.dart';

/// HTTP API:
///
///   GET  /healthz
///   POST /v1/licenses/verify-store        app → server (store purchase check)
///   POST /v1/stripe/webhook               Stripe → server (issue web licence)
///   GET  `/v1/licenses/checkout/{session}`  success page → server (fetch key)
///   GET  /v1/licenses/revoked             app (optional) → revoked licence ids
class LicenseServer {
  LicenseServer({
    required this.codec,
    required this.store,
    required this.productId,
    required this.stripeWebhookSecret,
    this.googlePlay,
    this.appStore,
    this.allowedOrigin = '',
  });

  final LicenseCodec codec;
  final LicenseStore store;
  final String productId;
  final String stripeWebhookSecret;
  final StoreVerifier? googlePlay;
  final StoreVerifier? appStore;
  final String allowedOrigin;

  final _rand = Random.secure();

  Handler get handler {
    final r = Router()
      ..get('/healthz', (Request _) => Response.ok('ok'))
      ..post('/v1/licenses/verify-store', _verifyStore)
      ..post('/v1/stripe/webhook', _stripeWebhook)
      ..get('/v1/licenses/checkout/<session>', _checkoutKey)
      ..get('/v1/licenses/revoked', (Request _) => _json(200, {'revoked': store.revoked}));
    return const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_limitBody(64 * 1024))
        .addHandler(r.call);
  }

  Future<Response> _verifyStore(Request req) async {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _json(400, {'error': 'invalid json'});
    }
    final platform = body['platform'];
    final product = body['productId'];
    final purchaseId = body['purchaseId'];
    final data = body['verificationData'];
    if (platform is! String || product is! String || purchaseId is! String || data is! String) {
      return _json(400, {'error': 'missing fields'});
    }
    if (product != productId) return _json(200, {'valid': false});
    final verifier = switch (platform) {
      'android' => googlePlay,
      'ios' => appStore,
      _ => null,
    };
    if (verifier == null) return _json(503, {'error': 'store not configured'});
    final verdict = await verifier.verify(
      productId: product,
      purchaseId: purchaseId,
      verificationData: data,
    );
    return switch (verdict) {
      StoreVerdict.valid => _json(200, {'valid': true}),
      StoreVerdict.invalid => _json(200, {'valid': false}),
      // 503 → the app accepts provisionally and re-checks later.
      StoreVerdict.unavailable => _json(503, {'error': 'store unavailable'}),
    };
  }

  Future<Response> _stripeWebhook(Request req) async {
    final payload = await req.readAsString();
    final ok = verifyStripeSignature(
      payload: payload,
      header: req.headers['stripe-signature'] ?? '',
      secret: stripeWebhookSecret,
    );
    if (!ok) return _json(400, {'error': 'bad signature'});
    final event = jsonDecode(payload) as Map<String, dynamic>;
    if (event['type'] != 'checkout.session.completed') {
      return _json(200, {'ignored': event['type']});
    }
    final session = (event['data'] as Map)['object'] as Map<String, dynamic>;
    final sessionId = session['id'] as String?;
    if (sessionId == null) return _json(400, {'error': 'no session'});
    if (session['payment_status'] != 'paid') return _json(200, {'pending': true});
    if (store.keyForSession(sessionId) != null) return _json(200, {'duplicate': true});

    final email = ((session['customer_details'] as Map?)?['email'] as String?)?.toLowerCase().trim() ?? '';
    final licenseId = 'lic_${_randomId()}';
    final key = await codec.issue(
      licenseId: licenseId,
      product: productId,
      // Hashed, so a key never carries the customer's e-mail address.
      customerRef: email.isEmpty ? '' : sha256.convert(utf8.encode(email)).toString().substring(0, 16),
    );
    await store.saveSession(sessionId, key, licenseId);
    return _json(200, {'issued': true});
  }

  Response _checkoutKey(Request req, String session) {
    if (!RegExp(r'^cs_[A-Za-z0-9_]{8,200}$').hasMatch(session)) {
      return _json(400, {'error': 'invalid session'});
    }
    final key = store.keyForSession(session);
    if (key == null) {
      // Webhook may not have arrived yet; the success page should poll.
      return _json(404, {'error': 'not ready'});
    }
    return _json(200, {'licenseKey': key});
  }

  String _randomId() =>
      List.generate(16, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  Middleware _cors() => (inner) => (req) async {
        final headers = {
          if (allowedOrigin.isNotEmpty) 'access-control-allow-origin': allowedOrigin,
          'access-control-allow-methods': 'GET, POST, OPTIONS',
          'access-control-allow-headers': 'content-type',
        };
        if (req.method == 'OPTIONS') return Response.ok('', headers: headers);
        final res = await inner(req);
        return res.change(headers: headers);
      };

  Middleware _limitBody(int max) => (inner) => (req) {
        final len = req.contentLength;
        if (len != null && len > max) return _json(413, {'error': 'too large'});
        return inner(req);
      };

  static Response _json(int status, Object body) => Response(
        status,
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      );
}
