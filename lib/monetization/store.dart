import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../game/ball.dart';
import '../game/ball_collection.dart';
import 'vip.dart';

/// Buying balls and VIP through the App Store and Google Play. Every product
/// is bought once and kept for good (non-consumable). Prices come from the
/// store, in the player's own currency.
///
/// Product ids, the same in both stores:
///  * `ball_<name>` for each ball that does not come with the game,
///  * `all_balls` for every ball at once,
///  * `vip` for a game without full-screen ads.
class Store extends ChangeNotifier {
  Store._();

  static final Store instance = Store._();

  static const String vipId = 'vip';
  static const String allBallsId = 'all_balls';

  /// The balls that are not starters.
  static List<BallKind> get purchasableBalls => [
        for (final b in BallKind.values)
          if (!BallCollection.starters.contains(b)) b,
      ];

  static String ballId(BallKind kind) => 'ball_${kind.name}';

  static Set<String> get productIds =>
      {vipId, allBallsId, for (final b in purchasableBalls) ballId(b)};

  /// Tests only: a purchase just grants the product, without a store.
  @visibleForTesting
  static bool simulate = false;

  bool available = false;

  /// Something is being bought right now (the store window is up).
  bool busy = false;

  /// The last store problem, for a message to the player; cleared on the next try.
  String? error;

  final Map<String, ProductDetails> _products = {};
  StreamSubscription<List<PurchaseDetails>>? _sub;

  String? priceOf(String id) => _products[id]?.price;

  String? ballPrice(BallKind kind) => priceOf(ballId(kind));
  String? get allBallsPrice => priceOf(allBallsId);
  String? get vipPrice => priceOf(vipId);

  /// True when [id] can be bought now.
  bool canBuy(String id) => simulate || (available && _products.containsKey(id));

  /// Connects to the store and reads the prices. Never throws; without a
  /// store the shop simply has nothing to buy.
  static Future<void> start() => instance._start();

  Future<void> _start() async {
    if (_sub != null) return;
    try {
      final iap = InAppPurchase.instance;
      available = await iap.isAvailable();
      if (!available) {
        notifyListeners();
        return;
      }
      _sub = iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          busy = false;
          error = '$e';
          notifyListeners();
        },
      );
      final found = await iap.queryProductDetails(productIds);
      for (final d in found.productDetails) {
        _products[d.id] = d;
      }
      notifyListeners();
      // Google Play hands back what the account owns without any prompt; on
      // iOS restoring asks for the Apple ID, so only the button does it.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await iap.restorePurchases();
      }
    } catch (_) {
      available = false;
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          busy = true;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          busy = false;
          await _grant(p.productID);
        case PurchaseStatus.error:
          busy = false;
          error = p.error?.message ?? 'error';
        case PurchaseStatus.canceled:
          busy = false;
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> _grant(String id) async {
    if (id == vipId) {
      await Vip.instance.set(true);
    } else if (id == allBallsId) {
      await BallCollection.instance.unlockAll();
    } else {
      for (final b in purchasableBalls) {
        if (ballId(b) == id) await BallCollection.instance.unlock(b);
      }
    }
  }

  Future<bool> _buy(String id) async {
    error = null;
    if (simulate) {
      await _grant(id);
      return true;
    }
    final details = _products[id];
    if (!available || details == null || busy) return false;
    busy = true;
    notifyListeners();
    try {
      // The result of the purchase comes through [purchaseStream].
      return await InAppPurchase.instance
          .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: details));
    } catch (e) {
      busy = false;
      error = '$e';
      notifyListeners();
      return false;
    }
  }

  static Future<bool> buyBall(BallKind kind) => instance._buy(ballId(kind));

  static Future<bool> buyAllBalls() => instance._buy(allBallsId);

  static Future<bool> buyVip() => instance._buy(vipId);

  /// Gives back what the store account has bought.
  static Future<void> restore() async {
    if (simulate || !instance.available) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {}
  }
}
