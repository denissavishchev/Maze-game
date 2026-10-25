import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'story.dart';

/// Best result of one story level.
class StoryResult {
  const StoryResult(this.stars, this.millis);

  final int stars;
  final int millis;
}

/// Stars and best times of the story levels, remembered between launches.
class StoryProgress extends ChangeNotifier {
  StoryProgress._();

  static final StoryProgress instance = StoryProgress._();

  static const _key = 'story_v1';

  final Map<int, StoryResult> _results = {};

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _results.clear();
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          final list = v as List;
          _results[int.parse(k)] = StoryResult(list[0] as int, list[1] as int);
        });
      }
    } catch (_) {}
    notifyListeners();
  }

  int stars(int level) => _results[level]?.stars ?? 0;
  int? bestMillis(int level) => _results[level]?.millis;

  int get totalStars => _results.values.fold(0, (a, r) => a + r.stars);

  /// Every level of chapter 1..5 has been finished.
  bool chapterDone(int chapter) {
    for (var n = 0; n < StoryLevel.perChapter; n++) {
      if (stars((chapter - 1) * StoryLevel.perChapter + n) < 1) return false;
    }
    return true;
  }

  bool isUnlocked(StoryLevel level) => totalStars >= level.requiredStars;

  /// Stars still missing to open [level] (0 when it is open).
  int missingStars(StoryLevel level) => (level.requiredStars - totalStars).clamp(0, 1 << 30);

  /// Keeps the better of the old and the new result; returns the stars this
  /// run added on top of the old best.
  Future<int> record(int level, int stars, int millis) async {
    final old = _results[level];
    final gained = stars - (old?.stars ?? 0);
    final best = old == null
        ? StoryResult(stars, millis)
        : StoryResult(
            stars > old.stars ? stars : old.stars,
            millis < old.millis ? millis : old.millis,
          );
    _results[level] = best;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final e in _results.entries) '${e.key}': [e.value.stars, e.value.millis],
        }),
      );
    } catch (_) {}
    return gained < 0 ? 0 : gained;
  }

  /// Tests: forget everything without touching the disk.
  @visibleForTesting
  void resetForTest() {
    _results.clear();
    notifyListeners();
  }
}
