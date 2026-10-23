import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';

bool _crosses(Offset p1, Offset p2, Seg s) {
  double o(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final d1 = o(s.a, s.b, p1);
  final d2 = o(s.a, s.b, p2);
  final d3 = o(p1, p2, s.a);
  final d4 = o(p1, p2, s.b);
  return d1 * d2 < 0 && d3 * d4 < 0;
}

/// The first wall (or closed gate) that the step [a] -> [b] cuts through.
Seg? wallCut(GameController g, Offset a, Offset b) {
  if ((b - a).distance < 1e-9) return null;
  final m = g.maze as PolarMaze;
  for (var k = 0; k <= m.rings; k++) {
    for (final s in m.byRing[k]) {
      if (s.gate >= 0 && g.gateOpen[s.gate]) continue;
      if (_crosses(a, b, s)) return s;
    }
  }
  return null;
}

/// Runs [seconds] of game and fails if any creature's step cuts a wall.
/// Returns the total distance the creatures walked, so a test can check that
/// they really moved.
double simulate(
  WorldKind world,
  int level,
  int seed, {
  required int seconds,
  required void Function(GameController g, int frame) drive,
}) {
  final game = GameController(GameConfig(world, level), seed: seed * 7 + level);
  game.started = true;
  final prev = [for (final c in game.creatures) c.pos];
  var walked = 0.0;
  for (var i = 0; i < 60 * seconds && !game.lost; i++) {
    drive(game, i);
    game.update(1 / 60, Offset.zero);
    if (game.lost) break;
    for (var k = 0; k < game.creatures.length; k++) {
      final c = game.creatures[k];
      final cut = wallCut(game, prev[k], c.pos);
      expect(cut, isNull,
          reason: '${world.name} level $level seed $seed: creature $k crossed '
              'a wall at ${c.pos} (frame $i)');
      walked += (c.pos - prev[k]).distance;
      prev[k] = c.pos;
    }
    if (game.noticeLeft > 2.3) game.caughtResetForTest();
  }
  game.dispose();
  return walked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final world in [WorldKind.forest, WorldKind.city]) {
    final name = world.name;

    test('$name: chasing a loud ball that hops around never cuts a wall', () {
      var walked = 0.0;
      for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
        for (var seed = 0; seed < 4; seed++) {
          final rnd = Random(seed);
          walked += simulate(world, level, seed, seconds: 40, drive: (g, i) {
            g.forcedStill = 0;
            g.forcedNoise = 1;
            if (i % 240 == 0) {
              // Sometimes behind closed gates, where wolves used to cut
              // straight across.
              g.pos = g.maze.cellCenter(rnd.nextInt(g.maze.cellCount));
              g.vel = Offset.zero;
            }
          });
        }
      }
      expect(walked, greaterThan(200), reason: 'they really did move');
    });

    test('$name: patrolling and searching never cut a wall', () {
      var walked = 0.0;
      for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
        for (var seed = 0; seed < 4; seed++) {
          walked += simulate(world, level, seed, seconds: 90, drive: (g, i) {
            g.forcedStill = 0;
            g.forcedNoise = 0;
            if (i == 0) {
              for (final c in g.creatures) {
                g.noise(c.pos); // wake them once, then leave them alone
              }
            }
            // The ball keeps clear of them at the start of the maze.
            g.pos = g.maze.cellCenter(g.maze.start);
          });
        }
      }
      expect(walked, greaterThan(200), reason: 'they really did move');
    });

    test('$name: falling asleep and waking up again never cuts a wall', () {
      for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
        for (var seed = 0; seed < 4; seed++) {
          final rnd = Random(seed + 50);
          simulate(world, level, seed, seconds: 120, drive: (g, i) {
            // Real stillness (so they get bored and sleep), then a burst of
            // noise from a random spot wakes them again.
            final phase = i % 900;
            g.forcedNoise = phase > 780 ? 1 : 0;
            if (phase == 780) {
              g.pos = g.maze.cellCenter(rnd.nextInt(g.maze.cellCount));
              g.vel = Offset.zero;
            }
          });
        }
      }
    });
  }
}
