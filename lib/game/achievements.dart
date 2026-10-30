import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:shared_preferences/shared_preferences.dart';

import 'ball.dart';
import 'world.dart';
import 'ball_collection.dart';
import 'story.dart';
import 'story_progress.dart';

/// One achievement: its texts are `ach.<id>` and `ach.<id>.desc`.
class Achievement {
  const Achievement(this.id, this.icon, {this.target});

  final String id;
  final IconData icon;

  /// For achievements with a count to reach: what the count is.
  final int? target;
}

/// What the player can earn, in the order they are shown.
final List<Achievement> achievementList = [
  Achievement('star_collector', Icons.stars_rounded, target: 50),
  Achievement('flawless_chapter', Icons.military_tech_rounded),
  Achievement('story_complete', Icons.workspace_premium_rounded, target: StoryLevel.count),
  Achievement('speed_demon', Icons.speed_rounded),
  Achievement('stargazer', Icons.auto_awesome_rounded, target: BallCollection.starsNeeded),
  Achievement('ball_collector', Icons.sports_baseball_rounded, target: 9),
  Achievement('endless_beginner', Icons.all_inclusive_rounded, target: 5),
  Achievement('endless_marathon', Icons.local_fire_department_rounded, target: 25),
  Achievement('pure_run', Icons.block_rounded, target: 10),
  Achievement('bonus_master', Icons.flash_on_rounded, target: 25),
  Achievement('ghost_whisperer', Icons.nightlight_round, target: 1),
  Achievement('sneaky_wolf', Icons.pets_rounded, target: 1),
  Achievement('in_the_dark', Icons.light_mode_rounded, target: 1),
  Achievement('world_tour', Icons.public_rounded, target: WorldKind.values.length),
  Achievement('big_maze_survivor', Icons.shield_rounded),
  Achievement('lava_walker', Icons.whatshot_rounded),
  Achievement('deep_diver', Icons.scuba_diving_rounded),
  Achievement('laser_dancer', Icons.visibility_off_rounded),
  Achievement('glass_cannon', Icons.diamond_rounded),
  Achievement('grave_dancer', Icons.church_rounded, target: 10),
];

/// The achievements the player has earned, remembered between launches under
/// its own key, so it never disturbs (or is disturbed by) any other saved data.
/// Unknown ids from a newer version are kept and ignored.
class Achievements extends ChangeNotifier {
  Achievements._();

  static final Achievements instance = Achievements._();

  static const _key = 'achievements_v1';

  /// Mazes of this size or bigger count as "big".
  static const int bigMaze = 4;

  /// Grave dancer: the ball's centre this close to an open grave counts as
  /// rolling past it (a grave kills from 0.12).
  static const double graveDodgeReach = 0.3;

  /// Pure run: this many endless mazes without a second chance.
  static const int pureRunMazes = 10;

  final Map<String, int> _earned = {};
  final Map<String, int> _counters = {};

  /// Newly earned, not yet announced on screen.
  final List<String> fresh = [];

  bool _watching = false;

  bool has(String id) => _earned.containsKey(id);

  int get earnedCount => achievementList.where((a) => has(a.id)).length;

