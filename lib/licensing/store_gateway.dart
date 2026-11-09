import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

class StoreProduct {
  const StoreProduct({required this.id, required this.title, required this.price});
  final String id;
  final String title;

  /// Localised price string from the store (e.g. "€4.99").
  final String price;
}

class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.purchaseId = '',
    this.verificationData = '',
    this.verificationSource = '',
    this.errorMessage,
    this.raw,
  });

  final String productId;
  final StorePurchaseStatus status;
  final String purchaseId;

  /// Google Play purchase token / Apple receipt — sent to the licence server.
  final String verificationData;
  final String verificationSource;
  final String? errorMessage;
  final Object? raw;
}

/// Thin seam over `in_app_purchase` so licensing logic is unit-testable.
abstract class StoreGateway {
  Future<bool> isAvailable();
  Future<StoreProduct?> queryProduct(String productId);
  Stream<List<StorePurchase>> get purchaseUpdates;
  Future<bool> buyNonConsumable(String productId);
  Future<void> restorePurchases();
  Future<void> completePurchase(StorePurchase purchase);

  String get platformName;
}

/// App Store / Google Play implementation. Web has no store → unavailable.
class InAppPurchaseGateway implements StoreGateway {
  final Map<String, ProductDetails> _products = {};

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  String get platformName =>
      defaultTargetPlatform == TargetPlatform.android ? 'android' : 'ios';

  @override
  Future<bool> isAvailable() async {
    if (!_supported) return false;
    try {
      return await InAppPurchase.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StoreProduct?> queryProduct(String productId) async {
    final res = await InAppPurchase.instance.queryProductDetails({productId});
    if (res.productDetails.isEmpty) return null;
    final p = res.productDetails.first;
    _products[p.id] = p;
    return StoreProduct(id: p.id, title: p.title, price: p.price);
  }

  @override
  Stream<List<StorePurchase>> get purchaseUpdates {
    if (!_supported) return const Stream.empty();
    return InAppPurchase.instance.purchaseStream.map((list) => [
          for (final p in list)
            StorePurchase(
              productId: p.productID,
              purchaseId: p.purchaseID ?? '',
              status: switch (p.status) {
                PurchaseStatus.pending => StorePurchaseStatus.pending,
                PurchaseStatus.purchased => StorePurchaseStatus.purchased,
                PurchaseStatus.restored => StorePurchaseStatus.restored,
                PurchaseStatus.error => StorePurchaseStatus.error,
                PurchaseStatus.canceled => StorePurchaseStatus.canceled,
              },
              verificationData: p.verificationData.serverVerificationData,
              verificationSource: p.verificationData.source,
              errorMessage: p.error?.message,
              raw: p,
            ),
        ]);
  }

  @override
  Future<bool> buyNonConsumable(String productId) async {
    var details = _products[productId];
    if (details == null) {
      await queryProduct(productId);
      details = _products[productId];
    }
    if (details == null) return false;
    return InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  @override
  Future<void> restorePurchases() => InAppPurchase.instance.restorePurchases();

  @override
  Future<void> completePurchase(StorePurchase purchase) async {
    final raw = purchase.raw;
    if (raw is PurchaseDetails && raw.pendingCompletePurchase) {
      await InAppPurchase.instance.completePurchase(raw);
    }
  }
}
