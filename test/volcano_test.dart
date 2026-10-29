import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/rect_maze.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/game_painter.dart';
import 'package:orbyrinth/ui/game_screen.dart';
import 'package:orbyrinth/ui/maze_art.dart';
import 'package:orbyrinth/ui/worlds.dart';

GameController volcano({int level = 3, int seed = 3, BallKind ball = BallKind.wood}) =>
    GameController(GameConfig(WorldKind.volcano, level, ball: ball), seed: seed);

/// Runs the game until [done] holds, with the ball kept still at [at].
void waitFor(GameController g, bool Function() done, {Offset? at}) {
  var guard = 0;
  while (!done() && guard++ < 2000) {
    if (at != null) g.pos = at;
    g.vel = Offset.zero;
    g.update(1 / 60, Offset.zero);
  }
  expect(done(), isTrue, reason: 'timed out');
}

void main() {
  test('the volcano is laid out on every level, clear of the start and exit', () {
    for (var level = 1; level <= 5; level++) {
      for (var seed = 0; seed < 6; seed++) {
        final g = volcano(level: level, seed: seed);
        final start = g.maze.cellCenter(g.maze.start);
        final goal = g.maze.cellCenter(g.maze.goal);
        expect(g.lavas.length, inInclusiveRange(1, g.config.lavaCount), reason: 'lava $level/$seed');
        expect(g.geysers.length, g.config.geyserCount, reason: 'geysers $level/$seed');
        expect(g.crusts.length, g.config.crustCount, reason: 'crusts $level/$seed');
        final spots = [
          for (final l in g.lavas) l.center,
          for (final v in g.geysers) v.pos,
          for (final k in g.crusts) k.pos,
        ];
        for (final p in spots) {
          expect((p - start).distance, greaterThan(2.4));
          expect((p - goal).distance, greaterThan(0.5));
        }
        expect(spots.toSet().length, spots.length, reason: 'no two on the same cell');
        expect(g.creatures, isEmpty);
        expect(g.mud, isEmpty);
        g.dispose();
      }
    }
  });

  test('lava floods the route in a rhythm and kills only while molten', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    final lava = g.lavas.first;
    // Crusted over, it is a floor like any other.
    waitFor(g, () => g.lavaPhase(lava) == 0 && g.lavaTime(lava) < g.config.lavaPeriod - 3.5);
    g.pos = lava.center;
    g.update(1 / 60, Offset.zero);
    expect(g.status, GameStatus.playing);
    // It warns, then floods.
    final seen = <int>{};
    var guard = 0;
    while (g.status == GameStatus.playing && guard++ < 2000) {
      g.pos = lava.center;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      seen.add(g.lavaPhase(lava));
    }
    expect(g.lostReason, 'lose.lava');
    expect(seen, containsAll([0, 1, 2]));
  });

  test('lava next to the ball but outside the stretch does not hurt', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    final lava = g.lavas.first;
    final side = Offset(-lava.along.dy, lava.along.dx);
    waitFor(g, () => g.lavaPhase(lava) == 2, at: g.maze.cellCenter(g.maze.start));
    g.pos = lava.center + side * (GameController.lavaWidth + 0.1);
    g.update(1 / 60, Offset.zero);
    expect(g.lostReason, isNot('lose.lava'));
  });

  test('a geyser hisses, then erupts and shoves the ball away', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    final vent = g.geysers.first;
    final home = g.maze.cellCenter(g.maze.start);
    final seen = <int>{};
    var guard = 0;
    while (g.geyserPhase(vent) != 2 && guard++ < 2000) {
      g.pos = home;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      seen.add(g.geyserPhase(vent));
    }
    expect(seen, containsAll([0, 1]));
    expect(g.geyserPhase(vent), 2);
    var pushed = false;
    for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
      g.pos = vent.pos + dir * 0.9;
      g.vel = Offset.zero;
      final before = (g.pos - vent.pos).distance;
      g.update(1 / 30, Offset.zero);
      if ((g.pos - vent.pos).distance > before + 0.001) pushed = true;
    }
    expect(pushed, isTrue, reason: 'the jet pushes the ball away from the vent');
    expect(g.status, GameStatus.playing, reason: 'outside the middle it only shoves');
  });

  test('standing over the vent when it erupts throws the ball to a safe spot', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    final vent = g.geysers.first;
    waitFor(g, () => g.geyserPhase(vent) == 2, at: g.maze.cellCenter(g.maze.start));
    g.pos = vent.pos;
    g.update(1 / 60, Offset.zero);
    expect(g.lost, isFalse, reason: 'it does not kill');
    expect((g.pos - vent.pos).distance, greaterThanOrEqualTo(1.0));
    expect(g.pos, isNot(g.maze.cellCenter(g.maze.start)), reason: 'not sent back to the start');
    expect(g.maze.cellCenter(g.maze.goal), isNot(g.pos));
    for (final l in g.lavas) {
      expect((l.center - g.pos).distance, greaterThanOrEqualTo(0.7));
    }
    for (final k in g.crusts) {
      expect((k.pos - g.pos).distance, greaterThanOrEqualTo(0.7));
    }
    for (final o in g.geysers) {
      expect((o.pos - g.pos).distance, greaterThanOrEqualTo(0.7));
    }
    // One throw per eruption: landing back on it in the same eruption does nothing.
    final landed = g.pos;
    g.pos = vent.pos;
    g.update(1 / 60, Offset.zero);
    expect((g.pos - vent.pos).distance, lessThan(0.1), reason: 'not thrown a second time');
    expect((landed - vent.pos).distance, greaterThan(0.5));
  });

  test('thin crust cracks under a ball that stands still, then gives way', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    g.lavas.clear();
    g.geysers.clear();
    final crust = g.crusts.first;
    final seen = <int>{};
    var guard = 0;
    while (g.status == GameStatus.playing && guard++ < 2000) {
      g.pos = crust.pos;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      seen.add(crust.stage);
    }
    expect(g.lostReason, 'lose.crust');
    expect(seen, containsAll([0, 1, 2, 3]));
    expect(g.elapsed, closeTo(g.config.crustSeconds, 0.6));
  });

  test('a ball that keeps moving crosses crust safely, and cracks mend', () {
    final g = volcano(level: 5, seed: 2);
    g.started = true;
    g.lavas.clear();
    g.geysers.clear();
    final crust = g.crusts.first;
    for (var i = 0; i < 60; i++) {
      g.pos = crust.pos;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(crust.level, greaterThan(0.2));
    final before = crust.level;
    g.pos = g.maze.cellCenter(g.maze.start);
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(crust.level, lessThan(before));
    // Rolling across at speed never cracks it.
    crust.level = 0;
    for (var i = 0; i < 30; i++) {
      g.pos = crust.pos;
      g.vel = const Offset(2.5, 0);
      g.update(1 / 60, Offset.zero);
    }
    expect(crust.level, 0);
    expect(g.status, GameStatus.playing);
  });

  test('a bomb warns, blasts where it lands and burns for a while', () {
    final g = volcano(level: 3, seed: 5);
    g.started = true;
    g.lavas.clear();
    g.geysers.clear();
    g.crusts.clear();
    g.spawnTrap();
    expect(g.hazards, hasLength(1));
    final bomb = g.hazards.first;
    expect(bomb.life, closeTo(bomb.armAt + GameController.bombFireSeconds, 1e-9));
    expect((bomb.pos - g.pos).distance, greaterThan(GameController.minBoulderDistance - 1.0));
    // Standing in the fire kills; the blast marks the spot.
    var guard = 0;
    while (!bomb.armed && guard++ < 600) {
      g.update(1 / 60, Offset.zero);
    }
    expect(bomb.armed, isTrue);
    expect(g.status, GameStatus.playing);
    g.pos = bomb.pos;
    g.update(1 / 60, Offset.zero);
    expect(g.lostReason, 'lose.bomb');
  });

  test('the cooling bonus crusts the lava, calms the geysers and stops the bombs', () {
    final g = volcano(level: 4, seed: 7);
    g.started = true;
    g.bonusCharges = 1;
    g.useBonus();
    g.spawnTrap();
    g.update(1 / 60, Offset.zero);
    expect(g.hazards, isEmpty);
    for (final l in g.lavas) {
      expect(g.lavaPhase(l), 0);
    }
    for (final v in g.geysers) {
      expect(g.geyserPhase(v), 0);
    }
    final crust = g.crusts.first;
    for (var i = 0; i < 60 * 4; i++) {
      g.pos = crust.pos;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.status, GameStatus.playing, reason: 'nothing hurts while it cools');
    expect(crust.level, 0);
    g.pos = g.lavas.first.center;
    g.update(1 / 60, Offset.zero);
    expect(g.status, GameStatus.playing);
  });

  test('the world has a theme, texts in every language and a note', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.volcano);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(hazardNote(const GameConfig(WorldKind.volcano, 3)), isNot(startsWith('note.')));
      expect(tr('bonus.volcano'), isNot(startsWith('bonus.')));
      for (final key in ['lose.lava', 'lose.steam', 'lose.crust', 'lose.bomb']) {
        expect(tr(key), isNot(startsWith('lose.')), reason: '$key in ${lang.name}');
      }
    }
    AppLanguage.instance.lang = AppLang.pl;
  });

  test('every part of the volcano can be painted, in every phase', () {
    for (final level in [1, 5]) {
      final g = volcano(level: level, seed: 4);
      final render = MazeRender(g.maze, themeFor(WorldKind.volcano));
      final painter = GamePainter(g, render);
      g.started = true;
      g.bonusCharges = 1;
      for (var i = 0; i < 60 * 14; i++) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        if (i == 60 * 7) g.useBonus();
        if (i % 12 == 0) {
          if (g.status != GameStatus.playing) g.restart();
          g.started = true;
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(390, 844));
          rec.endRecording();
        }
      }
      g.dispose();
    }
  });

  test('the rectangular volcano maze can be painted and played in endless mode', () {
    for (var seed = 0; seed < 300; seed++) {
      final g = GameController(
        GameController.endlessConfig(0, BallKind.wood),
        endless: true,
        seed: seed,
      );
      if (g.config.world != WorldKind.volcano) {
        g.dispose();
        continue;
      }
      expect(g.maze, isA<RectMaze>());
      expect(g.lavas, isNotEmpty);
      final picture = buildRectMazePicture(g.maze as RectMaze, themeFor(WorldKind.volcano), 1);
      expect(picture, isNotNull);
      return;
    }
    fail('no seed starts in the volcano');
  });

  testWidgets('the volcano world draws on a phone', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(config: GameConfig(WorldKind.volcano, 3, ball: BallKind.paper)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
