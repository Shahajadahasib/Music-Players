import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'license_key.dart';
import 'license_store.dart';
import 'store_gateway.dart';

enum LicenseTier { checking, free, premium }

/// Features unlocked by the one-time Premium purchase. Everything else —
/// search, streaming, queue, favourites, history — is free.
enum PremiumFeature { unlimitedPlaylists, localFiles, sleepTimer, themes }

class LicenseState extends Equatable {
  const LicenseState({
    this.tier = LicenseTier.checking,
    this.source = '',
    this.storeAvailable = false,
    this.product,
    this.purchasePending = false,
    this.message,
  });

  final LicenseTier tier;

  /// `paid-app`, `store`, `key` — how Premium was obtained.
  final String source;
  final bool storeAvailable;
  final StoreProduct? product;
  final bool purchasePending;
  final String? message;

  bool get isPremium => tier == LicenseTier.premium;

  bool allows(PremiumFeature feature) => isPremium;

  LicenseState copyWith({
    LicenseTier? tier,
    String? source,
    bool? storeAvailable,
    StoreProduct? product,
    bool? purchasePending,
    String? message,
    bool clearMessage = false,
  }) =>
      LicenseState(
        tier: tier ?? this.tier,
        source: source ?? this.source,
        storeAvailable: storeAvailable ?? this.storeAvailable,
        product: product ?? this.product,
        purchasePending: purchasePending ?? this.purchasePending,
        message: clearMessage ? null : (message ?? this.message),
      );

  @override
  List<Object?> get props => [tier, source, storeAvailable, product, purchasePending, message];
}

/// Optional server-side verification of store purchases.
abstract class PurchaseVerifier {
  /// Returns true/false for a definitive answer, null when the server could
  /// not be reached (the purchase is then accepted provisionally so legitimate
  /// users are never blocked by an outage).
  Future<bool?> verify(StorePurchase purchase, String platform);
}

class HttpPurchaseVerifier implements PurchaseVerifier {
  HttpPurchaseVerifier(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();
  final String baseUrl;
  final http.Client _client;

  @override
  Future<bool?> verify(StorePurchase p, String platform) async {
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/v1/licenses/verify-store'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'platform': platform,
              'productId': p.productId,
              'purchaseId': p.purchaseId,
              'verificationData': p.verificationData,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 500) return null;
      final body = jsonDecode(res.body);
      return body is Map && body['valid'] == true;
    } catch (_) {
      return null;
    }
  }
}

class LicenseController extends StateNotifier<LicenseState> {
  LicenseController({
    required LicenseStore store,
    required StoreGateway gateway,
    PurchaseVerifier? verifier,
    String? publicKey,
    String? productId,
    bool? paidUpfront,
  })  : _store = store,
        _gateway = gateway,
        _verifier = verifier,
        _publicKey = publicKey ?? AppConfig.licensePublicKey,
        _productId = productId ?? AppConfig.premiumProductId,
        _paidUpfront = paidUpfront ?? AppConfig.isPaidUpfront,
        super(const LicenseState()) {
    ready = _init();
  }

  final LicenseStore _store;
  final StoreGateway _gateway;
  final PurchaseVerifier? _verifier;
  final String _publicKey;
  final String _productId;
  final bool _paidUpfront;
  StreamSubscription<List<StorePurchase>>? _sub;

  /// Completes when the stored entitlement has been evaluated.
  late final Future<void> ready;

  Future<void> _init() async {
    if (_paidUpfront) {
      state = state.copyWith(tier: LicenseTier.premium, source: 'paid-app');
      return;
    }
    final stored = await _store.read();
    var premium = false;
    var source = '';
    if (stored != null) {
      if (stored.kind == 'key') {
        premium = await LicenseKeyCodec.verify(
              stored.licenseKey,
              publicKeyBase64: _publicKey,
              expectedProduct: _productId,
            ) !=
            null;
        source = 'key';
      } else if (stored.kind == 'store' && stored.productId == _productId) {
        // Cached store entitlement — trusted offline; re-confirmed whenever
        // the store re-delivers the purchase (restore / app start).
        premium = true;
        source = 'store';
      }
    }
    state = state.copyWith(
      tier: premium ? LicenseTier.premium : LicenseTier.free,
      source: source,
    );

    final available = await _gateway.isAvailable();
    state = state.copyWith(storeAvailable: available);
    if (!available) return;
    _sub = _gateway.purchaseUpdates.listen(_onPurchases, onError: (_) {});
    try {
      final product = await _gateway.queryProduct(_productId);
      if (product != null) state = state.copyWith(product: product);
    } catch (_) {}
  }

