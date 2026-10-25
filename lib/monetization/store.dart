import '../game/ball.dart';
import '../game/ball_collection.dart';

/// Buying balls. Until the real stores are plugged in (RevenueCat), a
/// purchase simply unlocks the ball, and the prices are placeholders.
class Store {
  Store._();

  static const String ballPrice = '4,99 zł';
  static const String allBallsPrice = '19,99 zł';

  static Future<bool> buyBall(BallKind kind) async {
    await BallCollection.instance.unlock(kind);
    return true;
  }

  static Future<bool> buyAllBalls() async {
    await BallCollection.instance.unlockAll();
    return true;
  }

  /// Gives back what the store account has bought. Nothing to ask yet.
  static Future<void> restore() async {}
}
