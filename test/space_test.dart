import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/worlds.dart';

GameController ship({int level = 2, int seed = 3, bool hazards = true}) => GameController(
      GameConfig(WorldKind.space, level),
      hazardsEnabled: hazards,
      seed: seed,
    );

void main() {
  test('the spaceship has lasers and airlocks along the way, away from start and goal', () {
    for (var seed = 0; seed < 30; seed++) {
      for (var level = 1; level <= 5; level++) {
        final g = ship(level: level, seed: seed);
        final c = g.config;
        expect(g.lasers.length, lessThanOrEqualTo(c.laserCount));
        expect(g.airlocks.length, lessThanOrEqualTo(c.airlockCount));
        expect(g.lasers.length + g.airlocks.length + g.cameras.length, greaterThanOrEqualTo(2),
            reason: 'seed $seed level $level: some of them were placed');
        final cells = [
          for (final l in g.lasers) g.maze.cellAt(l.center),
          for (final a in g.airlocks) g.maze.cellAt(a.center),
        ];
        expect(cells.toSet().length, cells.length, reason: 'one per cell');
        for (final cell in cells) {
          expect(g.maze.solution, contains(cell), reason: 'on the way to the exit');
          expect(cell, isNot(g.maze.start));
          expect(cell, isNot(g.maze.goal));
          expect(g.maze.buttonCells, isNot(contains(cell)));
        }
        for (final l in g.lasers) {
          expect(l.along.distance, closeTo(1, 1e-9));
        }
      }
    }
  });

  test('there are twice as many cameras as there were robots, one to a cell on the way out', () {
    expect([for (var l = 1; l <= 5; l++) GameConfig(WorldKind.space, l).cameraCount],
        [2, 2, 4, 4, 6]);
    var placed = 0;
    for (var seed = 0; seed < 30; seed++) {
      for (var level = 1; level <= 5; level++) {
        final g = ship(level: level, seed: seed);
        expect(g.cameras.length, lessThanOrEqualTo(g.config.cameraCount));
        placed += g.cameras.length;
        final taken = [
          for (final l in g.lasers) g.maze.cellAt(l.center),
          for (final a in g.airlocks) g.maze.cellAt(a.center),
          for (final c in g.cameras) g.maze.cellAt(c.pos),
        ];
        expect(taken.toSet().length, taken.length, reason: 'one danger to a cell');
        for (final c in g.cameras) {
          final cell = g.maze.cellAt(c.pos);
          expect(g.maze.solution, contains(cell));
          expect(cell, isNot(g.maze.start));
          expect(cell, isNot(g.maze.goal));
        }
      }
    }
    expect(placed, greaterThan(400), reason: 'cameras do get placed, about 3.6 a level');
  });

  test('a camera swings its view back and forth around where it looks', () {
    final g = ship(level: 3, seed: 2);
    final cam = g.cameras.first;
    g.started = true;
    var lo = double.infinity, hi = -double.infinity;
    for (var i = 0; i < 60 * 12; i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      final off = g.cameraAngle(cam) - cam.base;
      lo = off < lo ? off : lo;
      hi = off > hi ? off : hi;
    }
    expect(lo, closeTo(-GameController.cameraSweep, 0.05));
    expect(hi, closeTo(GameController.cameraSweep, 0.05));
  });

  test('a camera catches a ball that stays in its view, not one behind a wall or too far', () {
    final g = ship(level: 3, seed: 2, hazards: false);
    final cam = g.cameras.first;
    g.started = true;
    final look = Offset.fromDirection(g.cameraAngle(cam));

    // Right in front of the lens, with open ground: seen.
    g.pos = cam.pos + look * 0.6;
    expect(g.cameraSees(cam), isTrue);
    // Beyond its range: not seen.
    g.pos = cam.pos + look * (GameController.cameraRange + 1);
    expect(g.cameraSees(cam), isFalse);
    // Behind it: not seen.
    g.pos = cam.pos - look * 0.6;
    expect(g.cameraSees(cam), isFalse);
    // Beside its view cone: not seen.
    final side = Offset.fromDirection(g.cameraAngle(cam) + GameController.cameraHalfAngle + 0.4);
    g.pos = cam.pos + side * 0.6;
    expect(g.cameraSees(cam), isFalse);
  });

  test('standing in view long enough ends the game; the cone stops at the walls', () {
    final g = ship(level: 3, seed: 2);
    g.started = true;
    final cam = g.cameras.first;
    var steps = 0;
    while (!g.lost && steps++ < 60 * 20) {
      // Keep the ball just in front of the lens, wherever it points now.
      g.pos = cam.pos + Offset.fromDirection(g.cameraAngle(cam)) * 0.6;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isTrue);
    expect(g.lostReason, 'lose.camera');

    // No ray reaches further than the range, and some are stopped by walls.
    var stopped = 0;
    for (var i = 0; i < 24; i++) {
      final d = g.sightDistance(cam.pos, i * pi / 12, GameController.cameraRange);
      expect(d, inInclusiveRange(0, GameController.cameraRange));
      if (d < GameController.cameraRange - 0.05) stopped++;
    }
    expect(stopped, greaterThan(0), reason: 'walls cut the view');
  });

  test('other worlds have none of it', () {
    final g = GameController(const GameConfig(WorldKind.forest, 2), seed: 3);
    expect(g.lasers, isEmpty);
    expect(g.airlocks, isEmpty);
    expect(g.cameras, isEmpty);
    expect(g.gravityActive, isFalse);
  });

  test('gravity drifts the ball once the run is on, and changes direction on a timer', () {
    final g = ship(hazards: true);
    g.pos = g.maze.cellCenter(g.maze.start);
    // Before the first tilt nothing pulls.
    for (var i = 0; i < 30; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.started, isFalse);
    expect(g.vel.distance, 0);

    g.started = true;
    expect(g.gravityActive, isTrue);
    final seen = <Offset>{g.gravityDir};
    var warned = false;
    var moved = false;
    for (var i = 0; i < 60 * 40 && !g.lost; i++) {
      g.update(1 / 60, Offset.zero);
      if (g.gravityWarnLeft > 0) {
        warned = true;
        expect(g.gravityNext, isNot(g.gravityDir), reason: 'the next direction differs');
        expect(g.notice, 'notice.gravity');
      }
      seen.add(g.gravityDir);
      if (g.vel.distance > 0.2) moved = true;
    }
    expect(moved, isTrue, reason: 'drifts with the tilt at zero');
    expect(warned, isTrue, reason: 'a change is announced');
    expect(seen.length, greaterThan(1), reason: 'the direction changes');
    for (final d in seen) {
      expect(d.distance, closeTo(1, 1e-9));
    }
  });

  test('the stabilizer switches the drift off for its time', () {
    final g = ship(hazards: true);
    g.started = true;
    g.bonusCharges = 1;
    g.useBonus();
    expect(g.bonusLeft, greaterThan(0));
    expect(g.gravityActive, isFalse);
    // Lasers aside (the ball stays far from them), nothing moves the ball.
    final at = g.pos;
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect((g.pos - at).distance, lessThan(0.01));
  });

  test('a laser burns on a cycle: dark, warning, beam', () {
    final g = ship(hazards: true);
    final l = g.lasers.first;
    g.started = true;
    final period = g.config.laserPeriod;
    final phases = <int>[];
    // Keep the ball out of its way.
    for (var i = 0; i < (period * 3 * 60).round(); i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      phases.add(g.laserPhase(l));
    }
    expect(phases.toSet(), {0, 1, 2});
    // The order is dark -> warning -> beam -> dark, never skipping the warning.
    for (var i = 1; i < phases.length; i++) {
      if (phases[i] != phases[i - 1]) {
        expect((phases[i] - phases[i - 1]) % 3, 1, reason: 'step $i: ${phases[i - 1]} -> ${phases[i]}');
      }
    }
    final beam = phases.where((p) => p == 2).length / 60;
    expect(beam, closeTo(GameController.laserBeam * 3, 0.5), reason: 'beam seconds');
  });

  test('waiting out the beam is safe; standing in it is not', () {
    var g = ship(hazards: true);
    g.started = true;
    var l = g.lasers.first;
    // Stand in the corridor just short of the laser: never hit.
    g.pos = l.center - l.along * 0.9;
    for (var i = 0; i < 60 * 12; i++) {
      g.vel = Offset.zero;
      g.pos = l.center - l.along * 0.9;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isFalse, reason: 'next to the beam is safe');

    g = ship(hazards: true, seed: 5);
    g.started = true;
    l = g.lasers.first;
    var steps = 0;
    while (!g.lost && steps++ < 60 * 12) {
      g.pos = l.center;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isTrue, reason: 'in the beam');
    expect(g.lostReason, 'lose.laser');
  });

  test('a shut airlock stops the ball like a wall', () {
    final g = ship(level: 2, seed: 7, hazards: true);
    g.started = true;
    final a = g.airlocks.first;
    final perp = Offset(-a.along.dy, a.along.dx);
    // Lay the ball against the door from the side it comes from, pushing on.
    for (final wantClosed in [true, false]) {
      var tried = 0;
      var crossed = false;
      for (var i = 0; i < 60 * 14 && tried < 2; i++) {
        g.update(1 / 60, Offset.zero);
        if (g.airlockClosed(a) != wantClosed) continue;
        // Only while the door is in the wanted state, test one pass at it.
        g.pos = a.center - a.along * 0.5;
        g.vel = a.along * 1.2;
        for (var k = 0; k < 20 && g.airlockClosed(a) == wantClosed; k++) {
          g.update(1 / 60, a.along * 0.3);
          // Gravity and walls aside, did it get past the door's line?
          final d = (g.pos - a.center);
          if (d.dx * a.along.dx + d.dy * a.along.dy > 0.25 && (d.dx * perp.dx + d.dy * perp.dy).abs() < 0.3) {
            crossed = true;
          }
        }
        tried++;
        i += 60;
      }
      if (wantClosed) {
        expect(crossed, isFalse, reason: 'a shut door stops the ball');
      }
    }
  });

  test('the airlock cycle: open, a warning, then shut for a while', () {
    final g = ship(hazards: true);
    final a = g.airlocks.first;
    g.started = true;
    final phases = <int>[];
    for (var i = 0; i < 60 * 14; i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      phases.add(g.airlockPhase(a));
    }
    expect(phases.toSet(), {0, 1, 2});
    for (var i = 1; i < phases.length; i++) {
      if (phases[i] != phases[i - 1]) {
        expect((phases[i] - phases[i - 1]) % 3, 1, reason: 'never shuts without a warning');
      }
    }
    final shut = phases.where((p) => p == 2).length / 60;
    final cycles = 14 / GameController.airlockCycle;
    expect(shut / cycles, closeTo(GameController.airlockCycle - GameController.airlockOpen - GameController.airlockWarning, 0.9));
  });

  test('the spaceship works in endless mode, and the bonus rounds stay every five levels', () {
    final g = GameController(GameController.endlessConfig(0, BallKind.wood, world: WorldKind.space),
        endless: true, seed: 2);
    // The constructor draws a random world; force a ship maze from the start.
    for (var i = 0; i < 40 && g.config.world != WorldKind.space; i++) {
      g.resetRun();
    }
    expect(g.config.world, WorldKind.space);
    expect(g.lasers.length + g.airlocks.length, greaterThanOrEqualTo(2));
    expect(g.config.bonusCount, 0);
    expect(GameController.endlessConfig(5, BallKind.wood).bonusCount, 1);
    expect(GameController.endlessConfig(10, BallKind.wood).bonusCount, 0);
    expect(GameController.endlessConfig(15, BallKind.wood).bonusCount, 1);
  });

  test('the spaceship is named, described and has its bonus in every language', () {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    final names = <String>{};
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.space);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(tr('bonus.space'), isNot(startsWith('bonus.')));
      expect(tr('lose.laser'), isNot(startsWith('lose.')));
      expect(tr('notice.gravity'), isNot(startsWith('notice.')));
      expect(hazardNote(const GameConfig(WorldKind.space, 3)), isNot(startsWith('note.')));
      names.add(t.name);
    }
    expect(names.length, 3);
  });
}
