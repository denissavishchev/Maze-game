import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether sound effects are on. Remembered between launches.
class SoundSetting extends ChangeNotifier {
  SoundSetting._();

  static final SoundSetting instance = SoundSetting._();

  bool on = true;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      on = prefs.getBool('sound_on') ?? true;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> set(bool value) async {
    if (value == on) return;
    on = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sound_on', value);
    } catch (_) {}
  }
}
