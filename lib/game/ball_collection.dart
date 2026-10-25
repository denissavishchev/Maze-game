import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ball.dart';
import 'story.dart';
import 'story_progress.dart';

/// Where a ball comes from, besides buying it.
enum BallSource { starter, chapter, stars }

/// The balls the player owns. Three come with the game, one is given for each
/// finished story chapter, one for nearly all the stars, and every ball can
/// be bought. An owned ball can be played in every mode.
class BallCollection extends ChangeNotifier {
  BallCollection._();

  static final BallCollection instance = BallCollection._();

  static const List<BallKind> starters = [BallKind.wood, BallKind.rubber, BallKind.stone];

  /// Reward for finishing chapter 1..5: from the handy to the specialised.
  static const List<BallKind> chapterRewards = [
    BallKind.steel,
    BallKind.slime,
    BallKind.glass,
    BallKind.paper,
    BallKind.bubble,
  ];

  /// The last ball comes with this share of all the stars (or from the shop).
  static const BallKind starsBall = BallKind.chameleon;
  static const double starsShare = 0.97;

  static int get starsNeeded =>
      (StoryLevel.count * StoryLevel.maxStars * starsShare).ceil();

  static BallSource sourceOf(BallKind kind) {
    if (starters.contains(kind)) return BallSource.starter;
    if (chapterRewards.contains(kind)) return BallSource.chapter;
    return BallSource.stars;
  }

  /// The chapter (1..5) whose end gives [kind], if any.
  static int? chapterOf(BallKind kind) {
    final i = chapterRewards.indexOf(kind);
    return i < 0 ? null : i + 1;
  }

  static const _key = 'balls_v1';

  final Set<BallKind> _owned = {...starters};

  /// The owned balls, in the order of [BallKind.values].
  List<BallKind> get owned => [
        for (final b in BallKind.values)
          if (_owned.contains(b)) b,
      ];

  List<BallKind> get locked => [
        for (final b in BallKind.values)
          if (!_owned.contains(b)) b,
      ];

  bool owns(BallKind kind) => _owned.contains(kind);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_key);
      _owned
        ..clear()
        ..addAll(starters);
      if (names != null) {
        for (final b in BallKind.values) {
          if (names.contains(b.name)) _owned.add(b);
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final b in _owned) b.name]);
    } catch (_) {}
  }

  Future<void> unlock(BallKind kind) async {
    if (!_owned.add(kind)) return;
    notifyListeners();
    await _save();
  }

  Future<void> unlockAll() async {
    _owned.addAll(BallKind.values);
    notifyListeners();
    await _save();
  }

  /// Gives the balls the story has earned: one per finished chapter and the
  /// last for nearly all stars. Returns the ones that are new.
  Future<List<BallKind>> grantRewards(StoryProgress progress) async {
    final fresh = <BallKind>[];
    for (var c = 1; c <= chapterRewards.length; c++) {
      final ball = chapterRewards[c - 1];
      if (progress.chapterDone(c) && _owned.add(ball)) fresh.add(ball);
    }
    if (progress.totalStars >= starsNeeded && _owned.add(starsBall)) {
      fresh.add(starsBall);
    }
    if (fresh.isNotEmpty) {
      notifyListeners();
      await _save();
    }
    return fresh;
  }

  /// Tests and the settings' test button: back to the three starters.
  Future<void> reset() async {
    _owned
      ..clear()
      ..addAll(starters);
    notifyListeners();
    await _save();
  }
}
