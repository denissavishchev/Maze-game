import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/achievements.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/ball_collection.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/story.dart';
import 'package:orbyrinth/game/story_progress.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/achievement_popup.dart';
import 'package:orbyrinth/ui/achievements_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rolls the ball into the centre of a polar maze: the goal.
void win(GameController g) {
  g.started = true;
  g.pos = g.maze.cellCenter(g.maze.goal);
  g.update(1 / 60, Offset.zero);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StoryProgress.instance.resetForTest();
    await BallCollection.instance.reset();
    Achievements.instance.resetForTest();
    await Achievements.instance.load();
    // A save still on its way from the previous test must not leak in.
    Achievements.instance.resetForTest();
  });

  test('earned achievements are remembered, and a damaged save is ignored', () async {
    Achievements.instance.unlock('bonus_master');
    await Future<void>.delayed(Duration.zero);
    Achievements.instance.resetForTest();
    expect(Achievements.instance.has('bonus_master'), isFalse);
    await Achievements.instance.load();
    expect(Achievements.instance.has('bonus_master'), isTrue);

    SharedPreferences.setMockInitialValues({'achievements_v1': '{not json'});
    await Achievements.instance.load();
    expect(Achievements.instance.earnedCount, 0);

    // An id from a newer version stays out of the way.
    SharedPreferences.setMockInitialValues({
      'achievements_v1': jsonEncode({'u': {'from_the_future': 1, 'pure_run': 2}}),
    });
    await Achievements.instance.load();
    expect(Achievements.instance.earnedCount, 1);
  });

  test('stars, chapters and balls are earned from the story progress', () async {
    final a = Achievements.instance;
    for (var i = 0; i < 17; i++) {
      await StoryProgress.instance.record(i, 3, 1000);
    }
    expect(a.has('star_collector'), isTrue, reason: '51 stars');
    expect(a.has('flawless_chapter'), isTrue, reason: 'a whole chapter at 3 stars');
    expect(a.has('story_complete'), isFalse);
    for (var i = 0; i < StoryLevel.count; i++) {
      await StoryProgress.instance.record(i, 1, 1000);
    }
    expect(a.has('story_complete'), isTrue);
    expect(a.progress('story_complete')!.$1, StoryLevel.count);
  });

  test('speed demon needs 20% under the three-star time', () {
    final level = StoryLevel(4);
    Achievements.instance.storyWon(level, level.greatSeconds * 0.9);
    expect(Achievements.instance.has('speed_demon'), isFalse);
    Achievements.instance.storyWon(level, level.greatSeconds * 0.79);
    expect(Achievements.instance.has('speed_demon'), isTrue);
  });

  test('bonuses are counted', () {
    final a = Achievements.instance;
    final g = GameController(const GameConfig(WorldKind.forest, 1), seed: 3);
    for (var i = 0; i < 25; i++) {
      g.bonusCharges = 1;
      g.bonusLeft = 0;
      g.status = GameStatus.playing;
      g.useBonus();
    }
    expect(a.has('bonus_master'), isTrue);
  });

  test('ghost whisperer and sneaky wolf: a win without waking anything', () {
    final yard = GameController(const GameConfig(WorldKind.graveyard, 2), seed: 3);
    win(yard);
    expect(yard.won, isTrue);
    expect(Achievements.instance.has('ghost_whisperer'), isTrue);
    expect(Achievements.instance.has('sneaky_wolf'), isFalse);

    Achievements.instance.resetForTest();
    final wood = GameController(const GameConfig(WorldKind.forest, 2), seed: 3);
    wood.creatures.first.asleep = true;
    wood.noise(wood.creatures.first.pos);
    expect(wood.creatures.first.asleep, isFalse, reason: 'the bump woke it');
    win(wood);
    expect(Achievements.instance.has('sneaky_wolf'), isFalse);
  });

  test('in the dark: a big underground maze won without the light bonus', () {
    final small = GameController(const GameConfig(WorldKind.underground, 2), seed: 3);
    win(small);
    expect(Achievements.instance.has('in_the_dark'), isFalse, reason: 'not big');

    final lit = GameController(const GameConfig(WorldKind.underground, 4), seed: 3);
    lit.bonusCharges = 1;
    lit.useBonus();
    win(lit);
    expect(Achievements.instance.has('in_the_dark'), isFalse, reason: 'used the light');

    final dark = GameController(const GameConfig(WorldKind.underground, 4), seed: 3);
    win(dark);
    expect(Achievements.instance.has('in_the_dark'), isTrue);
  });

  test('endless: five mazes, and ten without a continue', () {
    final a = Achievements.instance;
    a.endlessProgress(5, 0);
    expect(a.has('endless_beginner'), isTrue);
    a.endlessProgress(10, 1);
    expect(a.has('pure_run'), isFalse, reason: 'used a second chance');
    a.endlessProgress(10, 0);
    expect(a.has('pure_run'), isTrue);
  });

  test('big mazes: first try, lava, ocean, glass; small ones count for none', () {
    final a = Achievements.instance;
    win(GameController(const GameConfig(WorldKind.volcano, 3), seed: 3));
    expect(a.has('lava_walker'), isFalse);
    expect(a.has('big_maze_survivor'), isFalse);

    win(GameController(const GameConfig(WorldKind.volcano, 4), seed: 3));
    expect(a.has('lava_walker'), isTrue);
    expect(a.has('big_maze_survivor'), isTrue);
    win(GameController(const GameConfig(WorldKind.ocean, 5), seed: 3));
    expect(a.has('deep_diver'), isTrue);

    a.resetForTest();
    final lost = GameController(const GameConfig(WorldKind.ocean, 5), seed: 3);
    lost.status = GameStatus.lost;
    lost.continueAfterLoss();
    lost.status = GameStatus.playing;
    win(lost);
    expect(a.has('deep_diver'), isTrue);
    expect(a.has('big_maze_survivor'), isFalse, reason: 'lost once in this maze');

    final glass = GameController(
        const GameConfig(WorldKind.forest, 4, ball: BallKind.glass),
        seed: 3);
    win(glass);
    expect(a.has('glass_cannon'), isTrue);
  });

  test('laser dancer: not once seen by a camera', () {
    final a = Achievements.instance;
    final g = GameController(const GameConfig(WorldKind.space, 4), seed: 3);
    win(g);
    expect(a.has('laser_dancer'), isTrue);
  });

  test('world tour needs all thirteen worlds', () {
    final a = Achievements.instance;
    for (final w in WorldKind.values.take(12)) {
      a.worldWon(w);
    }
    expect(a.has('world_tour'), isFalse);
    expect(a.progress('world_tour'), (12, 13));
    a.worldWon(WorldKind.values.last);
    expect(a.has('world_tour'), isTrue);
  });

  test('grave dancer: ten open graves rolled past, each counted once', () {
    final a = Achievements.instance;
    final g = GameController(const GameConfig(WorldKind.graveyard, 2), seed: 3);
    g.started = true;
    for (var i = 0; i < 10; i++) {
      final grave = Hazard(g.pos + const Offset(0.2, 0), armAt: 0, life: 50, radius: 0.12);
      g.hazards.add(grave);
      for (var k = 0; k < 5; k++) {
        g.update(1 / 60, Offset.zero);
      }
      expect(g.lost, isFalse);
    }
    expect(a.counter('graves'), 10);
    expect(a.has('grave_dancer'), isTrue);
  });

  test('endless marathon at 25 mazes', () {
    Achievements.instance.endlessProgress(25, 3);
    expect(Achievements.instance.has('endless_marathon'), isTrue);
  });

  testWidgets('the screen shows what is earned in colour and the rest greyed out',
      (tester) async {
    tester.view.physicalSize = const Size(780, 10000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Achievements.instance.resetForTest();
    Achievements.instance.unlock('bonus_master');
    await tester.pumpWidget(const MaterialApp(home: AchievementsScreen()));
    await tester.pump();
    expect(find.byKey(const Key('ach-count')), findsOneWidget);
    expect(Achievements.instance.earnedCount, 1);
    expect(find.byType(ColorFiltered), findsNWidgets(achievementList.length - 1));

    await tester.tap(find.byKey(const Key('ach-filter-earned')));
    await tester.pump();
    expect(find.byKey(const Key('ach-bonus_master')), findsOneWidget);
    expect(find.byType(ColorFiltered), findsNothing);

    await tester.tap(find.byKey(const Key('ach-filter-locked')));
    await tester.pump();
    expect(find.byKey(const Key('ach-bonus_master')), findsNothing);
    expect(find.byType(ColorFiltered), findsNWidgets(achievementList.length - 1));
  });

  testWidgets('earning one slides a card up from the bottom, then it goes away',
      (tester) async {
    Achievements.instance.resetForTest();
    await tester.pumpWidget(const MaterialApp(
      home: AchievementPopup(child: Scaffold(body: SizedBox.expand())),
    ));
    expect(find.byKey(const Key('ach-popup-pure_run')), findsNothing);
    Achievements.instance.unlock('pure_run');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('ach-popup-pure_run')), findsOneWidget);
    final bottom = tester.getBottomLeft(find.byKey(const Key('ach-popup-pure_run'))).dy;
    expect(bottom, greaterThan(tester.view.physicalSize.height / tester.view.devicePixelRatio - 40));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('ach-popup-pure_run')), findsNothing);
  });

  test('every achievement is named and described in every language', () {
    for (final a in achievementList) {
      for (final lang in AppLang.values) {
        final t = translationTables[lang]!;
        expect(t['ach.${a.id}'], isNotNull, reason: '${a.id} name in $lang');
        expect(t['ach.${a.id}.desc'], isNotNull, reason: '${a.id} text in $lang');
      }
    }
  });
}
