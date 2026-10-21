import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GameController make(BallKind kind, {int level = 3}) => GameController(
      GameConfig(WorldKind.mud, level, ball: kind),
      hazardsEnabled: false,
      seed: level * 5);

  test('outside the wall the ball can only be on the short entrance trail', () {
    for (final kind in BallKind.values) {
      for (var level = 1; level <= 5; level++) {
        final g = make(kind, level: level);
        final m = g.maze;
        final n = m.sectors.last;
        final t0 = m.entrance * 2 * pi / n;
        final t1 = (m.entrance + 1) * 2 * pi / n;
        g.started = true;
        final mid = (t0 + t1) / 2;
        g.pos = Offset.fromDirection(mid) * (m.radius + 0.3);

        // Shove it in every direction, hard, for a while.
        for (var dir = 0; dir < 8; dir++) {
          final push = Offset.fromDirection(dir * pi / 4);
          for (var i = 0; i < 90; i++) {
            g.update(1 / 60, push);
            final rho = g.pos.distance;
            if (rho > m.radius) {
              var a = g.pos.direction;
              if (a < 0) a += 2 * pi;
              expect(a, inInclusiveRange(t0 - 1e-6, t1 + 1e-6),
                  reason: '$kind level $level: left the trail sideways at $a (trail $t0..$t1)');
              expect(rho, lessThanOrEqualTo(m.radius + PolarMaze.trailLength - g.ballRadius + 0.02),
                  reason: '$kind level $level: rolled off the end of the trail');
            }
          }
        }
        g.dispose();
      }
    }
  });

  test('the ball can still roll out of the maze and back in through the trail', () {
    for (var level = 1; level <= 5; level++) {
      final g = make(BallKind.stone, level: level); // the widest ball
      final m = g.maze;
      final out = g.pos / g.pos.distance;
      g.started = true;
      expect(g.pos, m.cellCenter(m.start));
      var farthest = 0.0;
      for (var i = 0; i < 150; i++) {
        g.update(1 / 60, out);
        farthest = max(farthest, g.pos.distance);
      }
      expect(farthest, greaterThan(m.radius + 0.4), reason: 'level $level: out through the opening');
      for (var i = 0; i < 200; i++) {
        g.update(1 / 60, -out);
      }
      expect(g.pos.distance, lessThan(m.radius - 0.2), reason: 'level $level: back inside');
      g.dispose();
    }
  });

  test('the trail is drawn exactly where it is fenced', () {
    final m = PolarMaze.generate(rings: 7, gates: 6);
    final rect = m.trailPath().getBounds();
    expect(rect.width, greaterThan(0.9));
    expect(m.byRing[m.rings].length, greaterThanOrEqualTo(2), reason: 'both sides are solid');
    // The far end is closed too.
    expect(m.byRing[m.rings + 1], isNotEmpty);
  });
}
