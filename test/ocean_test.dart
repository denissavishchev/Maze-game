import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/rect_maze.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/game_screen.dart';
import 'package:maze/ui/maze_art.dart';
import 'package:maze/ui/worlds.dart';

GameController ocean({int level = 3, int seed = 3, BallKind ball = BallKind.wood}) =>
    GameController(GameConfig(WorldKind.ocean, level, ball: ball), seed: seed);

void main() {
  test('the ocean has whirlpools well away from the start and nothing else', () {
    final g = ocean();
    expect(g.whirls.length, g.config.whirlCount);
    for (final w in g.whirls) {
      expect((w.pos - g.pos).distance, greaterThan(3.5));
    }
    expect(g.creatures, isEmpty);
    expect(g.mud, isEmpty);
    expect(g.beams, isEmpty);
    expect(g.config.windEnabled, isTrue, reason: 'currents on every size');
  });

  test('whirlpools drift along the corridors', () {
    final g = ocean(level: 4, seed: 6);
    g.started = true;
    final start = [for (final w in g.whirls) w.pos];
    for (var i = 0; i < 60 * 6; i++) {
      g.vel = const Offset(0.0, 0.0);
      g.pos = g.maze.cellCenter(g.maze.start);
      g.update(1 / 60, Offset.zero);
    }
    for (var i = 0; i < g.whirls.length; i++) {
      expect((g.whirls[i].pos - start[i]).distance, greaterThan(0.5));
    }
  });

  test('a whirlpool pulls the ball in, and its eye swallows it', () {
    final g = ocean(level: 3, seed: 4);
    g.started = true;
    final w = g.whirls.first;
    w.route.clear();
    g.pos = w.pos + const Offset(0.9, 0);
    g.vel = Offset.zero;
    final d0 = (g.pos - w.pos).distance;
    g.update(1 / 30, Offset.zero);
    expect((g.pos - w.pos).distance, lessThan(d0), reason: 'pulled in');
    g.pos = w.pos + const Offset(0.1, 0);
    g.update(1 / 60, Offset.zero);
    expect(g.lostReason, 'lose.whirl');
  });

  test('heavy balls resist a whirlpool better than paper', () {
    double pulled(BallKind b) {
      final g = ocean(level: 3, seed: 4, ball: b);
      g.started = true;
      final w = g.whirls.first..route.clear();
      g.pos = w.pos + const Offset(1.0, 0);
      g.vel = Offset.zero;
      g.update(1 / 30, Offset.zero);
      return g.vel.distance;
    }

    expect(pulled(BallKind.stone), lessThan(pulled(BallKind.paper)));
  });

  test('currents come with a warning and carry the ball', () {
    final g = ocean(level: 3, seed: 2);
    g.started = true;
    var guard = 0;
    while (g.windWarnLeft <= 0 && guard++ < 2000) {
      g.whirls.clear();
      g.update(1 / 60, Offset.zero);
    }
    expect(g.windWarnLeft, greaterThan(0));
    expect(g.notice, 'notice.current');
    while (g.windLeft <= 0) {
      g.update(1 / 60, Offset.zero);
    }
    final from = g.vel.distance;
    g.update(0.1, Offset.zero);
    expect(g.vel.distance, greaterThan(from));
  });

  test('the anchor freezes whirlpools and currents', () {
    final g = ocean(level: 3, seed: 4);
    g.started = true;
    g.bonusCharges = 1;
    g.useBonus();
    final w = g.whirls.first;
    final at = w.pos;
    g.pos = w.pos + const Offset(0.1, 0);
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.status, GameStatus.playing);
    expect(w.pos, at);
  });

  test('the world has a theme and texts in every language', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.ocean);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(hazardNote(const GameConfig(WorldKind.ocean, 3)), isNot(startsWith('note.')));
      for (final k in ['bonus.ocean', 'current.now', 'current.coming', 'lose.whirl', 'notice.current']) {
        expect(tr(k), isNot(k), reason: '$k in ${lang.name}');
      }
    }
    AppLanguage.instance.lang = AppLang.pl;
  });

  testWidgets('the ocean draws, and so does the rectangular maze', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(config: GameConfig(WorldKind.ocean, 3, ball: BallKind.paper)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    final rect = RectMaze.generate(cols: 6, rows: 9, gates: 2);
    expect(buildRectMazePicture(rect, themeFor(WorldKind.ocean), 1), isNotNull);
  });
}
