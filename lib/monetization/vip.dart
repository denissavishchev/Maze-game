import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the player has paid for VIP: no interstitials, and rewarded ads
/// give their reward at once. The store's purchase sets it ([Store]).
class Vip extends ChangeNotifier {
  Vip._();

  static final Vip instance = Vip._();

  bool on = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on = prefs.getBool('vip') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> set(bool value) async {
    if (value == on) return;
    on = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vip', value);
    } catch (_) {}
  }
}
