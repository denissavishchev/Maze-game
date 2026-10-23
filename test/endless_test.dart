import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/rect_maze.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/game_screen.dart';
import 'package:maze/ui/home_screen.dart';
import 'package:maze/ui/menu_screen.dart';

RectMaze rectOf(GameController g) => g.maze as RectMaze;

/// Rolls the ball out of the exit in the bottom wall, then lets the screen
/// scroll to the next maze.
void finishMaze(GameController g) {
  final m = rectOf(g);
  g.pos = Offset(m.goalCol + 0.5, m.rows + 0.05);
  g.update(1 / 60, Offset.zero);
  var guard = 0;
  while (g.scrolling && guard++ < 600) {
    g.update(1 / 60, Offset.zero);
  }
}

void main() {
  test('bonuses on every other round of five levels', () {
    for (var stage = 0; stage < 30; stage++) {
      final c = GameController.endlessConfig(stage, BallKind.wood);
      expect(c.level, GameConfig.minLevel);
      expect(c.buttonCount, 3, reason: '3 stars per level');
      expect(c.bonusCount, (stage ~/ 5).isOdd ? 1 : 0, reason: 'stage $stage bonuses');
    }
  });

  test('the first world is random, and no world repeats one of the last three', () {
    final firsts = <WorldKind>{};
    for (var seed = 0; seed < 40; seed++) {
      final g = GameController(GameController.endlessConfig(0, BallKind.wood),
          endless: true, seed: seed);
      firsts.add(g.config.world);
    }
    expect(firsts.length, WorldKind.values.length, reason: 'any world can come first');

    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, hazardsEnabled: false, seed: 11);
    final played = [g.config.world];
    for (var i = 0; i < 60; i++) {
      finishMaze(g);
      played.add(g.config.world);
    }
    for (var i = 3; i < played.length; i++) {
      expect(played.sublist(i - 3, i), isNot(contains(played[i])),
          reason: 'stage $i (${played[i].name}) repeats one of the last three');
    }
    expect(played.toSet().length, WorldKind.values.length, reason: 'all of them turn up');
  });

  test('the maze is rectangular: start in the top row, exit in the bottom row', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, seed: 1);
    for (var i = 0; i < 20; i++) {
      final m = rectOf(g);
      expect(m.fullView, isTrue);
      expect(m.cols, g.endlessCols);
      expect(m.rows, g.endlessRows);
      expect(m.rowOf(m.start), 0, reason: 'the ball starts at the top');
      expect(m.rowOf(m.goal), m.rows - 1, reason: 'and has to get to the bottom');
      expect(g.pos, m.cellCenter(m.start));
      expect(m.gateCount, 3);
      g.newMaze();
    }
  });

  test('the grid fills the room on the screen with square cells', () {
    for (final (w, h) in [(402.0, 700.0), (390.0, 650.0), (360.0, 560.0), (430.0, 780.0)]) {
      final (cols, rows) = GameController.gridFor(w, h);
      expect(GameController.endlessColsChoices, contains(cols));
      final cell = w / (cols + RectMaze.padX);
      final left = h - (rows + RectMaze.padTop + RectMaze.padBottom) * cell;
      expect(left, greaterThanOrEqualTo(-1e-6), reason: '$w x $h: fits');
      expect(left, lessThan(cell), reason: '$w x $h: less than a cell left over');
    }
    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, seed: 1);
    g.fitGrid(6, 14);
    expect((rectOf(g).cols, rectOf(g).rows), (6, 14));
  });

  test('every rectangular maze is solvable through its gates, in order', () {
    final rnd = Random(4);
    for (var i = 0; i < 60; i++) {
      final m = RectMaze.generate(cols: 7, rows: 12, gates: 3, random: rnd);
      final open = List<bool>.filled(3, false);
      for (var j = 0; j < 3; j++) {
        expect(m.path(m.start, m.goal, open), isNull,
            reason: 'gate $j must block the way while closed');
        // The button for gate j can be reached while gate j (and later) are shut.
        expect(m.path(m.start, m.buttonCells[j], open), isNotNull,
            reason: 'maze $i: button $j is reachable before its gate opens');
        open[j] = true;
      }
      expect(m.path(m.start, m.goal, open), isNotNull, reason: 'maze $i solvable');
      // A perfect maze: every cell can be reached and there are no loops.
      final everywhere = List<bool>.filled(3, true);
      for (var c = 0; c < m.cellCount; c++) {
        expect(m.path(m.start, c, everywhere), isNotNull);
      }
      final passages = m.open.where((o) => o).length;
      expect(passages, m.cellCount - 1, reason: 'a spanning tree has no loops');
    }
  });

  test('walls hold the ball in; only the exit leads out, at the bottom', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, hazardsEnabled: false, seed: 9);
    final m = rectOf(g);
    expect(m.cols, g.endlessCols);
    // Push hard against every side for a while: the ball never leaves, except
    // down through the exit (which starts the next maze).
    for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, -1)]) {
      for (var i = 0; i < 400; i++) {
        g.update(1 / 60, dir);
      }
      expect(g.pos.dx, inInclusiveRange(0, m.cols.toDouble()));
      expect(g.pos.dy, inInclusiveRange(0, m.rows.toDouble()));
      expect(g.stage, 0);
    }
    // The bottom wall is solid beside the exit...
    final far = m.goalCol < m.cols ~/ 2 ? m.cols - 1 : 0;
    g.pos = Offset(far + 0.5, m.rows - 0.5);
    for (var i = 0; i < 200; i++) {
      g.update(1 / 60, const Offset(0, 1));
    }
    expect(g.pos.dy, lessThan(m.rows.toDouble()));
    expect(g.stage, 0);
    // ...and the entrance in the top wall is open in the start column only.
    expect(m.segmentsNear(Offset(m.startCol + 0.5, 0.2)).any((s) =>
        s.a.dy == 0 && s.b.dy == 0 && s.a.dx <= m.startCol + 0.5 && s.b.dx >= m.startCol + 0.5),
        isFalse);
  });

  test('an autopilot can walk the whole maze, out through the exit', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, hazardsEnabled: false, seed: 9);
    final first = g.maze;
    var guard = 0;
    while (g.maze == first && guard++ < 20000) {
      final next = g.buttonUsed.indexOf(false);
      final m = rectOf(g);
      final Offset to;
      if (next < 0 && m.cellAt(g.pos) == m.goal) {
        to = Offset(m.goalCol + 0.5, m.rows + 0.5); // out through the exit
      } else {
        final target = next >= 0 ? m.buttonCells[next] : m.goal;
        final route = m.path(m.cellAt(g.pos), target, g.gateOpen)!;
        final points = m.routePoints(route).skip(1).toList();
        to = points.isEmpty ? m.cellCenter(target) : points.first;
      }
      final d = to - g.pos;
      g.update(1 / 60, d.distance < 1e-6 ? Offset.zero : d / d.distance * 0.7);
    }
    expect(g.maze, isNot(same(first)), reason: 'left through the exit: next world');
    expect(g.stage, 1);
  });

  test('leaving through the exit scrolls into the next world, which starts below it', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, seed: 3);
    expect(g.bonusCells, isEmpty);
    g.update(1 / 60, const Offset(1, 0)); // first tilt starts the clock
    for (var i = 0; i < 59; i++) {
      g.update(1 / 60, Offset.zero);
    }
    final before = g.elapsed;
    expect(before, greaterThan(0.9));

    final firstWorld = g.config.world;
    final firstMaze = rectOf(g);
    final exitCol = firstMaze.goalCol;
    final m = firstMaze;
    g.pos = Offset(exitCol + 0.5, m.rows + 0.05);
    g.update(1 / 60, Offset.zero);
    expect(g.status, GameStatus.playing, reason: 'endless never ends by winning');
    expect(g.stage, 1);
    expect(g.config.world, isNot(firstWorld), reason: 'a different world');
    expect(g.scrolling, isTrue);
    expect(g.prevMaze, same(firstMaze));
    expect(rectOf(g).startCol, exitCol, reason: 'the next maze starts right below the exit');

    // The ball rolls on into it while the screen scrolls; the clock keeps its time.
    var last = g.pos.dy;
    while (g.scrolling) {
      g.update(1 / 60, const Offset(1, 0));
      expect(g.pos.dy, greaterThanOrEqualTo(last), reason: 'only moves on, downwards');
      expect(g.pos.dx, rectOf(g).cellCenter(rectOf(g).start).dx);
      last = g.pos.dy;
    }
    expect(g.prevMaze, isNull);
    expect(g.pos, rectOf(g).cellCenter(rectOf(g).start));
    expect(g.elapsed, closeTo(before, 0.05));
    expect(g.pressedCount, 0, reason: 'stars start empty on the new level');
    expect(g.notice, 'notice.level');

    // Through to the sixth level: back to the first world, now with a bonus.
    for (var i = 0; i < 4; i++) {
      finishMaze(g);
    }
    expect(g.stage, 5);
    expect(g.bonusCells, hasLength(1));
    // And the eleventh: no bonuses again.
    for (var i = 0; i < 5; i++) {
      finishMaze(g);
    }
    expect(g.stage, 10);
    expect(g.bonusCells, isEmpty);
  });

  test('reset starts the run again from level 1 with the clock at zero', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.steel),
        endless: true, seed: 5);
    g.update(1 / 60, const Offset(1, 0));
    finishMaze(g);
    finishMaze(g);
    expect(g.stage, 2);
    g.resetRun();
    expect(g.stage, 0);
    expect(g.config.ball, BallKind.steel, reason: 'the chosen ball stays');
    expect(g.elapsed, 0);
    expect(g.scrolling, isFalse);
  });

  test('a single level still ends when the centre is reached', () {
    final g = GameController(const GameConfig(WorldKind.forest, 1), seed: 3);
    g.pos = Offset.zero;
    g.update(1 / 60, Offset.zero);
    expect(g.won, isTrue);
  });

  testWidgets('home screen offers both modes', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('play.endless')), findsOneWidget);
    expect(find.text(tr('play.single')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home screen buttons fit in every language', (tester) async {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    for (final lang in AppLang.values) {
      // ignore: unawaited_futures
      AppLanguage.instance.set(lang);
      for (final size in [const Size(320, 568), const Size(360, 640), const Size(390, 844)]) {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '${lang.name} at $size');
        expect(find.text(tr('play.endless')), findsOneWidget);
        expect(find.text(tr('play.single')), findsOneWidget);
      }
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('endless start screen: description, ball choice, back and play', (tester) async {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    for (final lang in AppLang.values) {
      // ignore: unawaited_futures
      AppLanguage.instance.set(lang);
      for (final size in [const Size(360, 640), const Size(320, 568), const Size(390, 844)]) {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.3)),
            child: const MaterialApp(home: SelectScreen(endless: true)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(tr('endless.title')), findsOneWidget);
        expect(find.text(tr('endless.desc')), findsOneWidget);
        expect(find.text(tr('sel.ball')), findsOneWidget);
        expect(find.text(tr('sel.world')), findsNothing);
        expect(find.text(tr('sel.size')), findsNothing);
        expect(find.text(tr('play')), findsOneWidget);
        expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '${lang.name} at $size');
      }
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('endless game: header has calibration, no stars and no restart; the maze fills the rest',
      (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: GameScreen(
        config: GameController.endlessConfig(0, BallKind.wood),
        endless: true,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.byIcon(Icons.replay_rounded), findsNothing);
    expect(find.byIcon(Icons.screen_rotation_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    for (final icon in [
      Icons.bedtime_rounded,
      Icons.shield_rounded,
      Icons.landslide_rounded,
      Icons.light_mode_rounded,
      Icons.power_settings_new_rounded,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: 'no bonus on the first five levels');
    }
    // The maze starts right under the header.
    final painter = find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null).last;
    final top = tester.getTopLeft(painter).dy;
    final cal = tester.getBottomLeft(find.byIcon(Icons.screen_rotation_alt_rounded)).dy;
    expect(top - cal, lessThan(30), reason: 'nothing between the header and the maze');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('single level: calibration moved to the top bar too', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(config: GameConfig(WorldKind.forest, 2)),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.screen_rotation_alt_rounded), findsOneWidget);
    expect(tester.getTopLeft(find.byIcon(Icons.screen_rotation_alt_rounded)).dy, lessThan(120));
    expect(find.text(tr('cal.label')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
