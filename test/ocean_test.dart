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
  test('the ocean has jellyfish well away from the start and nothing else', () {
    final g = ocean();
    expect(g.jellies.length, g.config.jellyCount);
    for (final j in g.jellies) {
      expect((j.pos - g.pos).distance, greaterThan(2.9));
    }
    expect(g.creatures, isEmpty);
    expect(g.mud, isEmpty);
    expect(g.beams, isEmpty);
    expect(g.config.windEnabled, isTrue, reason: 'currents on every size');
  });

  test('jellyfish patrol a fixed stretch back and forth, never chasing', () {
    final g = ocean(level: 4, seed: 6);
    g.started = true;
    final seen = <int, List<Offset>>{};
    for (var i = 0; i < 60 * 40; i++) {
      g.vel = Offset.zero;
      g.pos = g.maze.cellCenter(g.maze.start);
      g.caughtResetForTest();
      g.update(1 / 60, Offset.zero);
      for (var k = 0; k < g.jellies.length; k++) {
        seen.putIfAbsent(k, () => []).add(g.jellies[k].pos);
      }
    }
    for (final j in g.jellies) {
      expect(j.path.length, greaterThan(1));
      final walked = seen[g.jellies.indexOf(j)]!;
      final far = walked.map((p) => (p - j.home).distance).reduce((a, b) => a > b ? a : b);
      expect(far, greaterThan(1.5), reason: 'it swims away from its home');
      // Always on its own patrol: close to some point of the route.
      for (final p in walked) {
        final near = j.path.map((q) => (q - p).distance).reduce((a, b) => a < b ? a : b);
        expect(near, lessThan(1.5));
      }
    }
  });

  test('a jellyfish sends the ball back to the start, only when it touches', () {
    final g = ocean(level: 3, seed: 4);
    g.started = true;
    final j = g.jellies.first;
    g.update(1 / 60, Offset.zero); // plans the patrol
    g.pos = j.pos + const Offset(2.0, 0);
    g.vel = Offset.zero;
    g.update(1 / 60, Offset.zero);
    expect(g.notice, isNot('notice.jelly'));
    final start = g.maze.cellCenter(g.maze.start);
    g.pos = j.pos + const Offset(0.1, 0);
    g.update(1 / 60, Offset.zero);
    if ((g.pos - start).distance > 0.01) {
      // A wall between them keeps the sting out; stand in line of sight.
      g.pos = j.pos;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.notice, 'notice.jelly');
    expect((g.pos - start).distance, lessThan(0.01));
    expect(g.status, GameStatus.playing);
  });

  test('a jellyfish glows brighter just before it turns round', () {
    final g = ocean(level: 3, seed: 4);
    g.started = true;
    var calm = 1.0, bright = 0.0;
    for (var i = 0; i < 60 * 40; i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = Offset.zero;
      g.caughtResetForTest();
      g.update(1 / 60, Offset.zero);
      final j = g.jellies.first;
      if (j.glow < calm) calm = j.glow;
      if (j.glow > bright) bright = j.glow;
    }
    expect(calm, lessThan(0.2));
    expect(bright, greaterThan(0.9));
  });

  test('currents come with a warning and carry the ball', () {
    final g = ocean(level: 3, seed: 2);
    g.started = true;
    var guard = 0;
    while (g.windWarnLeft <= 0 && guard++ < 2000) {
      g.jellies.clear();
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

  test('the anchor freezes the jellyfish and the currents', () {
    final g = ocean(level: 3, seed: 4);
    g.started = true;
    g.update(1 / 60, Offset.zero);
    g.bonusCharges = 1;
    g.useBonus();
    final j = g.jellies.first;
    final at = j.pos;
    g.pos = j.pos;
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.status, GameStatus.playing);
    expect(g.notice, isNot('notice.jelly'));
    expect(j.pos, at);
  });

  test('the world has a theme and texts in every language', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.ocean);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(hazardNote(const GameConfig(WorldKind.ocean, 3)), isNot(startsWith('note.')));
      for (final k in ['bonus.ocean', 'current.now', 'current.coming', 'notice.jelly', 'notice.current']) {
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
