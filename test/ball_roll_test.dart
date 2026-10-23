import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';

/// Angle in radians between two orientations.
double between(Rot a, Rot b) {
  // trace(a^T b)
  var tr = 0.0;
  for (var i = 0; i < 3; i++) {
    for (var j = 0; j < 3; j++) {
      tr += a[i * 3 + j] * b[i * 3 + j];
    }
  }
  return acos(((tr - 1) / 2).clamp(-1.0, 1.0));
}

void main() {
  test('rolling moves the surface along with the ball', () {
    // Rolling right by r * theta takes the point on top towards +x.
    const r = 0.26, theta = 0.5;
    final rot = rollRot(identityRot(), r * theta, 0, r);
    // The point that started at the top (0, 0, 1) is now (sin, 0, cos).
    expect(rot[2], closeTo(sin(theta), 1e-9));
    expect(rot[8], closeTo(cos(theta), 1e-9));
    expect(rot[5], closeTo(0, 1e-9));

    // Rolling down the screen (+y) carries it towards +y instead.
    final down = rollRot(identityRot(), 0, r * theta, r);
    expect(down[5], closeTo(sin(theta), 1e-9));
    expect(down[2], closeTo(0, 1e-9));
  });

  test('many small rolls keep the orientation a true rotation', () {
    var rot = restingRot();
    final rnd = Random(1);
    for (var i = 0; i < 20000; i++) {
      rot = rollRot(rot, rnd.nextDouble() * 0.02 - 0.01, rnd.nextDouble() * 0.02 - 0.01, 0.26);
      if (i % 120 == 0) rot = orthonormalize(rot);
    }
    // Rows are unit length and perpendicular.
    double dot(int a, int b) =>
        rot[a * 3] * rot[b * 3] + rot[a * 3 + 1] * rot[b * 3 + 1] + rot[a * 3 + 2] * rot[b * 3 + 2];
    for (var i = 0; i < 3; i++) {
      expect(dot(i, i), closeTo(1, 1e-6));
      for (var j = i + 1; j < 3; j++) {
        expect(dot(i, j), closeTo(0, 1e-6));
      }
    }
  });

  test('the ball turns by distance over radius, and not when it is blocked', () {
    for (final kind in [BallKind.wood, BallKind.glass, BallKind.stone]) {
      final g = GameController(GameConfig(WorldKind.forest, 3, ball: kind),
          hazardsEnabled: false, seed: 4);
      final m = g.maze as PolarMaze;
      final theta = (m.entrance + 0.5) * 2 * pi / m.sectors.last;
      final out = Offset(cos(theta), sin(theta));
      g.started = true;

      // Along the entrance trail, outwards from just outside the wall.
      g.pos = out * (m.radius + 0.1);
      g.vel = out * 1.2;
      final start = g.pos;
      final before = g.ballRot;
      for (var i = 0; i < 20; i++) {
        g.update(1 / 60, Offset.zero);
      }
      final travelled = (g.pos - start).distance;
      expect(travelled, greaterThan(0.2));
      expect(between(before, g.ballRot), closeTo(travelled / g.ballRadius, 0.02),
          reason: '$kind rolls its own circumference per revolution');

      // Pressed against a wall: stops spinning.
      final n = m.sectors.last;
      final wall = Offset.fromDirection(((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n);
      g.pos = wall * (m.radius - 0.6);
      g.vel = wall * 3;
      for (var i = 0; i < 40; i++) {
        g.update(1 / 60, wall);
      }
      final settled = g.ballRot;
      for (var i = 0; i < 20; i++) {
        g.update(1 / 60, wall); // keeps pushing into the wall
      }
      // A few degrees of jitter at most, against well over a radian of real rolling.
      expect(between(settled, g.ballRot), lessThan(0.3), reason: '$kind does not spin against a wall');
      g.dispose();
    }
  });
}
