import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player_app/licensing/license_controller.dart';
import 'package:music_player_app/licensing/license_key.dart';
import 'package:music_player_app/licensing/license_store.dart';
import 'package:music_player_app/licensing/store_gateway.dart';

class FakeGateway implements StoreGateway {
  FakeGateway({this.available = true});
  final bool available;
  final controller = StreamController<List<StorePurchase>>.broadcast();
  final completed = <StorePurchase>[];
  int buys = 0;
  int restores = 0;

  @override
  String get platformName => 'android';
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<StoreProduct?> queryProduct(String id) async =>
      StoreProduct(id: id, title: 'Premium', price: '€4.99');
  @override
  Stream<List<StorePurchase>> get purchaseUpdates => controller.stream;
  @override
  Future<bool> buyNonConsumable(String productId) async {
    buys++;
    return true;
  }

  @override
  Future<void> restorePurchases() async => restores++;
  @override
  Future<void> completePurchase(StorePurchase p) async => completed.add(p);

  void emit(StorePurchaseStatus status, {String product = 'premium_lifetime'}) =>
      controller.add([StorePurchase(productId: product, status: status, purchaseId: 'GPA.1', verificationData: 'tok')]);
}

class FakeVerifier implements PurchaseVerifier {
  FakeVerifier(this.answer);
  bool? answer;
  @override
  Future<bool?> verify(StorePurchase p, String platform) async => answer;
}

Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late SimpleKeyPair keyPair;
  late String publicKey;

  setUpAll(() async {
    keyPair = await Ed25519().newKeyPair();
    publicKey = base64.encode((await keyPair.extractPublicKey()).bytes);
  });

  Future<String> issue({String product = 'premium_lifetime', SimpleKeyPair? kp}) => LicenseKeyCodec.sign(
        LicensePayload(licenseId: 'lic_1', product: product, issuedAt: DateTime.utc(2026, 1, 1)),
        kp ?? keyPair,
      );

  group('LicenseKeyCodec', () {
    test('round-trips a signed key', () async {
      final key = await issue();
      final p = await LicenseKeyCodec.verify(key, publicKeyBase64: publicKey, expectedProduct: 'premium_lifetime');
      expect(p?.licenseId, 'lic_1');
    });

    test('rejects tampered payloads, foreign signers and wrong products', () async {
      final key = await issue();
      final parts = key.split('.');
      final forged = base64Url
          .encode(utf8.encode(jsonEncode({'lid': 'lic_hack', 'prd': 'premium_lifetime', 'iat': 1})))
          .replaceAll('=', '');
      expect(await LicenseKeyCodec.verify('${parts[0]}.$forged.${parts[2]}', publicKeyBase64: publicKey), isNull);

      final other = await issue(kp: await Ed25519().newKeyPair());
      expect(await LicenseKeyCodec.verify(other, publicKeyBase64: publicKey), isNull);

      final wrongProduct = await issue(product: 'other');
      expect(await LicenseKeyCodec.verify(wrongProduct, publicKeyBase64: publicKey, expectedProduct: 'premium_lifetime'), isNull);
    });

    test('rejects garbage input safely', () async {
      for (final junk in ['', 'AURORA1', 'AURORA1.a.b', 'X.Y.Z', 'AURORA1.!!!.???', 'A' * 5000]) {
        expect(await LicenseKeyCodec.verify(junk, publicKeyBase64: publicKey), isNull, reason: junk.length > 20 ? 'long' : junk);
      }
      expect(await LicenseKeyCodec.verify(await issue(), publicKeyBase64: ''), isNull);
    });

    test('tolerates whitespace from copy/paste', () async {
      final key = await issue();
      final spaced = '  ${key.substring(0, 20)}\n${key.substring(20)}  ';
      expect(await LicenseKeyCodec.verify(spaced, publicKeyBase64: publicKey), isNotNull);
    });
  });

  group('LicenseController', () {
    LicenseController make({
      FakeGateway? gateway,
      MemoryLicenseStore? store,
      PurchaseVerifier? verifier,
      bool paid = false,
    }) =>
        LicenseController(
          store: store ?? MemoryLicenseStore(),
          gateway: gateway ?? FakeGateway(),
          verifier: verifier,
          publicKey: publicKey,
          productId: 'premium_lifetime',
          paidUpfront: paid,
        );

    test('starts free and loads the store price', () async {
      final c = make();
      await c.ready;
      expect(c.state.tier, LicenseTier.free);
      expect(c.state.product?.price, '€4.99');
    });

    test('paid-upfront builds are always premium without a store', () async {
      final c = make(paid: true, gateway: FakeGateway(available: false));
      await c.ready;
      expect(c.state.isPremium, isTrue);
      expect(c.state.source, 'paid-app');
    });

    test('successful purchase unlocks, persists and completes the transaction', () async {
      final g = FakeGateway();
      final store = MemoryLicenseStore();
      final c = make(gateway: g, store: store);
      await c.ready;
      await c.buy();
      expect(g.buys, 1);
      g.emit(StorePurchaseStatus.pending);
      await pump();
      expect(c.state.purchasePending, isTrue);
      g.emit(StorePurchaseStatus.purchased);
      await pump();
      expect(c.state.isPremium, isTrue);
      expect(store.value?.kind, 'store');
      expect(g.completed, hasLength(1));

      // Survives a restart (cached entitlement, offline).
      final again = make(gateway: FakeGateway(available: false), store: store);
      await again.ready;
      expect(again.state.isPremium, isTrue);
    });

    test('server rejection does not unlock but still completes the transaction', () async {
      final g = FakeGateway();
      final c = make(gateway: g, verifier: FakeVerifier(false));
      await c.ready;
      g.emit(StorePurchaseStatus.purchased);
      await pump();
      expect(c.state.isPremium, isFalse);
      expect(c.state.message, contains('verify'));
      expect(g.completed, hasLength(1));
    });

    test('verification server outage accepts the purchase provisionally', () async {
      final g = FakeGateway();
      final c = make(gateway: g, verifier: FakeVerifier(null));
      await c.ready;
      g.emit(StorePurchaseStatus.restored);
      await pump();
      expect(c.state.isPremium, isTrue);
    });

    test('cancel and error do not unlock', () async {
      final g = FakeGateway();
      final c = make(gateway: g);
      await c.ready;
      g.emit(StorePurchaseStatus.canceled);
      g.emit(StorePurchaseStatus.error);
      await pump();
      expect(c.state.isPremium, isFalse);
    });

    test('purchases of other products are ignored', () async {
      final g = FakeGateway();
      final c = make(gateway: g);
      await c.ready;
      g.emit(StorePurchaseStatus.purchased, product: 'something_else');
      await pump();
      expect(c.state.isPremium, isFalse);
    });

    test('restore asks the store', () async {
      final g = FakeGateway();
      final c = make(gateway: g);
      await c.ready;
      await c.restore();
      expect(g.restores, 1);
    });

    test('licence key activation (web) and re-validation on start', () async {
      final store = MemoryLicenseStore();
      final c = make(gateway: FakeGateway(available: false), store: store);
      await c.ready;
      expect(await c.activateKey('not a key'), isFalse);
      expect(c.state.isPremium, isFalse);
      expect(await c.activateKey(await issue()), isTrue);
      expect(c.state.isPremium, isTrue);

      final again = make(gateway: FakeGateway(available: false), store: store);
      await again.ready;
      expect(again.state.isPremium, isTrue);
      expect(again.state.source, 'key');
    });

    test('a stored key that no longer verifies is not trusted', () async {
      final store = MemoryLicenseStore()
        ..value = const StoredEntitlement(kind: 'key', licenseKey: 'AURORA1.x.y', productId: 'premium_lifetime');
      final c = make(gateway: FakeGateway(available: false), store: store);
      await c.ready;
      expect(c.state.isPremium, isFalse);
    });

    test('deactivate removes the entitlement', () async {
      final store = MemoryLicenseStore();
      final c = make(gateway: FakeGateway(available: false), store: store);
      await c.ready;
      await c.activateKey(await issue());
      await c.deactivate();
      expect(c.state.isPremium, isFalse);
      expect(store.value, isNull);
    });
  });
}