  int counter(String name) => _counters[name] ?? 0;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _earned.clear();
      _counters.clear();
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        (j['u'] as Map<String, dynamic>?)?.forEach((k, v) => _earned[k] = v as int);
        (j['c'] as Map<String, dynamic>?)?.forEach((k, v) => _counters[k] = v as int);
      }
    } catch (_) {
      _earned.clear();
      _counters.clear();
    }
    // Progress that exists already (stars, chapters, balls) counts at once,
    // and from now on is checked whenever it changes.
    if (!_watching) {
      _watching = true;
      StoryProgress.instance.addListener(checkProgress);
      BallCollection.instance.addListener(checkProgress);
    }
    checkProgress(announce: false);
    notifyListeners();
  }

  /// Gives [id] if it is not yet earned.
  void unlock(String id, {bool announce = true}) {
    if (_earned.containsKey(id)) return;
    _earned[id] = DateTime.now().millisecondsSinceEpoch;
    if (announce) fresh.add(id);
    notifyListeners();
    _save();
  }

  void _count(String name, int value) {
    _counters[name] = value;
    _save();
  }

  /// Achievements that follow from the story's stars and the owned balls.
  void checkProgress({bool announce = true}) {
    final story = StoryProgress.instance;
    final stars = story.totalStars;
    _count('stars', stars);
    if (stars >= 50) unlock('star_collector', announce: announce);
    if (stars >= BallCollection.starsNeeded) unlock('stargazer', announce: announce);
    for (var c = 1; c <= StoryLevel.chapters; c++) {
      var all = true;
      for (var n = 0; n < StoryLevel.perChapter; n++) {
        if (story.stars((c - 1) * StoryLevel.perChapter + n) < StoryLevel.maxStars) {
          all = false;
          break;
        }
      }
      if (all) unlock('flawless_chapter', announce: announce);
    }
    var cleared = 0;
    for (var i = 0; i < StoryLevel.count; i++) {
      if (story.stars(i) >= 1) cleared++;
    }
    _count('cleared', cleared);
    if (cleared >= StoryLevel.count) unlock('story_complete', announce: announce);
    final balls = BallCollection.instance.owned.length;
    _count('balls', balls);
    if (balls >= BallKind.values.length) unlock('ball_collector', announce: announce);
  }

  /// A story level was won in [seconds]; [level] is it.
  void storyWon(StoryLevel level, double seconds) {
    if (seconds <= level.greatSeconds * 0.8) unlock('speed_demon');
  }

  /// A maze was won in [world]; all the worlds make a world tour.
  void worldWon(WorldKind world) {
    final bits = counter('worlds') | (1 << world.index);
    if (bits != counter('worlds')) _count('worlds', bits);
    if (_bits(bits) >= WorldKind.values.length) unlock('world_tour');
  }

  static int _bits(int n) {
    var c = 0;
    for (var i = 0; i < WorldKind.values.length; i++) {
      if (n & (1 << i) != 0) c++;
    }
    return c;
  }

  /// The ball rolled past an open grave without falling in.
  void graveDodged() {
    final n = counter('graves') + 1;
    _count('graves', n);
    if (n >= 10) unlock('grave_dancer');
    notifyListeners();
  }

  /// A bonus was used.
  void bonusUsed() {
    final n = counter('bonus') + 1;
    _count('bonus', n);
    if (n >= 25) unlock('bonus_master');
    notifyListeners();
  }

  /// Endless: [mazes] solved so far in this run, [continues] second chances
  /// taken in it.
  void endlessProgress(int mazes, int continues) {
    if (mazes > counter('endless')) _count('endless', mazes);
    if (mazes >= 5) unlock('endless_beginner');
    if (mazes >= 25) unlock('endless_marathon');
    if (mazes >= pureRunMazes && continues == 0) unlock('pure_run');
    if (mazes > counter('pure') && continues == 0) _count('pure', mazes);
  }

  /// How far [id] has got, for achievements with a count (null otherwise).
  (int, int)? progress(String id) {
    final target = achievementList.firstWhere((a) => a.id == id).target;
    if (target == null) return null;
    final now = switch (id) {
      'star_collector' => counter('stars'),
      'stargazer' => counter('stars'),
      'story_complete' => counter('cleared'),
      'world_tour' => _bits(counter('worlds')),
      'grave_dancer' => counter('graves'),
      'endless_marathon' => counter('endless'),
      'ball_collector' => counter('balls'),
      'endless_beginner' => counter('endless'),
      'pure_run' => counter('pure'),
      'bonus_master' => counter('bonus'),
      _ => null,
    };
    if (now == null) return null;
    return (now.clamp(0, target), target);
  }

  /// Tests: forget everything without touching the disk.
  @visibleForTesting
  void resetForTest() {
    _earned.clear();
    _counters.clear();
    fresh.clear();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode({'u': _earned, 'c': _counters}));
    } catch (_) {}
  }
}
