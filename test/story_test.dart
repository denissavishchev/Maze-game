import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/story.dart';
import 'package:orbyrinth/game/story_progress.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/monetization/ad_service.dart';
import 'package:orbyrinth/monetization/vip.dart';
import 'package:orbyrinth/ui/game_screen.dart';
import 'package:orbyrinth/ui/settings_screen.dart';
import 'package:orbyrinth/ui/story_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StoryProgress.instance.resetForTest();
    Vip.instance.on = false;
  });

  test('65 levels: five chapters, each visiting all 13 worlds once', () {
    expect(StoryLevel.count, 65);
    for (var c = 1; c <= 5; c++) {
      final worlds = [
        for (var n = 0; n < 13; n++) StoryLevel((c - 1) * 13 + n).world,
      ];
      expect(worlds.toSet(), WorldKind.values.toSet());
      for (var n = 0; n < 13; n++) {
        expect(StoryLevel((c - 1) * 13 + n).size, c, reason: 'size is the chapter');
      }
    }
    expect(StoryLevel(64).next, isNull);
  });

  test('3, 4, 5, then 6 balls; only the last two chapters offer the hard one', () {
    const counts = [3, 4, 5, 6, 6];
    for (final level in StoryLevel.all) {
      expect(level.balls.length, counts[level.chapter - 1]);
      expect(level.balls.toSet().length, level.balls.length, reason: 'no duplicates');
      expect(level.hardBall != null, level.chapter >= 4);
      if (level.hardBall != null) expect(level.balls.last, level.hardBall);
      expect(level.defaultBall, level.balls.first);
    }
  });

  test('stars: one for finishing, then by time; the hard ball earns the third early', () {
    final l = StoryLevel(13 * 3); // chapter 4
    final hard = l.hardBall!;
    expect(l.starsFor(l.goodSeconds + 1, BallKind.wood), 1);
    expect(l.starsFor(l.goodSeconds, BallKind.wood), 2);
    expect(l.starsFor(l.greatSeconds, BallKind.wood), 3);
    expect(l.starsFor(l.goodSeconds, hard), 3);
    expect(l.starsFor(l.goodSeconds + 1, hard), 1);
    final early = StoryLevel(0);
    expect(early.hardBall, isNull);
    expect(early.starsFor(early.goodSeconds, early.defaultBall), 2);
    for (final level in StoryLevel.all) {
      expect(level.greatSeconds, lessThan(level.goodSeconds));
    }
  });

  test('bigger mazes get longer times', () {
    for (var n = 0; n < 13; n++) {
      for (var c = 1; c < 5; c++) {
        expect(StoryLevel(c * 13 + n).goodSeconds,
            greaterThan(StoryLevel((c - 1) * 13 + n).goodSeconds));
      }
    }
  });

  test('star gates: never decreasing and always reachable with three stars everywhere', () {
    var last = 0;
    for (final level in StoryLevel.all) {
      expect(level.requiredStars, greaterThanOrEqualTo(last));
      last = level.requiredStars;
      expect(level.requiredStars, lessThanOrEqualTo(level.index * StoryLevel.maxStars));
    }
    expect(StoryLevel(0).requiredStars, 0);
    expect(StoryLevel(1).requiredStars, 0);
    expect(StoryLevel(9).requiredStars, 14);
  });

  test('progress keeps the best stars and time, and opens levels by total stars', () async {
    final p = StoryProgress.instance;
    expect(p.isUnlocked(StoryLevel(0)), isTrue);
    expect(p.isUnlocked(StoryLevel(9)), isFalse);
    expect(p.missingStars(StoryLevel(9)), 14);

    expect(await p.record(0, 2, 30000), 2);
    expect(await p.record(0, 1, 20000), 0, reason: 'worse stars add nothing');
    expect(p.stars(0), 2);
    expect(p.bestMillis(0), 20000);
    expect(await p.record(0, 3, 25000), 1);
    expect(p.stars(0), 3);
    expect(p.bestMillis(0), 20000);

    for (var i = 1; i <= 4; i++) {
      await p.record(i, 3, 10000);
    }
    expect(p.totalStars, 15);
    expect(p.isUnlocked(StoryLevel(9)), isTrue);
  });

  test('progress survives a restart', () async {
    await StoryProgress.instance.record(5, 2, 12345);
    StoryProgress.instance.resetForTest();
    expect(StoryProgress.instance.stars(5), 0);
    await StoryProgress.instance.load();
    expect(StoryProgress.instance.stars(5), 2);
    expect(StoryProgress.instance.bestMillis(5), 12345);
  });

  test('interstitial gate: every third level, never within 90 seconds', () {
    var now = DateTime(2026, 1, 1);
    final gate = AdGate(clock: () => now);
    gate.levelFinished();
    gate.levelFinished();
    expect(gate.due, isFalse);
    gate.levelFinished();
    expect(gate.due, isTrue);
    gate.shown();
    for (var i = 0; i < 3; i++) {
      gate.levelFinished();
    }
    expect(gate.due, isFalse, reason: 'too soon after the last ad');
    now = now.add(const Duration(seconds: 91));
    expect(gate.due, isTrue);
  });

  testWidgets('VIP skips interstitials and gives rewards at once; others see a closable blank ad',
      (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));

    Vip.instance.on = true;
    expect(await AdService.rewarded(ctx), isTrue);
    for (var i = 0; i < 3; i++) {
      AdGate.instance.levelFinished();
    }
    await AdService.interstitialIfDue(ctx);
    expect(find.byKey(const Key('ad-close')), findsNothing);
    AdGate.instance.shown();

    Vip.instance.on = false;
    final reward = AdService.rewarded(ctx);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ad-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ad-close')));
    await tester.pumpAndSettle();
    expect(await reward, isTrue);
  });

  test('a second chance puts the ball back, once per maze', () {
    final g = GameController(GameConfig(WorldKind.glass, 3), seed: 5);
    g.started = true;
    var guard = 0;
    while (g.status == GameStatus.playing && guard++ < 2000) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isTrue);
    expect(g.continueUsed, isFalse);
    expect(g.continueAfterLoss(), isTrue);
    expect(g.status, GameStatus.playing);
    expect(g.continueUsed, isTrue);
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.status, GameStatus.playing, reason: 'a few seconds of mercy');

    guard = 0;
    while (g.status == GameStatus.playing && guard++ < 4000) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isTrue);
    expect(g.continueAfterLoss(), isFalse, reason: 'only once per maze');
    g.newMaze();
    expect(g.continueUsed, isFalse);
  });

  testWidgets('the map shows all levels, locks the far ones and opens the start sheet',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: StoryMapScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    await tester.tap(find.byKey(const Key('story-node-0')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('story-ball-wood')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings has a VIP switch', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.byKey(const Key('vip-switch')));
    await tester.tap(find.byKey(const Key('vip-switch')));
    await tester.pump();
    expect(Vip.instance.on, isTrue);
  });

  test('a rewarded ad can put the ball back where it was before it was sent to the start', () {
    final g = GameController(GameConfig(WorldKind.ocean, 3), seed: 4);
    final spot = g.maze.cellCenter(g.maze.goal);
    g.pos = spot;
    g.caughtByJelly();
    expect(g.pos, g.maze.cellCenter(g.maze.start));
    expect(g.backLeft, greaterThan(0));
    g.returnToSpot();
    expect(g.pos, spot);
    expect(g.backLeft, 0);
    g.returnToSpot(); // nothing left to return to
    expect(g.pos, spot);
  });

  testWidgets('endless: continuing after a loss keeps the run; starting over resets it',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    GameController? g;
    for (var seed = 0; seed < 300 && g == null; seed++) {
      final c = GameController(GameController.endlessConfig(0, BallKind.wood),
          endless: true, seed: seed);
      c.started = true;
      c.pos = c.maze.cellCenter(c.maze.goal);
      var m = 0;
      while ((c.scrolling || c.stage == 0) && m++ < 600) {
        c.update(1 / 60, Offset.zero);
      }
      c.started = true;
      var n = 0;
      while (c.status == GameStatus.playing && n++ < 6000) {
        c.update(1 / 60, Offset.zero);
      }
      if (c.lost && c.stage >= 1) g = c;
    }
    final stage = g!.stage;
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(config: g.config, endless: true, controller: g),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('end-continue')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('ad-close')));
    await tester.pump(const Duration(seconds: 1));
    expect(g.status, GameStatus.playing);
    expect(g.stage, stage, reason: 'the run goes on');
  });

  testWidgets('"try again" always shows an ad, except for a VIP', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ));
    final shown = AdService.interstitialAlways(ctx);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ad-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ad-close')));
    await tester.pumpAndSettle();
    await shown;

    Vip.instance.on = true;
    await AdService.interstitialAlways(ctx);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ad-close')), findsNothing);
  });
}
