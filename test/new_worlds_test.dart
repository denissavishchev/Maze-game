import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/rect_maze.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/game_painter.dart';
import 'package:maze/ui/game_screen.dart';
import 'package:maze/ui/maze_art.dart';
import 'package:maze/ui/worlds.dart';

GameController world(WorldKind w, {int level = 3, int seed = 3, BallKind ball = BallKind.wood}) =>
    GameController(GameConfig(w, level, ball: ball), seed: seed);

void run(GameController g, int frames, {Offset? at, Offset? vel, Offset tilt = Offset.zero}) {
  for (var i = 0; i < frames; i++) {
    if (at != null) g.pos = at;
    if (vel != null) g.vel = vel;
    g.update(1 / 60, tilt);
  }
}

void main() {
  group('shifting maze', () {
    test('the extra passages never let a gate be walked around', () {
      for (var seed = 0; seed < 8; seed++) {
        for (final level in [1, 3, 5]) {
          final g = world(WorldKind.shifting, level: level, seed: seed);
          final m = g.maze;
          expect(m.loops, isNotEmpty, reason: 'loops $level/$seed');
          final closed = List<bool>.filled(m.gateCount, false);
          expect(m.path(m.start, m.goal, closed), isNull,
              reason: 'the gates still guard the exit ($level/$seed)');
          g.dispose();
        }
      }
    });

    test('there are ten times as many shifting walls as before', () {
      expect([for (var l = 1; l <= 5; l++) GameConfig(WorldKind.shifting, l).doorCount],
          [20, 30, 40, 50, 60]);
      for (final level in [1, 3, 5]) {
        final g = world(WorldKind.shifting, level: level, seed: 2);
        expect(g.doors.length, greaterThanOrEqualTo(GameConfig(WorldKind.shifting, level).doorCount ~/ 2),
            reason: 'level $level');
        g.dispose();
      }
    });

    test('every door sits on an open passage, away from the start and the exit', () {
      for (var seed = 0; seed < 6; seed++) {
        final g = world(WorldKind.shifting, level: 4, seed: seed);
        expect(g.doors, isNotEmpty);
        final open = List<bool>.filled(g.maze.gateCount, true);
        final noGates = List<bool>.filled(g.maze.gateCount, false);
        for (final d in g.doors) {
          expect(g.maze.passable(d.edge, noGates), isTrue);
          expect(g.maze.passable(d.edge, open), isTrue);
          expect(d.state, g.maze.loops.contains(d.edge) ? 2 : 0,
              reason: 'the extra passages start shut, the maze\'s own open');
          expect(d.segs, isNotEmpty);
        }
        g.dispose();
      }
    });

    test('however the doors shift, the maze can always still be finished', () {
      var closedSeen = 0;
      var blocked = 0;
      for (var seed = 0; seed < 10; seed++) {
        for (final level in [2, 5]) {
          final g = world(WorldKind.shifting, level: level, seed: seed);
          final rnd = Random(seed * 7 + level);
          g.started = true;
          var tilt = Offset.zero;
          for (var i = 0; i < 60 * 45; i++) {
            if (i % 25 == 0) {
              final a = rnd.nextDouble() * 2 * pi;
              tilt = Offset(cos(a), sin(a)) * rnd.nextDouble();
            }
            g.update(1 / 60, tilt);
            expect(g.status, GameStatus.playing, reason: 'nothing kills in this world');
            if (i % 5 == 0) {
              expect(g.canFinishForTest(), isTrue, reason: 'cut off at frame $i ($level/$seed)');
            }
            closedSeen += g.doors.where((d) => d.state == 2).length;
          }
          blocked += g.doors.length;
          g.dispose();
        }
      }
      expect(closedSeen, greaterThan(0), reason: 'doors do shut');
      expect(blocked, greaterThan(0));
    });

    test('the same holds in the rectangular maze of endless mode', () {
      GameController? g;
      for (var seed = 0; seed < 300 && g == null; seed++) {
        final c = GameController(GameController.endlessConfig(0, BallKind.wood),
            endless: true, seed: seed);
        if (c.config.world == WorldKind.shifting) {
          g = c;
        } else {
          c.dispose();
        }
      }
      expect(g, isNotNull);
      expect(g!.maze, isA<RectMaze>());
      expect(g.doors.length, greaterThanOrEqualTo(10));
      g.started = true;
      final rnd = Random(4);
      var closed = 0;
      for (var i = 0; i < 60 * 40; i++) {
        if (i % 20 == 0) {
          final a = rnd.nextDouble() * 2 * pi;
          g.vel = Offset(cos(a), sin(a)) * 2;
        }
        g.update(1 / 60, Offset.zero);
        if (g.status != GameStatus.playing || g.scrolling) break;
        if (i % 5 == 0) expect(g.canFinishForTest(), isTrue, reason: 'frame $i');
        closed += g.doors.where((d) => d.state == 2).length;
      }
      expect(closed, greaterThan(0));
    });

    test('a door does not shut on a ball standing in its way', () {
      final g = world(WorldKind.shifting, level: 3, seed: 5);
      g.started = true;
      final d = g.doors.first;
      d.state = 1;
      d.timer = 0;
      g.pos = d.center;
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      expect(d.state, isNot(2), reason: 'it does not shut on the ball');
    });

    test('a shut door is a wall', () {
      final g = world(WorldKind.shifting, level: 3, seed: 5);
      g.started = true;
      final d = g.doors.firstWhere((d) => g.maze.loops.contains(d.edge));
      final (a, b) = d.cells;
      final from = g.maze.cellCenter(a);
      final toward = g.maze.cellCenter(b) - from;
      d.state = 2;
      d.timer = 100;
      g.pos = from;
      g.vel = Offset.zero;
      for (var i = 0; i < 120; i++) {
        g.update(1 / 60, toward / toward.distance);
        d.timer = 100;
      }
      expect(g.maze.cellAt(g.pos), isNot(b), reason: 'the door holds the ball back');
      // Open, the ball steers through the passage.
      d.state = 0;
      d.timer = 100;
      g.pos = from;
      g.vel = Offset.zero;
      final route = g.maze.routePoints([a, b]).skip(1).toList();
      for (var i = 0; i < 600 && g.maze.cellAt(g.pos) != b; i++) {
        final next = route.first;
        if ((next - g.pos).distance < 0.25 && route.length > 1) route.removeAt(0);
        final to = route.first - g.pos;
        g.update(1 / 60, to / max(to.distance, 1e-6));
        d.timer = 100;
      }
      expect(g.maze.cellAt(g.pos), b);
    });

    test('the vision bonus shows every moving wall and its countdown, and nothing else changes', () {
      final g = world(WorldKind.shifting, level: 5, seed: 2);
      g.started = true;
      expect(g.doorsRevealed, isFalse);
      g.bonusCharges = 1;
      g.useBonus();
      expect(g.doorsRevealed, isTrue);
      // The doors go on shifting while it lasts, and still never cut the way.
      final before = [for (final d in g.doors) d.state];
      var changed = false;
      for (var i = 0; i < 60 * 8; i++) {
        g.update(1 / 60, Offset.zero);
        expect(g.canFinishForTest(), isTrue);
        if (!changed) {
          final now = [for (final d in g.doors) d.state];
          for (var k = 0; k < now.length; k++) {
            if (now[k] != before[k]) changed = true;
          }
        }
      }
      expect(changed, isTrue, reason: 'no freezing');
      for (final d in g.doors) {
        expect(d.timer, lessThanOrEqualTo(g.config.doorOpenSeconds * 1.3 + 2));
      }
      expect(g.doorsRevealed, isTrue);
      run(g, 60 * 3);
      expect(g.doorsRevealed, isFalse, reason: 'it runs out after ten seconds');
    });
  });

  group('factory', () {
    test('presses, belts and magnets are laid out clear of the start', () {
      for (var level = 1; level <= 5; level++) {
        final g = world(WorldKind.factory, level: level, seed: 4);
        final start = g.maze.cellCenter(g.maze.start);
        expect(g.presses.length + g.belts.length, greaterThanOrEqualTo(2), reason: 'level $level');
        expect(g.magnets, isNotEmpty);
        for (final p in [...g.presses.map((p) => p.center), ...g.belts.map((b) => b.center), ...g.magnets.map((m) => m.pos)]) {
          expect((p - start).distance, greaterThan(1.0));
        }
        for (final b in g.belts) {
          expect(b.along.distance, closeTo(1, 1e-6));
        }
        g.dispose();
      }
    });

    test('a belt carries the ball one way, then the other', () {
      final g = world(WorldKind.factory, level: 3, seed: 4);
      g.started = true;
      final b = g.belts.first;
      final dirs = <int>{};
      var guard = 0;
      while (dirs.length < 2 && guard++ < 60 * 12) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        dirs.add(g.beltDir(b));
      }
      expect(dirs, {1, -1});
      final dir = g.beltDir(b);
      g.pos = b.center;
      g.vel = Offset.zero;
      g.update(1 / 20, Offset.zero);
      expect((g.vel.dx * b.along.dx + g.vel.dy * b.along.dy) * dir, greaterThan(0.2));
    });

    test('a press warns, then slams and crushes only then', () {
      final g = world(WorldKind.factory, level: 3, seed: 6);
      g.started = true;
      final p = g.presses.first;
      final seen = <int>{};
      var guard = 0;
      while (g.status == GameStatus.playing && guard++ < 60 * 12) {
        g.pos = p.center;
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        seen.add(g.pressPhase(p));
      }
      expect(g.lostReason, 'lose.press');
      expect(seen, containsAll([0, 1, 2]));
    });

    test('a magnet pulls an iron ball and leaves a wooden one alone', () {
      for (final (kind, pulled) in [(BallKind.steel, true), (BallKind.wood, false)]) {
        final g = world(WorldKind.factory, level: 3, seed: 4, ball: kind);
        g.started = true;
        final m = g.magnets.first;
        var guard = 0;
        while (g.magnetPhase(m) != 2 && guard++ < 60 * 12) {
          g.pos = g.maze.cellCenter(g.maze.start);
          g.vel = Offset.zero;
          g.update(1 / 60, Offset.zero);
        }
        expect(g.magnetPhase(m), 2);
        var gained = 0.0;
        for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
          g.pos = m.pos + dir * 1.0;
          g.vel = Offset.zero;
          g.update(1 / 60, Offset.zero);
          gained = max(gained, -(g.vel.dx * dir.dx + g.vel.dy * dir.dy));
        }
        expect(gained > 0.05, pulled, reason: kind.name);
        g.dispose();
      }
    });

    test('the factory has many belts, wrecking balls and turntables, and no robots', () {
      for (var level = 1; level <= 5; level++) {
        final g = world(WorldKind.factory, level: level, seed: 4);
        expect(g.pendulums, isNotEmpty, reason: 'level $level');
        expect(g.turntables, isNotEmpty);
        expect(g.jellies, isEmpty);
        expect(g.belts.length, greaterThanOrEqualTo(g.config.beltCount - 2), reason: 'level $level');
        g.dispose();
      }
      expect([for (var l = 1; l <= 5; l++) GameConfig(WorldKind.factory, l).beltCount], [4, 5, 6, 7, 8]);
    });

    test('a wrecking ball swings across and knocks the ball back, but leaves its ends free', () {
      final g = world(WorldKind.factory, level: 3, seed: 4);
      g.started = true;
      final p = g.pendulums.first;
      var minAcross = 0.0, maxAcross = 0.0;
      var guard = 0;
      while (guard++ < 60 * 6) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        final a = g.pendulumAcross(p);
        minAcross = min(minAcross, a);
        maxAcross = max(maxAcross, a);
      }
      expect(minAcross, lessThan(-0.35));
      expect(maxAcross, greaterThan(0.35));
      // Standing in the swing's path gets the ball knocked back.
      var hit = false;
      for (var i = 0; i < 60 * 6 && !hit; i++) {
        g.pos = p.center;
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        hit = g.notice == 'notice.pendulum';
      }
      expect(hit, isTrue);
      expect(g.status, GameStatus.playing);
    });

    test('a turntable flings the ball round its middle, one way and then the other', () {
      final g = world(WorldKind.factory, level: 3, seed: 4);
      g.started = true;
      final t = g.turntables.first;
      final dirs = <int>{};
      var guard = 0;
      while (dirs.length < 2 && guard++ < 60 * 14) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        dirs.add(g.turntableDir(t));
      }
      expect(dirs, {1, -1});
      final dir = g.turntableDir(t);
      // Round the middle: along the tangent of the offset, which way depends on
      // the spin (try each side, since a wall may stand in the way on some).
      var best = 0.0;
      for (final side in const [Offset(0.4, 0), Offset(-0.4, 0), Offset(0, 0.4), Offset(0, -0.4)]) {
        g.pos = t.pos + side;
        g.vel = Offset.zero;
        g.update(1 / 20, Offset.zero);
        final tangent = Offset(-side.dy, side.dx) / side.distance;
        best = max(best, (g.vel.dx * tangent.dx + g.vel.dy * tangent.dy) * dir);
      }
      expect(best, greaterThan(0.1));
    });

    test('the emergency stop halts belts, presses and magnets', () {
      final g = world(WorldKind.factory, level: 5, seed: 2);
      g.started = true;
      g.bonusCharges = 1;
      g.useBonus();
      run(g, 60 * 4, at: g.presses.isEmpty ? g.belts.first.center : g.presses.first.center, vel: Offset.zero);
      expect(g.status, GameStatus.playing);
      for (final b in g.belts) {
        expect(g.beltDir(b), 0);
      }
      for (final p in g.presses) {
        expect(g.pressPhase(p), 0);
      }
      for (final m in g.magnets) {
        expect(g.magnetPhase(m), 0);
      }
      for (final t in g.turntables) {
        expect(g.turntableDir(t), 0);
      }
      for (final p in g.pendulums) {
        expect(g.pendulumAcross(p), GameController.pendulumSwing);
      }
    });
  });

  group('candy', () {
    test('caramel, chocolate and gummy bears, clear of the start', () {
      for (var level = 1; level <= 5; level++) {
        final g = world(WorldKind.candy, level: level, seed: 4);
        final start = g.maze.cellCenter(g.maze.start);
        expect(g.goos.length, g.config.gooCount);
        expect(g.goos.any((x) => x.melts), isTrue);
        expect(g.goos.any((x) => !x.melts), isTrue);
        expect(g.jellies.length, g.config.jellyCount);
        for (final x in g.goos) {
          expect((x.pos - start).distance, greaterThan(1.9));
        }
        g.dispose();
      }
    });

    test('caramel holds the ball back; chocolate does only while melted', () {
      final g = world(WorldKind.candy, level: 3, seed: 4);
      g.started = true;
      final caramel = g.goos.firstWhere((x) => !x.melts);
      final choc = g.goos.firstWhere((x) => x.melts);
      expect(g.gooSticky(caramel), isTrue);
      double speedAfter(Offset at) {
        g.pos = at;
        g.vel = const Offset(3, 0);
        g.update(1 / 30, Offset.zero);
        return g.vel.distance;
      }

      final free = speedAfter(g.maze.cellCenter(g.maze.start));
      final stuck = speedAfter(caramel.pos);
      expect(stuck, lessThan(free * 0.6));
      // Chocolate sets and melts again.
      final states = <bool>{};
      for (var i = 0; i < 60 * 8; i++) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        states.add(g.gooSticky(choc));
      }
      expect(states, {true, false});
    });

    test('gummy worms wriggle up across the corridor and block it, then slip away', () {
      final g = world(WorldKind.candy, level: 3, seed: 4);
      g.started = true;
      expect(g.worms.length, inInclusiveRange(1, g.config.wormCount));
      final w = g.worms.first;
      final seen = <int>{};
      var guard = 0;
      while (!(seen.containsAll([0, 1, 2])) && guard++ < 60 * 14) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        seen.add(g.wormPhase(w));
      }
      expect(seen, containsAll([0, 1, 2]));
      // Out, it is a wall: a ball pushed along the corridor cannot pass.
      var wait = 0;
      while (g.wormPhase(w) != 2 && wait++ < 60 * 14) {
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
      }
      expect(g.wormPhase(w), 2);
      g.pos = w.center - w.along * 0.8;
      g.vel = Offset.zero;
      for (var i = 0; i < 40 && g.wormPhase(w) == 2; i++) {
        g.update(1 / 60, w.along);
      }
      final across = (g.pos - w.center);
      expect(across.dx * w.along.dx + across.dy * w.along.dy, lessThan(0.05),
          reason: 'the ball did not get past the worm');
    });

    test('the mint makes everything harmless', () {
      final g = world(WorldKind.candy, level: 3, seed: 4);
      g.started = true;
      g.bonusCharges = 1;
      g.useBonus();
      for (final x in g.goos) {
        expect(g.gooSticky(x), isFalse);
      }
      for (final w in g.worms) {
        expect(g.wormPhase(w), 0);
      }
      final bear = g.jellies.first;
      final before = bear.pos;
      run(g, 60, at: g.maze.cellCenter(g.maze.start), vel: Offset.zero);
      expect(bear.pos, before, reason: 'the bears stand still');
    });

    test('a gummy bear sends the ball back to the start', () {
      final g = world(WorldKind.candy, level: 3, seed: 4);
      g.started = true;
      final bear = g.jellies.first;
      run(g, 2);
      g.pos = bear.pos;
      g.update(1 / 60, Offset.zero);
      expect(g.notice, 'notice.gummy');
      expect(g.pos, g.maze.cellCenter(g.maze.start));
      expect(g.status, GameStatus.playing);
    });
  });

  test('the three worlds have themes, texts in every language and notes', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final w in [WorldKind.factory, WorldKind.candy, WorldKind.shifting]) {
        final t = themeFor(w);
        expect(t.name, isNot(startsWith('world.')), reason: '${w.name} ${lang.name}');
        expect(t.blurb, isNot(startsWith('world.')));
        expect(hazardNote(GameConfig(w, 3)), isNot(startsWith('note.')));
        expect(tr('bonus.${w.name}'), isNot(startsWith('bonus.')));
      }
      expect(tr('lose.press'), isNot(startsWith('lose.')));
      expect(tr('notice.gummy'), isNot(startsWith('notice.')));
    }
    AppLanguage.instance.lang = AppLang.pl;
  });

  test('everything in the three worlds can be painted, in every phase', () {
    for (final w in [WorldKind.factory, WorldKind.candy, WorldKind.shifting]) {
      for (final level in [1, 5]) {
        final g = world(w, level: level, seed: 4);
        final painter = GamePainter(g, MazeRender(g.maze, themeFor(w)));
        g.started = true;
        g.bonusCharges = 1;
        for (var i = 0; i < 60 * 16; i++) {
          g.pos = g.maze.cellCenter(g.maze.start);
          g.vel = Offset.zero;
          g.update(1 / 60, Offset.zero);
          if (i == 60 * 8) g.useBonus();
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
      GameController? e;
      for (var seed = 0; seed < 300 && e == null; seed++) {
        final c = GameController(GameController.endlessConfig(0, BallKind.wood),
            endless: true, seed: seed);
        if (c.config.world == w) {
          e = c;
        } else {
          c.dispose();
        }
      }
      expect(e, isNotNull, reason: w.name);
      expect(buildRectMazePicture(e!.maze as RectMaze, themeFor(w), 1), isNotNull);
      final painter = GamePainter(e, MazeRender(e.maze, themeFor(w)));
      e.started = true;
      for (var i = 0; i < 60 * 6; i++) {
        e.update(1 / 60, Offset.zero);
        if (i % 20 == 0) {
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(390, 844));
          rec.endRecording();
        }
      }
      e.dispose();
    }
  });

  testWidgets('the three worlds draw on a phone', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final w in [WorldKind.factory, WorldKind.candy, WorldKind.shifting]) {
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(config: GameConfig(w, 3, ball: BallKind.steel)),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: w.name);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
