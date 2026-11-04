import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';

GameController game(WorldKind w, BallKind ball, {int level = 3, int seed = 3}) =>
    GameController(GameConfig(w, level, ball: ball), seed: seed);

/// Wakes the first ghost and drops it right on a rolling ball.
void ghostOnBall(GameController g) {
  final ghost = g.creatures.first;
  ghost.asleep = false;
  ghost.grace = 0;
  ghost.awakeTimer = 30;
  ghost.pos = g.pos + const Offset(0.1, 0);
  g.vel = const Offset(1, 0);
  g.update(1 / 60, const Offset(1, 0));
}

/// A burning glass laser with the ball right in its line.
void underBeam(GameController g) {
  g.started = true;
  var guard = 0;
  while (g.beams.isEmpty && guard++ < 3000) {
    g.pos = g.maze.cellCenter(g.maze.start);
    g.vel = const Offset(2, 0);
    g.update(1 / 60, Offset.zero);
  }
  final b = g.beams.first;
  b.age = GlassBeam.warning + 0.1;
  g.pos = (b.a + b.b) / 2;
  g.vel = Offset.zero;
  g.update(1 / 60, Offset.zero);
}

void main() {
  group('rubber', () {
    test('bounces off a creature once per maze, the second catch counts', () {
      final g = game(WorldKind.graveyard, BallKind.rubber, seed: 5);
      g.started = true;
      ghostOnBall(g);
      expect(g.status, GameStatus.playing);
      expect(g.springUsed, isTrue);
      expect(g.notice, 'notice.spring');
      expect(tr('notice.spring'), isNot(startsWith('notice.')));

      g.caughtResetForTest();
      ghostOnBall(g);
      expect(g.lostReason, 'lose.ghost');

      // A new try gives the bounce back.
      g.restart();
      expect(g.springUsed, isFalse);
    });

    test('another ball is caught at once', () {
      final g = game(WorldKind.graveyard, BallKind.wood, seed: 5);
      g.started = true;
      ghostOnBall(g);
      expect(g.lostReason, 'lose.ghost');
    });

    test('squeezes out from under a press instead of being crushed', () {
      final g = game(WorldKind.factory, BallKind.rubber, seed: 6);
      g.started = true;
      final p = g.presses.first;
      final seen = <int>{};
      for (var i = 0; i < 60 * 12; i++) {
        g.pos = p.center;
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        seen.add(g.pressPhase(p));
      }
      expect(seen, contains(2), reason: 'the press did slam');
      expect(g.status, GameStatus.playing);
    });

    test('hops over spikes at speed, not when slow', () {
      for (final (speed, safe) in [(3.0, true), (0.5, false)]) {
        final g = game(WorldKind.mud, BallKind.rubber, seed: 2);
        g.started = true;
        final spot = g.pos;
        g.hazards.add(Hazard(spot, armAt: 0, life: 5));
        for (var i = 0; i < 5 && !g.lost; i++) {
          g.pos = spot;
          g.vel = Offset(speed, 0);
          g.update(1 / 60, Offset.zero);
        }
        expect(g.lost, !safe, reason: 'speed $speed');
      }
    });
  });

  group('glass', () {
    test('is seen from half as far and lights the caves 40% further', () {
      final g = game(WorldKind.underground, BallKind.glass);
      final w = game(WorldKind.underground, BallKind.wood);
      expect(g.droneSight, GameController.droneRange / 2);
      expect(g.cameraSight, GameController.cameraRange / 2);
      expect(w.droneSight, GameController.droneRange);
      expect(g.lightRadius, closeTo(g.config.lightRadius * 1.4, 1e-9));
      expect(w.lightRadius, w.config.lightRadius);
    });

    test('glass world lasers pass through a glass ball, not a wooden one', () {
      final g = game(WorldKind.glass, BallKind.glass, level: 2, seed: 8);
      underBeam(g);
      expect(g.status, GameStatus.playing);
      final w = game(WorldKind.glass, BallKind.wood, level: 2, seed: 8);
      underBeam(w);
      expect(w.lostReason, 'lose.laser');
    });
  });

  group('bubble', () {
    test('floats over spikes', () {
      for (final (ball, safe) in [(BallKind.bubble, true), (BallKind.wood, false)]) {
        final g = game(WorldKind.mud, ball, seed: 2);
        g.started = true;
        final spot = g.pos;
        g.hazards.add(Hazard(spot, armAt: 0, life: 5));
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        expect(g.lost, !safe, reason: '$ball');
      }
    });

    test('drifts over jellyfish, but not over gummy bears', () {
      for (final (w, stung) in [(WorldKind.ocean, false), (WorldKind.candy, true)]) {
        final g = game(w, BallKind.bubble, seed: 4);
        g.started = true;
        final j = g.jellies.first;
        g.update(1 / 60, Offset.zero); // plans the patrols
        g.pos = j.pos;
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        expect(g.notice == 'notice.jelly' || g.notice == 'notice.gummy', stung,
            reason: '$w');
      }
    });
  });

  test('gummy bears start well apart and patrol apart where they can', () {
    for (var level = 3; level <= 5; level++) {
      for (var seed = 0; seed < 6; seed++) {
        final g = game(WorldKind.candy, BallKind.wood, level: level, seed: seed);
        final homes = [for (final j in g.jellies) j.home];
        for (var a = 0; a < homes.length; a++) {
          for (var b = a + 1; b < homes.length; b++) {
            expect((homes[a] - homes[b]).distance,
                greaterThanOrEqualTo(GameController.jellySpacing),
                reason: 'level $level seed $seed');
          }
        }
        g.started = true;
        g.update(1 / 60, Offset.zero);
        expect(g.jellies.every((j) => j.path.length >= 2), isTrue);
      }
    }
  });

  test('the dots show two seconds of the way ahead, and fewer during a pause', () {
    for (final w in [WorldKind.candy, WorldKind.ocean]) {
      final g = game(w, BallKind.wood, seed: 4);
      g.started = true;
      g.update(1 / 60, Offset.zero); // plans the patrols
      final j = g.jellies.first;
      j.pause = 0;
      final reach = g.config.jellySpeed * GameController.jellyLookAhead;
      final dots = g.jellyAhead(j);
      expect(dots, isNotEmpty);
      expect(dots.length, lessThanOrEqualTo((reach / 0.3).floor() + 1));
      for (final d in dots) {
        expect((d - j.pos).distance, lessThanOrEqualTo(reach + 1e-6));
      }
      expect((dots.first - j.pos).distance, closeTo(0.3, 0.05), reason: 'starts just ahead');
      j.pause = 1.5;
      expect(g.jellyAhead(j).length, lessThan(dots.length), reason: '$w');
      j.pause = GameController.jellyLookAhead;
      expect(g.jellyAhead(j), isEmpty);
    }
    expect(GameController.jellyPause, 1.2);
  });
}
