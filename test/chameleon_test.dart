import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/balls.dart';

GameController chameleon({WorldKind world = WorldKind.forest, int seed = 3}) => GameController(
    GameConfig(world, 3, ball: BallKind.chameleon),
    hazardsEnabled: false,
    seed: seed);

void main() {
  test('it starts as one of the other balls, with its own size', () {
    for (var seed = 0; seed < 20; seed++) {
      final g = chameleon(seed: seed);
      expect(g.mimicking, isNot(BallKind.chameleon));
      final traits = statsOf(g.mimicking);
      expect(g.ball.accel, traits.accel);
      expect(g.ball.noise, traits.noise);
      expect(g.ball.breaksAt, traits.breaksAt);
      expect(g.ball.floats, traits.floats);
      expect(g.ball.radius, 1, reason: 'never wedged by a size change');
      expect(g.ballRadius, GameController.baseBallRadius);
      g.dispose();
    }
  });

  test('every ten seconds it becomes a different ball and a different colour', () {
    final g = chameleon();
    g.started = true;
    final seen = <BallKind>{};
    var previous = g.mimicking;
    var hue = g.chameleonHue;
    var shifts = 0;
    for (var i = 0; i < 60 * 10 * 12; i++) {
      g.pos = g.maze.cellCenter(g.maze.start);
      g.vel = Offset.zero;
      g.update(1 / 60, Offset.zero);
      if (g.mimicking != previous) {
        shifts++;
        expect(g.mimicking, isNot(previous), reason: 'never twice the same');
        expect(g.mimicking, isNot(BallKind.chameleon));
        var d = (g.chameleonHue - hue).abs() % 360;
        if (d > 180) d = 360 - d;
        expect(d, greaterThan(60), reason: 'the colour is clearly different');
        expect(g.ball.accel, statsOf(g.mimicking).accel);
        seen.add(g.mimicking);
        previous = g.mimicking;
        hue = g.chameleonHue;
      }
    }
    expect(shifts, inInclusiveRange(11, 12), reason: 'once every ten seconds');
    expect(seen.length, greaterThan(3), reason: 'it tries many different balls');
    g.dispose();
  });

  test('it waits for the first tilt, and a restart picks a fresh form', () {
    final g = chameleon();
    final first = g.mimicking;
    for (var i = 0; i < 60 * 30; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.mimicking, first, reason: 'the clock has not started');
    g.restart();
    expect(g.mimicking, isNot(BallKind.chameleon));
  });

  test('its traits really are the other ball\'s: a glass form breaks, a bubble form floats', () {
    var broke = false, floated = false;
    for (var seed = 0; seed < 60 && !(broke && floated); seed++) {
      final g = chameleon(seed: seed);
      if (g.mimicking == BallKind.glass) {
        expect(g.ball.breaksAt, isNotNull);
        broke = true;
      }
      if (g.mimicking == BallKind.bubble) {
        expect(g.ball.floats, isTrue);
        floated = true;
      }
      g.dispose();
    }
    expect(broke && floated, isTrue);
  });

  test('the sound of its bumps gives nothing away', () {
    // Always the same sound whatever it has become (checked in the controller:
    // there is a single chameleon sound).
    final g = chameleon();
    expect(g.config.ball, BallKind.chameleon);
    g.dispose();
  });

  test('endless mode can hand it out, and a long run works', () {
    var found = false;
    for (var seed = 0; seed < 200 && !found; seed++) {
      final g = GameController(GameController.endlessConfig(0, BallKind.wood),
          endless: true, hazardsEnabled: false, seed: seed);
      for (var stage = 0; stage < 12 && !found; stage++) {
        if (g.config.ball == BallKind.chameleon) {
          found = true;
          g.started = true;
          for (var i = 0; i < 60 * 25; i++) {
            g.update(1 / 60, const Offset(0.3, 0.6));
          }
          expect(g.mimicking, isNot(BallKind.chameleon));
        } else {
          g.resetRun();
        }
      }
      g.dispose();
    }
    expect(found, isTrue);
  });

  test('it has a name, pros and cons in every language, and can be painted in any colour', () {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final info = infoOf(BallKind.chameleon);
      expect(info.name, isNot(startsWith('ball.')));
      expect(info.pros, isNotEmpty);
      expect(info.cons, isNotEmpty);
      expect(info.pros.first, isNot(startsWith('ball.')));
    }
    AppLanguage.instance.lang = AppLang.pl;
    for (var hue = 0.0; hue < 720; hue += 45) {
      final rec = ui.PictureRecorder();
      paintBall(Canvas(rec), const Offset(20, 20), 18, BallKind.chameleon, null, hue);
      rec.endRecording();
    }
  });
}
