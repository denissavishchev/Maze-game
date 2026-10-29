
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/rect_maze.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/game_screen.dart';
import 'package:orbyrinth/ui/maze_art.dart';
import 'package:orbyrinth/ui/worlds.dart';

GameController glass({int level = 3, int seed = 3}) =>
    GameController(GameConfig(WorldKind.glass, level), seed: seed);

/// An endless run that happens to start in the glass world.
GameController endlessGlass() {
  for (var seed = 0; seed < 200; seed++) {
    final g = GameController(
      GameController.endlessConfig(0, BallKind.wood),
      endless: true,
      seed: seed,
    );
    if (g.config.world == WorldKind.glass) return g;
    g.dispose();
  }
  throw StateError('no seed starts in the glass world');
}

void main() {
  test('the glass world has no creatures, bogs or ship lasers', () {
    final g = glass();
    expect(g.lasers, isEmpty);
    expect(g.mud, isEmpty);
    expect(g.creatures, isEmpty);
    expect(g.cracks, isEmpty);
    expect(g.beams, isEmpty);
  });

  test('the floor cracks in four stages under a ball that stands still, then gives way', () {
    final g = glass(level: 3, seed: 5);
    g.started = true;
    final seen = <int>{};
    var guard = 0;
    while (g.status == GameStatus.playing && guard++ < 2000) {
      g.update(1 / 60, Offset.zero);
      if (g.cracks.isNotEmpty) seen.add(g.cracks.first.stage);
    }
    expect(g.lostReason, 'lose.floor');
    expect(seen, containsAll([0, 1, 2, 3]));
    // Roughly the configured time.
    expect(g.elapsed, closeTo(g.config.crumbleSeconds, 0.6));
  });

  test('a ball that keeps moving never breaks the floor, and cracks mend', () {
    final g = glass(level: 5, seed: 2);
    g.started = true;
    // Stand for a while (less than it takes to fall through), then roll on.
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.cracks, isNotEmpty);
    final before = g.cracks.first.level;
    expect(before, greaterThan(0));
    g.vel = const Offset(3, 0);
    for (var i = 0; i < 20; i++) {
      g.vel = const Offset(3, 0);
      g.update(1 / 60, const Offset(1, 0));
    }
    expect(g.status, GameStatus.playing);
  });

  test('a laser warns first, then burns the whole row or column', () {
    final g = endlessGlass();
    g.started = true;
    // Wait for the first beam.
    var guard = 0;
    while (g.beams.isEmpty && guard++ < 3000) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = const Offset(2, 0);
      g.update(1 / 60, Offset.zero);
    }
    expect(g.beams, isNotEmpty);
    final b = g.beams.first;
    expect(b.burning, isFalse);
    final m = g.maze as RectMaze;
    final horizontal = b.a.dy == b.b.dy;
    // Spans the entire maze.
    expect(horizontal ? (b.b.dx - b.a.dx).abs() : (b.b.dy - b.a.dy).abs(),
        greaterThan(horizontal ? m.cols : m.rows));
    // Standing in its way during the warning is safe; once it burns it kills.
    g.pos = horizontal ? Offset(1.5, b.a.dy) : Offset(b.a.dx, 1.5);
    g.vel = Offset.zero;
    g.update(0.1, Offset.zero);
    expect(g.status, GameStatus.playing);
    g.beams.first.age = GlassBeam.warning + 0.1;
    g.pos = horizontal ? Offset(1.5, b.a.dy) : Offset(b.a.dx, 1.5);
    g.update(1 / 60, Offset.zero);
    expect(g.lostReason, 'lose.laser');
  });

  test('a laser in the round maze is a chord from edge to edge', () {
    final g = glass(level: 2, seed: 8);
    g.started = true;
    var guard = 0;
    while (g.beams.isEmpty && guard++ < 3000) {
      g.vel = const Offset(2, 0);
      g.update(1 / 60, Offset.zero);
      if (g.status != GameStatus.playing) g.restart();
      g.started = true;
    }
    expect(g.beams, isNotEmpty);
    final b = g.beams.first;
    expect(b.a.distance, closeTo(b.b.distance, 3));
    expect(b.a.distance, greaterThan(g.maze.radius * 0.7));
    expect(b.b.distance, greaterThan(g.maze.radius * 0.7));
  });

  test('the prism bonus switches the floor and lasers off', () {
    final g = glass(level: 3, seed: 5);
    g.started = true;
    g.bonusCharges = 1;
    g.useBonus();
    for (var i = 0; i < 60 * 8; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.status, GameStatus.playing, reason: 'nothing hurts under the prism');
    expect(g.cracks.where((k) => k.level > 0), isEmpty);
    g.beams.add(GlassBeam(Offset(-9, g.pos.dy), Offset(9, g.pos.dy), 0.4)..age = 1.5);
    g.update(1 / 60, Offset.zero);
    expect(g.status, GameStatus.playing);
  });

  test('the world has a theme, texts in every language and a note', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.glass);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(hazardNote(const GameConfig(WorldKind.glass, 3)), isNot(startsWith('note.')));
      expect(tr('bonus.glass'), isNot(startsWith('bonus.')));
      expect(GameController.bonusName(WorldKind.glass), tr('bonus.glass'));
    }
    AppLanguage.instance.lang = AppLang.pl;
  });

  testWidgets('the glass world draws, in the round maze and in endless mode', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(config: GameConfig(WorldKind.glass, 3, ball: BallKind.paper)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('the rectangular glass maze can be painted', () {
    final g = endlessGlass();
    final picture = buildRectMazePicture(g.maze as RectMaze, themeFor(WorldKind.glass), 1);
    expect(picture, isNotNull);
  });
}
