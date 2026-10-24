import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/balls.dart';

GameController play(WorldKind w, BallKind b, {int level = 3, int seed = 3}) =>
    GameController(GameConfig(w, level, ball: b), seed: seed);

void main() {
  test('the bubble is big, light, almost silent and bouncy, and pops at a light knock', () {
    final s = statsOf(BallKind.bubble);
    expect(s.floats, isTrue);
    expect(s.radius, greaterThan(statsOf(BallKind.wood).radius));
    expect(s.noise, lessThan(0.2));
    expect(s.bounce, greaterThan(0.4));
    expect(s.windResist, lessThan(statsOf(BallKind.paper).windResist));
    expect(s.breaksAt, isNotNull);
    expect(s.breaksAt!, lessThan(statsOf(BallKind.glass).breaksAt! - 1));
    for (final k in BallKind.values.where((k) => k != BallKind.bubble)) {
      expect(statsOf(k).floats, isFalse);
    }
  });

  test('a bubble floats over a bog, fog and a crumbling floor', () {
    final mud = play(WorldKind.mud, BallKind.bubble);
    mud.started = true;
    mud.pos = mud.mud.first.pos;
    mud.vel = Offset.zero;
    for (var i = 0; i < 60 * 6; i++) {
      mud.update(1 / 60, Offset.zero);
    }
    expect(mud.sink, 0, reason: 'does not sink');
    expect(mud.status, GameStatus.playing);

    final glass = play(WorldKind.glass, BallKind.bubble, level: 5);
    glass.started = true;
    for (var i = 0; i < 60 * 8; i++) {
      glass.update(1 / 60, Offset.zero);
      glass.beams.clear();
    }
    expect(glass.cracks, isEmpty);
    expect(glass.status, GameStatus.playing);

    // The same stand-still ruins a wooden ball.
    final wood = play(WorldKind.glass, BallKind.wood, level: 5);
    wood.started = true;
    for (var i = 0; i < 60 * 8; i++) {
      wood.update(1 / 60, Offset.zero);
      wood.beams.clear();
    }
    expect(wood.lostReason, 'lose.floor');
  });

  test('a knock pops the bubble with its own message, a gentle bump does not', () {
    String? popped(double speed) {
      final g = GameController(const GameConfig(WorldKind.forest, 3, ball: BallKind.bubble),
          hazardsEnabled: false, seed: 4);
      final m = g.maze as PolarMaze;
      final n = m.sectors.last;
      final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
      final out = Offset(cos(theta), sin(theta));
      g.started = true;
      g.pos = out * (m.radius - 0.5);
      g.vel = out * speed;
      for (var i = 0; i < 30 && !g.lost; i++) {
        g.update(1 / 60, out * 1.0);
      }
      final r = g.lost ? g.lostReason : null;
      g.dispose();
      return r;
    }

    expect(popped(6), 'lose.bubble');
    expect(popped(4.4), 'lose.bubble', reason: 'even a modest knock');
    expect(popped(3.0), isNull, reason: 'a hard bump from a current is survived');
    expect(popped(1.2), isNull);
  });

  strainTests();

  test('texts exist in every language', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final info = infoOf(BallKind.bubble);
      expect(info.name, isNot(startsWith('ball.')));
      expect(info.pros, isNotEmpty);
      expect(info.cons, isNotEmpty);
      expect(tr('lose.bubble'), isNot('lose.bubble'));
    }
    AppLanguage.instance.lang = AppLang.pl;
  });
}

void strainTests() {
  GameController hit(BallKind b, double speed) {
    final g = GameController(GameConfig(WorldKind.forest, 3, ball: b),
        hazardsEnabled: false, seed: 4);
    final m = g.maze as PolarMaze;
    final n = m.sectors.last;
    final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
    final out = Offset(cos(theta), sin(theta));
    g.started = true;
    g.pos = out * (m.radius - 0.5);
    g.vel = out * speed;
    for (var i = 0; i < 30 && !g.lost; i++) {
      g.update(1 / 60, out * 1.0);
    }
    return g;
  }

  test('a fragile ball shows how near a knock came to breaking it, then recovers', () {
    final g = hit(BallKind.glass, 3.0);
    expect(g.lost, isFalse);
    expect(g.strain, inInclusiveRange(0.2, 0.95));
    final peak = g.strain;
    for (var i = 0; i < 60; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.strain, closeTo(peak, 0.01), reason: 'held for a moment');
    for (var i = 0; i < 60 * 8; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.strain, lessThan(peak * 0.5));
  });

  test('a ball that cannot break never shows strain; a popped one shows full', () {
    expect(hit(BallKind.wood, 6).strain, 0);
    expect(hit(BallKind.bubble, 6).strain, 1);
  });
}
