import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/polar_maze.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/balls.dart';

/// Speed along the outer wall after pressing the ball against it and tilting
/// along it for a moment. [pressed] false: the same push, but out in the open.
double alongWall(BallKind kind, {required bool pressed, int seed = 4}) {
  final g = GameController(GameConfig(WorldKind.forest, 3, ball: kind),
      hazardsEnabled: false, seed: seed);
  final m = g.maze as PolarMaze;
  final n = m.sectors.last;
  final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
  final out = Offset(cos(theta), sin(theta));
  final side = Offset(-out.dy, out.dx);
  g.started = true;
  final gap = pressed ? g.ballRadius + PolarMaze.wallHalf : 0.5;
  g.pos = out * (m.radius - gap) - side * 0.3;
  var peak = 0.0;
  for (var i = 0; i < 24; i++) {
    // Push along the wall, and a little into it.
    g.update(1 / 60, side * 0.8 + (pressed ? out * 0.4 : Offset.zero));
    peak = max(peak, g.vel.dx * side.dx + g.vel.dy * side.dy);
  }
  return peak;
}

void main() {
  test('slime clings to walls: slower beside one than in the open', () {
    for (final seed in [4, 5, 6]) {
      final wall = alongWall(BallKind.slime, pressed: true, seed: seed);
      final open = alongWall(BallKind.slime, pressed: false, seed: seed);
      expect(wall, lessThan(open * 0.85), reason: 'seed $seed: $wall vs $open');
      // Other balls do not mind the wall.
      final wood = alongWall(BallKind.wood, pressed: true, seed: seed);
      final woodOpen = alongWall(BallKind.wood, pressed: false, seed: seed);
      expect(wood, greaterThan(woodOpen * 0.9), reason: 'seed $seed: wood $wood vs $woodOpen');
    }
  });

  test('slime does not bounce, is quiet, slow, resists wind, sinks faster in bogs', () {
    final s = statsOf(BallKind.slime);
    final wood = statsOf(BallKind.wood);
    expect(s.bounce, 0);
    expect(s.noise, lessThan(wood.noise));
    expect(s.accel, lessThan(wood.accel));
    expect(s.maxSpeed, lessThan(wood.maxSpeed));
    expect(s.windResist, greaterThan(0));
    expect(s.bogResist, lessThan(0));
    expect(s.stick, greaterThan(0));
    expect(s.breaksAt, isNull);
  });

  test('every language describes the slime with pros and cons', () {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final info = infoOf(BallKind.slime);
      expect(info.name, isNot(startsWith('ball.')));
      expect(info.pros.length, greaterThanOrEqualTo(2), reason: lang.name);
      expect(info.cons.length, greaterThanOrEqualTo(2), reason: lang.name);
    }
  });

  testWidgets('slime can be drawn', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: BallBubble(kind: BallKind.slime, size: 64))),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
