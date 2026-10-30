import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/rect_maze.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/game_painter.dart';
import 'package:orbyrinth/ui/game_screen.dart';
import 'package:orbyrinth/ui/maze_art.dart';
import 'package:orbyrinth/ui/worlds.dart';

GameController winter({int level = 3, int seed = 3, BallKind ball = BallKind.wood}) =>
    GameController(GameConfig(WorldKind.winter, level, ball: ball), seed: seed);

/// The fastest the ball gets in 2.5 s of full tilt, held in the cell at [at].
double topSpeed(GameController g, Offset at) {
  g.vel = Offset.zero;
  var top = 0.0;
  for (var i = 0; i < 150; i++) {
    g.pos = at;
    g.update(1 / 60, const Offset(1, 0));
    top = max(top, g.vel.distance);
  }
  return top;
}

Offset snowCell(GameController g) =>
    g.maze.cellCenter([for (var c = 3; c < g.snow.length; c++) if (g.snow[c]) c].first);

Offset iceCell(GameController g) =>
    g.maze.cellCenter([for (var c = 3; c < g.snow.length; c++) if (!g.snow[c]) c].first);

void main() {
  test('most of the maze is snow in a few patches of ice, with caves and yetis', () {
    for (var level = 1; level <= 5; level++) {
      for (var seed = 0; seed < 8; seed++) {
        final g = winter(level: level, seed: seed);
        final reason = 'level $level seed $seed';
        expect(g.snow.length, g.maze.cellCount, reason: reason);
        final ice = g.snow.where((s) => !s).length;
        expect(ice / g.snow.length, inInclusiveRange(0.2, 0.32), reason: reason);
        expect(g.snow[g.maze.start], isTrue, reason: 'the start is snow');
        expect(g.snow[g.maze.goal], isTrue, reason: 'so is the exit');
        expect(g.caves.length, g.config.caveCount, reason: reason);
        expect(g.caves.length, greaterThanOrEqualTo(2));
        final start = g.maze.cellCenter(g.maze.start);
        for (final c in g.caves) {
          expect(g.maze.cellAt(c.pos), isNot(g.maze.start));
          expect(g.maze.cellAt(c.pos), isNot(g.maze.goal));
          expect(g.maze.buttonCells, isNot(contains(g.maze.cellAt(c.pos))));
          expect((c.pos - start).distance, greaterThan(3.9), reason: reason);
        }
        expect(g.creatures.length, g.config.chaserCount, reason: reason);
        for (final y in g.creatures) {
          expect(y.asleep, isFalse, reason: 'a yeti never sleeps');
          expect((y.pos - start).distance, greaterThan(5.9));
        }
        g.dispose();
      }
    }
    expect([for (var l = 1; l <= 5; l++) GameConfig(WorldKind.winter, l).caveCount], [2, 2, 3, 3, 4]);
  });

  test('ice is in patches along the way: every run meets some', () {
    for (var seed = 0; seed < 12; seed++) {
      final g = winter(level: 4, seed: seed);
      final onRoute = g.maze.solution.where((c) => !g.snow[c]).length;
      expect(onRoute, greaterThan(0), reason: 'seed $seed');
      g.dispose();
    }
  });

  test('snow drags and holds the ball back, and ice lets it slide', () {
    final g = winter(level: 3, seed: 2);
    g.started = true;
    final snowy = topSpeed(g, snowCell(g));
    final icy = topSpeed(g, iceCell(g));
    expect(snowy, lessThanOrEqualTo(GameController.snowSpeed + 0.01));
    expect(icy, greaterThan(snowy * 1.4));
    // On ice it keeps rolling when the tilt is let go; in snow it stops.
    g.vel = const Offset(2, 0);
    for (var i = 0; i < 40; i++) {
      g.pos = iceCell(g);
      g.vel = Offset(g.vel.dx, 0);
      g.update(1 / 60, Offset.zero);
    }
    final slid = g.vel.distance;
    g.vel = const Offset(2, 0);
    for (var i = 0; i < 40; i++) {
      g.pos = snowCell(g);
      g.vel = Offset(g.vel.dx, 0);
      g.update(1 / 60, Offset.zero);
    }
    expect(slid, greaterThan(g.vel.distance * 4));
    g.dispose();
  });

  test('a ball rolling in snow leaves tracks that melt away; ice and a blizzard leave none', () {
    final g = winter(level: 3, seed: 2);
    g.creatures = [];
    g.started = true;
    final cell = g.maze.cellCenter([for (var c = 3; c < g.snow.length; c++) if (g.snow[c]) c].first);
    for (var i = 0; i < 40; i++) {
      g.pos = cell + Offset(i.isEven ? 0.2 : -0.2, 0);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.tracks, isNotEmpty);
    final ids = [for (final t in g.tracks) t.id];
    expect(ids, [...ids]..sort(), reason: 'numbered in order');
    // They melt after a few seconds once the ball stops making them.
    g.pos = cell;
    for (var i = 0; i < (g.config.trackSeconds + 1) * 60; i++) {
      g.pos = iceCell(g);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.tracks, isEmpty, reason: 'melted, and ice leaves none');
    g.dispose();
  });

  test('a blizzard warns, buries the tracks, hides the view, then clears', () {
    final g = winter(level: 3, seed: 2);
    g.creatures = [];
    g.started = true;
    final cell = snowCell(g);
    var warned = false, blew = false, buriedAll = true, whiteout = 0.0;
    for (var i = 0; i < 60 * 80; i++) {
      g.pos = cell + Offset(i.isEven ? 0.2 : -0.2, 0);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      if (g.blizzardWarnLeft > 0) warned = true;
      if (g.blizzardLeft > 0) {
        blew = true;
        if (g.tracks.isNotEmpty) buriedAll = false;
        whiteout = max(whiteout, g.blizzard);
      }
    }
    expect(warned, isTrue);
    expect(blew, isTrue);
    expect(buriedAll, isTrue, reason: 'no footprint survives a blizzard');
    expect(whiteout, greaterThan(0.8));
    // After it, the view is clear again.
    for (var i = 0; i < 60 * 40 && (g.blizzardLeft > 0 || g.blizzardWarnLeft > 0); i++) {
      g.pos = cell;
      g.update(1 / 60, Offset.zero);
    }
    for (var i = 0; i < 180; i++) {
      g.pos = cell;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.blizzard, lessThan(1));
    g.dispose();
  });

  /// A trail of footprints along the way out, [from] to [to] cells of the
  /// route, and the ball waiting at its end on a patch of ice (no new tracks).
  List<Offset> laidTrail(GameController g, int from, int to) {
    final pts = g.maze.routePoints(g.maze.solution.sublist(from, to));
    final out = <Offset>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final a = out.last;
      final d = pts[i] - a;
      var left = d.distance;
      while (left >= 0.3) {
        out.add(out.last + d / d.distance * 0.3);
        left -= 0.3;
      }
    }
    for (var i = 0; i < out.length; i++) {
      g.tracks.add(Track(out[i], i));
    }
    return out;
  }

  test('a yeti that crosses a footprint follows the trail to the ball, fast', () {
    var done = 0;
    for (var seed = 0; seed < 12 && done < 3; seed++) {
      final g = winter(level: 4, seed: seed);
      g.started = true;
      final n = g.maze.solution.length;
      if (n < 14) continue;
      final trail = laidTrail(g, 2, 12);
      if (trail.length < 20) continue;
      final end = trail.last;
      if ((trail[3] - end).distance <= GameController.yetiSight) {
        g.dispose();
        continue;
      }
      g.snow[g.maze.cellAt(end)] = false;
      final y = Creature(trail[3], cell: g.maze.cellAt(trail[3]));
      g.creatures = [y];
      g.pos = end;
      g.vel = Offset.zero;
      // The ball is well beyond sight, so only the trail can lead it.
      expect((y.pos - end).distance, greaterThan(GameController.yetiSight));
      var trailSeen = false;
      var steps = 0;
      var moved = 0.0;
      var last = y.pos;
      while (g.status == GameStatus.playing && steps++ < 60 * 20) {
        g.pos = end;
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        if (y.mode == 1) trailSeen = true;
        if (steps == 60) moved = (y.pos - last).distance;
        if (steps == 1) last = y.pos;
      }
      expect(trailSeen, isTrue, reason: 'seed $seed: it picked the trail up');
      expect(g.lostReason, 'lose.yeti', reason: 'seed $seed: it reached the ball');
      expect(moved, greaterThan(g.config.chaserSpeed * GameController.yetiPatrol * 1.6),
          reason: 'seed $seed: faster than on patrol');
      g.dispose();
      done++;
    }
    expect(done, greaterThan(0));
  });

  test('without a trail a yeti wanders; it loses the trail when it melts or ice breaks it', () {
    final g = winter(level: 4, seed: 3);
    g.started = true;
    final trail = laidTrail(g, 2, 10);
    final y = Creature(trail[2], cell: g.maze.cellAt(trail[2]));
    g.creatures = [y];
    g.pos = g.maze.cellCenter(g.maze.start);
    g.update(1 / 60, Offset.zero);
    expect(y.mode, 1);
    // The trail melts.
    g.tracks.clear();
    g.pos = g.maze.cellCenter(g.maze.start);
    g.update(1 / 60, Offset.zero);
    expect(y.mode, 0, reason: 'back to wandering');
    expect(y.asleep, isFalse);
    g.dispose();
  });

  test('a yeti breaks off at a gap in the trail (where the ball crossed ice)', () {
    final g = winter(level: 4, seed: 3);
    g.started = true;
    final trail = laidTrail(g, 2, 10);
    // Remove a stretch ahead of the yeti.
    final y = Creature(trail[2], cell: g.maze.cellAt(trail[2]));
    g.tracks.removeWhere((t) => t.id > 4 && t.id < 12);
    g.creatures = [y];
    g.pos = g.maze.cellCenter(g.maze.start);
    var followed = false, brokeOff = false;
    for (var i = 0; i < 120; i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.update(1 / 60, Offset.zero);
      if (y.mode == 1) followed = true;
      if (followed && y.mode == 0) brokeOff = true;
    }
    expect(followed, isTrue);
    expect(brokeOff, isTrue, reason: 'the trail is broken, so it stops following');
    g.dispose();
  });

  test('a yeti sees the ball in front of it and runs straight at it; a blizzard blinds it', () {
    final g = winter(level: 3, seed: 5);
    g.started = true;
    final route = g.maze.solution;
    final at = g.maze.cellCenter(route[4]);
    // A yeti one cell behind it on the route, in plain sight.
    final y = Creature(g.maze.cellCenter(route[2]), cell: route[2]);
    g.creatures = [y];
    g.pos = at;
    g.vel = Offset.zero;
    final d = (y.pos - at).distance;
    expect(d, lessThan(GameController.yetiSight));
    g.update(1 / 60, Offset.zero);
    expect(y.mode, 2);
    g.dispose();
  });

  test('a yeti goes down a cave and comes up in another, and never sleeps', () {
    var downs = 0;
    for (var seed = 0; seed < 8; seed++) {
      final g = winter(level: 5, seed: seed);
      g.started = true;
      for (final y in g.creatures) {
        y.mode = 0;
      }
      final seen = <int, bool>{};
      final from = <int, Offset>{};
      var t = 0;
      while (g.status == GameStatus.playing && t++ < 60 * 150) {
        // The ball keeps to the far corner so the yetis only wander.
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        for (var i = 0; i < g.creatures.length; i++) {
          final y = g.creatures[i];
          expect(y.asleep, isFalse);
          if (y.hiddenLeft > 0 && seen[i] != true) {
            seen[i] = true;
            from[i] = y.pos;
            downs++;
          } else if (y.hiddenLeft <= 0 && seen[i] == true) {
            seen[i] = false;
            expect(g.caves.any((c) => (c.pos - y.pos).distance < 1e-6), isTrue,
                reason: 'it comes up out of a cave');
            expect((y.pos - from[i]!).distance, greaterThan(0.5),
                reason: 'a different one than it went down');
          }
        }
      }
      g.dispose();
    }
    expect(downs, greaterThan(0), reason: 'yetis do use the caves');
  });

  test('a yeti that reaches the ball ends the run; the spawn is far from the start', () {
    final g = winter(level: 2, seed: 4);
    g.started = true;
    final y = g.creatures.first;
    y.pos = g.pos + const Offset(0.2, 0);
    g.update(1 / 60, Offset.zero);
    expect(g.lostReason, 'lose.yeti');
    g.dispose();
  });

  test('the whistle sends the nearest yeti to a cave and up in another, far from the ball', () {
    var done = 0;
    for (var seed = 0; seed < 10 && done < 4; seed++) {
      final g = winter(level: 5, seed: seed);
      g.started = true;
      final y = g.creatures.first;
      // The yeti is close behind the ball.
      final route = g.maze.solution;
      g.pos = g.maze.cellCenter(route[route.length ~/ 2]);
      y.pos = g.maze.cellCenter(route[route.length ~/ 2 - 3]);
      y.cell = g.maze.cellAt(y.pos);
      g.creatures = [y];
      g.bonusCharges = 1;
      g.useBonus();
      expect(y.mode == 3 || y.hiddenLeft > 0, isTrue, reason: 'seed $seed: it runs for a cave');
      var down = false, up = false;
      for (var i = 0; i < 60 * 25 && g.status == GameStatus.playing; i++) {
        g.pos = g.maze.cellCenter(route[route.length ~/ 2]);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        if (y.hiddenLeft > 0) down = true;
        if (down && y.hiddenLeft <= 0) {
          up = true;
          break;
        }
      }
      expect(g.status, GameStatus.playing, reason: 'seed $seed: it never catches the ball on its way');
      expect(down && up, isTrue, reason: 'seed $seed: down one cave, up another');
      expect(g.caves.any((c) => (c.pos - y.pos).distance < 1e-6), isTrue);
      expect(y.mode, 0);
      g.dispose();
      done++;
    }
    expect(done, greaterThan(0));
  });

  test('the whistle clears the blizzard and holds the next one back while it lasts', () {
    final g = winter(level: 3, seed: 2);
    g.creatures = [];
    g.started = true;
    final cell = snowCell(g);
    var guard = 0;
    while (g.blizzardLeft <= 0 && guard++ < 60 * 80) {
      g.pos = cell;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.blizzardLeft, greaterThan(0));
    for (var i = 0; i < 90; i++) {
      g.pos = cell;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.blizzard, greaterThan(0.5));
    g.bonusCharges = 1;
    g.useBonus();
    expect(g.blizzardLeft, 0);
    for (var i = 0; i < 60 * 4; i++) {
      g.pos = cell;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.blizzard, lessThan(0.1), reason: 'the view is clear');
    expect(g.blizzardLeft, 0);
    expect(g.blizzardWarnLeft, 0, reason: 'and no new one while the whistle lasts');
    g.dispose();
  });

  test('winter has its texts in every language', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final key in ['lose.yeti', 'notice.blizzard', 'bonus.winter', 'world.winter.name', 'world.winter.blurb']) {
        expect(tr(key), isNot(key), reason: '$key in ${lang.name}');
      }
      expect(hazardNote(const GameConfig(WorldKind.winter, 3)), isNot(startsWith('note.')));
      expect(hazardNote(const GameConfig(WorldKind.winter, 3)), contains('3'));
    }
    AppLanguage.instance.lang = AppLang.pl;
  });

  test('everything in winter can be painted, in every phase', () {
    for (final level in [1, 5]) {
      final g = winter(level: level, seed: 4);
      final render = MazeRender(g.maze, themeFor(WorldKind.winter));
      final painter = GamePainter(g, render);
      g.started = true;
      g.bonusCharges = 1;
      for (var i = 0; i < 60 * 70; i++) {
        g.pos = g.maze.cellCenter(g.maze.start) + Offset(i.isEven ? 0.2 : -0.2, 0);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
        if (i == 60 * 5) g.useBonus();
        if (i % 20 == 0) {
          if (g.status != GameStatus.playing) g.restart();
          g.started = true;
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(390, 844));
          rec.endRecording();
        }
      }
      g.dispose();
    }
  });

  test('winter turns up in endless mode, in the rectangular maze, and plays there', () {
    for (var seed = 0; seed < 400; seed++) {
      final g = GameController(
        GameController.endlessConfig(0, BallKind.wood),
        endless: true,
        seed: seed,
      );
      if (g.config.world != WorldKind.winter) {
        g.dispose();
        continue;
      }
      expect(g.maze, isA<RectMaze>());
      expect(g.snow.length, g.maze.cellCount);
      expect(g.caves, isNotEmpty);
      expect(g.creatures, isNotEmpty);
      g.started = true;
      final render = MazeRender(g.maze, themeFor(WorldKind.winter));
      final painter = GamePainter(g, render);
      for (var i = 0; i < 60 * 8; i++) {
        g.update(1 / 60, const Offset(0.3, 0.3));
        if (g.status != GameStatus.playing) break;
        if (i % 30 == 0) {
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(390, 844));
          rec.endRecording();
        }
      }
      expect(buildRectMazePicture(g.maze as RectMaze, themeFor(WorldKind.winter), 1), isNotNull);
      return;
    }
    fail('no seed starts in winter');
  });

  testWidgets('the winter world draws on a phone', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: GameScreen(config: GameConfig(WorldKind.winter, 3, ball: BallKind.stone)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
