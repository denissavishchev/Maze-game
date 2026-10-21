import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether vibration is on. Remembered between launches.
class VibrationSetting extends ChangeNotifier {
  VibrationSetting._();

  static final VibrationSetting instance = VibrationSetting._();

  bool on = true;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on = prefs.getBool('vibration_on') ?? true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> set(bool value) async {
    if (value == on) return;
    on = value;
    notifyListeners();
    if (value) Haptics.play(Haptic.tick); // a taste of what it feels like
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vibration_on', value);
    } catch (_) {}
  }
}

/// How strong a vibration is. Both are gentle: the system's lightest
/// feedback, never the long strong buzz.
enum Haptic {
  /// A faint tick: soft bumps, and a reminder while the ball is loud.
  tick,

  /// A little firmer, for harder hits.
  bump,
}

class Haptics {
  /// Off until the app turns it on (unit tests have no device to vibrate).
  static bool enabled = false;

  /// Tests collect what would have been felt here.
  @visibleForTesting
  static List<Haptic>? record;

  static bool get active => enabled && VibrationSetting.instance.on;

  static void play(Haptic h) {
    record?.add(h);
    if (!active) return;
    try {
      switch (h) {
        case Haptic.tick:
          HapticFeedback.selectionClick();
        case Haptic.bump:
          HapticFeedback.lightImpact();
      }
    } catch (_) {}
  }
}
