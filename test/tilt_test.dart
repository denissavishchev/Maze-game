import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/tilt.dart';

/// Gravity as the accelerometer reports it for a phone pitched back by
/// [pitch] radians (0 = lying flat) and rolled sideways by [roll].
Gravity pose(double pitch, {double roll = 0}) => Gravity.fromAccel(
      9.81 * cos(pitch) * sin(roll),
      9.81 * sin(pitch),
      9.81 * cos(pitch) * cos(roll),
    );

double deg(double d) => d * pi / 180;

void main() {
  test('lying flat: tilting a side down rolls that way, as before', () {
    final flat = pose(0);
    // Right edge down reads negative x -> the ball goes right.
    expect(tiltBetween(flat, Gravity.fromAccel(-2, 0, 9.6)).dx, greaterThan(0.3));
    expect(tiltBetween(flat, Gravity.fromAccel(2, 0, 9.6)).dx, lessThan(-0.3));
    // Positive y -> down the screen.
    expect(tiltBetween(flat, Gravity.fromAccel(0, 2, 9.6)).dy, greaterThan(0.3));
    expect(tiltBetween(flat, Gravity.fromAccel(0, -2, 9.6)).dy, lessThan(-0.3));
    // Not tilted: nothing.
    expect(tiltBetween(flat, flat).distance, closeTo(0, 1e-9));
    // Full tilt saturates at length 1.
    expect(tiltBetween(flat, Gravity.fromAccel(-9, 0, 3)).distance, closeTo(1, 1e-9));
  });

  test('a phone held at an angle feels exactly like one lying flat', () {
    final flat = tiltBetween(pose(0), pose(deg(6)));
    for (final angle in [20.0, 35.0, 50.0, 65.0]) {
      final held = tiltBetween(pose(deg(angle)), pose(deg(angle + 6)));
      expect(held.dy, closeTo(flat.dy, 1e-6), reason: 'forward tilt at $angle degrees');
      expect(held.dx, closeTo(0, 1e-6));
    }
    // The old raw-reading way saturated: the same 6 degrees changed y by far
    // less on a steep pose (g * (sin 65+6 - sin 65) is under half of g * sin 6).
    final raw = 9.81 * (sin(deg(71)) - sin(deg(65)));
    expect(raw, lessThan(9.81 * sin(deg(6))));
  });

  test('rolling sideways from an angled pose still goes the right way', () {
    final base = pose(deg(45));
    expect(tiltBetween(base, pose(deg(45), roll: deg(-8))).dx, greaterThan(0.1));
    expect(tiltBetween(base, pose(deg(45), roll: deg(8))).dx, lessThan(-0.1));
  });

  test('changing grip slowly before the start never starts the ball', () {
    final t = TiltTracker();
    t.feed(0, 9.81 * sin(deg(50)), 9.81 * cos(deg(50)));
    var worst = 0.0;
    const dt = 1 / 60;
    // 2 seconds holding at 50 degrees, then relaxing to 30 over 2 seconds
    // (10 degrees a second), then holding.
    for (var i = 0; i < 60 * 6; i++) {
      final s = i / 60;
      final angle = s < 2 ? 50.0 : (s < 4 ? 50 - 10 * (s - 2) : 30.0);
      t.feed(0, 9.81 * sin(deg(angle)), 9.81 * cos(deg(angle)));
      worst = max(worst, t.tilt.distance);
      t.step(dt, started: false, stillTime: 0);
    }
    expect(worst, lessThan(0.15), reason: 'below the tilt that starts the game');
    expect(t.tilt.distance, lessThan(0.02), reason: 'settled: the new grip is level');
  });

  test('a deliberate quick tilt is not followed away, so it starts the game', () {
    final t = TiltTracker();
    t.feed(0, 9.81 * sin(deg(40)), 9.81 * cos(deg(40)));
    for (var i = 0; i < 60; i++) {
      t.step(1 / 60, started: false, stillTime: 0); // settle
    }
    // 8 degrees in a fifth of a second.
    var peak = 0.0;
    for (var i = 0; i < 12; i++) {
      final angle = 40 + 8 * (i + 1) / 12;
      t.feed(0, 9.81 * sin(deg(angle)), 9.81 * cos(deg(angle)));
      peak = max(peak, t.tilt.distance);
      t.step(1 / 60, started: false, stillTime: 0);
    }
    expect(peak, greaterThan(0.15));
  });

  test('once playing, the level stays put; a steady hand slowly re-centres it', () {
    final t = TiltTracker();
    t.feed(0, 0, 9.81);
    // Hold a deliberate 15 degree tilt for 5 seconds while moving: it stays.
    t.feed(0, 9.81 * sin(deg(15)), 9.81 * cos(deg(15)));
    final tilted = t.tilt.distance;
    for (var i = 0; i < 300; i++) {
      t.step(1 / 60, started: true, stillTime: 0);
    }
    expect(t.tilt.distance, closeTo(tilted, 1e-9));

    // A tiny lean while the ball rests is slowly re-zeroed.
    final r = TiltTracker();
    r.feed(0, 0, 9.81);
    r.feed(0, 9.81 * sin(deg(1.5)), 9.81 * cos(deg(1.5)));
    final lean = r.tilt.distance;
    expect(lean, lessThan(TiltTracker.steady));
    for (var i = 0; i < 60 * 12; i++) {
      r.step(1 / 60, started: true, stillTime: 5);
    }
    expect(r.tilt.distance, lessThan(lean / 2));

    // But a real tilt that holds the ball against a wall is never eroded.
    final w = TiltTracker();
    w.feed(0, 0, 9.81);
    w.feed(0, 9.81 * sin(deg(12)), 9.81 * cos(deg(12)));
    final push = w.tilt.distance;
    for (var i = 0; i < 60 * 12; i++) {
      w.step(1 / 60, started: true, stillTime: 5);
    }
    expect(w.tilt.distance, closeTo(push, 1e-9));
  });

  test('without a sensor there is no tilt', () {
    expect(TiltTracker().hasSensor, isFalse);
    expect(TiltTracker().tilt.distance, 0);
    final t = TiltTracker()..feed(0, 0, 9.81);
    expect(t.hasSensor, isTrue);
    expect(t.tilt.distance, closeTo(0, 1e-9), reason: 'the first pose is level');
  });

  test('calibrating makes the present pose level', () {
    final t = TiltTracker();
    t.feed(0, 0, 9.81);
    t.feed(0, 9.81 * sin(deg(20)), 9.81 * cos(deg(20)));
    expect(t.tilt.distance, greaterThan(0.5));
    t.calibrate();
    expect(t.tilt.distance, closeTo(0, 1e-9));
    expect(TiltTracker().hasSensor, isFalse);
    TiltTracker().calibrate(); // without a sensor: harmless
  });
}