  Future<void> _onPurchases(List<StorePurchase> purchases) async {
    for (final p in purchases) {
      if (p.productId != _productId) continue;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          state = state.copyWith(purchasePending: true, clearMessage: true);
        case StorePurchaseStatus.canceled:
          state = state.copyWith(purchasePending: false);
          await _gateway.completePurchase(p);
        case StorePurchaseStatus.error:
          state = state.copyWith(
            purchasePending: false,
            message: p.errorMessage ?? 'The purchase could not be completed.',
          );
          await _gateway.completePurchase(p);
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          final verdict = await _verifier?.verify(p, _gateway.platformName);
          if (verdict == false) {
            state = state.copyWith(
              purchasePending: false,
              message: 'We couldn’t verify this purchase. Contact support if you were charged.',
            );
          } else {
            await _store.write(StoredEntitlement(
              kind: 'store',
              purchaseId: p.purchaseId,
              productId: p.productId,
            ));
            state = state.copyWith(
              tier: LicenseTier.premium,
              source: 'store',
              purchasePending: false,
              message: p.status == StorePurchaseStatus.restored
                  ? 'Purchase restored — thank you!'
                  : 'Premium unlocked — thank you!',
            );
          }
          // Must always be completed or Google Play refunds after 3 days.
          await _gateway.completePurchase(p);
      }
    }
  }

  Future<void> buy() async {
    if (!state.storeAvailable) {
      state = state.copyWith(message: 'In-app purchases are not available on this device.');
      return;
    }
    state = state.copyWith(clearMessage: true);
    try {
      final started = await _gateway.buyNonConsumable(_productId);
      if (!started) {
        state = state.copyWith(message: 'Premium is not available in your store region yet.');
      }
    } catch (e) {
      state = state.copyWith(message: 'Could not start the purchase.');
    }
  }

  Future<void> restore() async {
    if (!state.storeAvailable) {
      state = state.copyWith(
        message: 'Restore is done with your licence key on this platform.',
      );
      return;
    }
    state = state.copyWith(message: 'Checking your purchases…');
    try {
      await _gateway.restorePurchases();
    } catch (_) {
      state = state.copyWith(message: 'Restore failed. Try again later.');
    }
  }

  /// Activates a licence key (web purchase, or support-issued key).
  Future<bool> activateKey(String key) async {
    final payload = await LicenseKeyCodec.verify(
      key,
      publicKeyBase64: _publicKey,
      expectedProduct: _productId,
    );
    if (payload == null) {
      state = state.copyWith(message: 'That licence key isn’t valid.');
      return false;
    }
    await _store.write(StoredEntitlement(
      kind: 'key',
      licenseKey: key.trim(),
      productId: payload.product,
    ));
    state = state.copyWith(
      tier: LicenseTier.premium,
      source: 'key',
      message: 'Premium activated — thank you!',
    );
    return true;
  }

  Future<void> deactivate() async {
    if (_paidUpfront) return;
    await _store.clear();
    state = state.copyWith(tier: LicenseTier.free, source: '', message: 'Licence removed from this device.');
  }

  void clearMessage() => state = state.copyWith(clearMessage: true);

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final licenseControllerProvider =
    StateNotifierProvider<LicenseController, LicenseState>((ref) {
  return LicenseController(
    store: SecureLicenseStore(),
    gateway: InAppPurchaseGateway(),
    verifier: AppConfig.licenseServerUrl.isEmpty
        ? null
        : HttpPurchaseVerifier(AppConfig.licenseServerUrl),
  );
});

final isPremiumProvider = Provider<bool>(
  (ref) => ref.watch(licenseControllerProvider.select((s) => s.isPremium)),
);
