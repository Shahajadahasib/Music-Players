import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

/// Result of asking a store whether a purchase is genuine.
enum StoreVerdict { valid, invalid, unavailable }

abstract class StoreVerifier {
  Future<StoreVerdict> verify({
    required String productId,
    required String purchaseId,
    required String verificationData,
  });
}

/// Google Play Developer API — purchases.products.get.
/// https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.products/get
///
/// Needs a service account with "View financial data" access in Play Console.
class GooglePlayVerifier implements StoreVerifier {
  GooglePlayVerifier({required this.packageName, required String serviceAccountJson, http.Client? client})
      : _credentials = ServiceAccountCredentials.fromJson(serviceAccountJson),
        _base = client ?? http.Client();

  final String packageName;
  final ServiceAccountCredentials _credentials;
  final http.Client _base;
  AutoRefreshingAuthClient? _client;

  @override
  Future<StoreVerdict> verify({
    required String productId,
    required String purchaseId,
    required String verificationData, // the purchase token
  }) async {
    if (verificationData.isEmpty || verificationData.length > 4096) return StoreVerdict.invalid;
    try {
      _client ??= await clientViaServiceAccount(
        _credentials,
        ['https://www.googleapis.com/auth/androidpublisher'],
        baseClient: _base,
      );
      final uri = Uri.https(
        'androidpublisher.googleapis.com',
        '/androidpublisher/v3/applications/$packageName/purchases/products/$productId/tokens/$verificationData',
      );
      final res = await _client!.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 404 || res.statusCode == 400 || res.statusCode == 410) {
        return StoreVerdict.invalid;
      }
      if (res.statusCode != 200) return StoreVerdict.unavailable;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // purchaseState: 0 = purchased, 1 = cancelled, 2 = pending.
      return body['purchaseState'] == 0 ? StoreVerdict.valid : StoreVerdict.invalid;
    } catch (_) {
      return StoreVerdict.unavailable;
    }
  }
}

/// App Store Server API — Get Transaction Info.
/// https://developer.apple.com/documentation/appstoreserverapi/get_transaction_info
///
/// The request is authenticated with an ES256 JWT made from an In-App
/// Purchase key (.p8) from App Store Connect. The response arrives directly
/// from Apple over TLS; the JWS payload is decoded and checked for bundle id,
/// product id and revocation.
class AppStoreVerifier implements StoreVerifier {
  AppStoreVerifier({
    required this.issuerId,
    required this.keyId,
    required this.privateKeyPem,
    required this.bundleId,
    this.sandbox = false,
    http.Client? client,
  }) : _http = client ?? http.Client();

  final String issuerId;
  final String keyId;
  final String privateKeyPem;
  final String bundleId;
  final bool sandbox;
  final http.Client _http;

  String _token() => JWT(
        {'bid': bundleId},
        issuer: issuerId,
        audience: Audience.one('appstoreconnect-v1'),
        header: {'kid': keyId, 'typ': 'JWT'},
      ).sign(ECPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.ES256, expiresIn: const Duration(minutes: 5));

  @override
  Future<StoreVerdict> verify({
    required String productId,
    required String purchaseId, // transaction id
    required String verificationData,
  }) async {
    if (!RegExp(r'^\d{1,32}$').hasMatch(purchaseId)) return StoreVerdict.invalid;
    final host = sandbox ? 'api.storekit-sandbox.itunes.apple.com' : 'api.storekit.itunes.apple.com';
    try {
      final res = await _http.get(
        Uri.https(host, '/inApps/v1/transactions/$purchaseId'),
        headers: {'Authorization': 'Bearer ${_token()}'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 404 || res.statusCode == 400) return StoreVerdict.invalid;
      if (res.statusCode != 200) return StoreVerdict.unavailable;
      final jws = (jsonDecode(res.body) as Map<String, dynamic>)['signedTransactionInfo'] as String?;
      final parts = jws?.split('.') ?? const [];
      if (parts.length != 3) return StoreVerdict.unavailable;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final ok = payload['bundleId'] == bundleId &&
          payload['productId'] == productId &&
          payload['revocationDate'] == null;
      return ok ? StoreVerdict.valid : StoreVerdict.invalid;
    } catch (_) {
      return StoreVerdict.unavailable;
    }
  }
}
