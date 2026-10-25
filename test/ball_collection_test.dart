import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/ball_collection.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/story.dart';
import 'package:orbyrinth/game/story_progress.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/ui/ball_shop.dart';
import 'package:orbyrinth/ui/menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StoryProgress.instance.resetForTest();
    await BallCollection.instance.reset();
  });

  test('the player starts with wood, rubber and stone', () {
    expect(BallCollection.instance.owned,
        [BallKind.wood, BallKind.rubber, BallKind.stone]);
    expect(BallCollection.instance.locked.length, 6);
  });

  test('each of the 9 balls has exactly one way to be earned', () {
    final all = <BallKind>[
      ...BallCollection.starters,
      ...BallCollection.chapterRewards,
      BallCollection.starsBall,
    ];
    expect(all.toSet(), BallKind.values.toSet());
    expect(all.length, 9);
    expect(BallCollection.starsNeeded, 190);
  });

  test('every story level offers at least one starter ball', () {
    for (final level in StoryLevel.all) {
      expect(level.balls.any(BallCollection.starters.contains), isTrue,
          reason: 'level ${level.index} (${level.world.name}, chapter ${level.chapter})');
      expect(BallCollection.starters.contains(level.defaultBallFor(BallCollection.starters)),
          isTrue);
    }
  });

  test('a finished chapter gives its ball, once', () async {
    final p = StoryProgress.instance;
    for (var n = 0; n < 12; n++) {
      await p.record(n, 1, 1000);
    }
    expect(await BallCollection.instance.grantRewards(p), isEmpty,
        reason: 'one level of the chapter is still missing');
    await p.record(12, 1, 1000);
    expect(await BallCollection.instance.grantRewards(p), [BallKind.steel]);
    expect(BallCollection.instance.owns(BallKind.steel), isTrue);
    expect(await BallCollection.instance.grantRewards(p), isEmpty);
  });

  test('nearly all the stars give the last ball', () async {
    final p = StoryProgress.instance;
    for (var i = 0; i < StoryLevel.count; i++) {
      await p.record(i, i < 63 ? 3 : 0 + 1, 1000);
    }
    expect(p.totalStars, 63 * 3 + 2);
    final fresh = await BallCollection.instance.grantRewards(p);
    expect(fresh, contains(BallKind.chameleon));
    expect(fresh, containsAll(BallCollection.chapterRewards));
    expect(BallCollection.instance.locked, isEmpty);
  });

  test('ownership is remembered', () async {
    await BallCollection.instance.unlock(BallKind.glass);
    await BallCollection.instance.reset();
    expect(BallCollection.instance.owns(BallKind.glass), isFalse);
    await BallCollection.instance.unlock(BallKind.glass);
    SharedPreferences.setMockInitialValues(
        {'balls_v1': ['glass']}); // a fresh launch reads what was saved
    await BallCollection.instance.load();
    expect(BallCollection.instance.owns(BallKind.glass), isTrue);
    expect(BallCollection.instance.owns(BallKind.wood), isTrue);
    expect(BallCollection.instance.owns(BallKind.steel), isFalse);
  });

  test('endless only brings up balls from the pool', () {
    const pool = [BallKind.wood, BallKind.rubber, BallKind.stone];
    final g = GameController(
      GameController.endlessConfig(0, BallKind.wood),
      endless: true,
      ballPool: pool,
      seed: 2,
    );
    expect(pool, contains(g.config.ball));
    for (var i = 0; i < 20; i++) {
      g.pos = g.maze.cellCenter(g.maze.goal);
      g.started = true;
      var m = 0;
      final stage = g.stage;
      while ((g.scrolling || g.stage == stage) && g.status == GameStatus.playing && m++ < 600) {
        g.update(1 / 60, Offset.zero);
      }
      if (g.status != GameStatus.playing) g.resetRun();
      expect(pool, contains(g.config.ball));
    }
  });

  testWidgets('the shop buys one ball or all of them', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(onPressed: () => showBallShop(c), child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('buy-ball-wood')), findsNothing, reason: 'already owned');
    await tester.ensureVisible(find.byKey(const Key('buy-ball-glass')));
    await tester.tap(find.byKey(const Key('buy-ball-glass')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(BallCollection.instance.owns(BallKind.glass), isTrue);
    await tester.ensureVisible(find.byKey(const Key('buy-all-balls')));
    await tester.tap(find.byKey(const Key('buy-all-balls')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(BallCollection.instance.locked, isEmpty);
  });

  testWidgets('a locked ball in the picker opens the shop instead of being chosen',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SelectScreen()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    await tester.ensureVisible(find.byIcon(Icons.lock_rounded).first);
    await tester.tap(find.byIcon(Icons.lock_rounded).first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('restore-purchases')), findsOneWidget);
    expect(GameConfig(WorldKind.forest, 1).ball, BallKind.wood);
  });
}
