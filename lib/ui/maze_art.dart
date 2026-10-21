import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/polar_maze.dart';
import 'palette.dart';
import 'worlds.dart';

const Color _ink = Palette.ink;

/// Everything that never changes while a maze is played: scenery, floor and
/// walls, drawn like the key art: thick dark outlines, soft cartoon shading,
/// a sand path between mossy, leafy or stony walls. Recorded once into a
/// [ui.Picture] in maze units.
ui.Picture buildMazePicture(PolarMaze m, WorldTheme t, int seed,
    {bool scenery = true}) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final rnd = Random(seed);
  final R = m.radius;

  // [scenery] false leaves the outside transparent, so the maze can be laid
  // over any background.
  if (scenery) {
    c.drawRect(
      Rect.fromCircle(center: Offset.zero, radius: R + 16),
      Paint()..color = t.bg,
    );
    _ground(c, t, rnd, R);
    _scenery(c, t, rnd, R);
  }
  _floor(c, m, t, rnd);
  _walls(c, m, t, rnd);
  return rec.endRecording();
}

// ---- floor -----------------------------------------------------------------

void _floor(Canvas c, PolarMaze m, WorldTheme t, Random rnd) {
  final R = m.radius;
  // The short fenced trail outside the entrance, with an outlined edge.
  final trail = m.trailPath();
  c.drawPath(
    trail,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.22
      ..strokeJoin = StrokeJoin.round
      ..color = _ink,
  );
  c.drawPath(trail, Paint()..color = t.floor);
  c.drawCircle(Offset.zero, R, Paint()..color = t.floor);

  final dark = Paint()..color = t.floorDark.withValues(alpha: 0.6);
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.045
    ..color = t.floorDark.withValues(alpha: 0.75);
  switch (t.floorStyle) {
    case FloorStyle.sand:
      // Pebbles and trampled patches, each with a tiny highlight.
      for (var i = 0; i < R * R * 3.5; i++) {
        final a = rnd.nextDouble() * kTwoPi;
        final r = sqrt(rnd.nextDouble()) * (R - 0.3);
        final p = polar(r, a);
        final s = 0.04 + rnd.nextDouble() * 0.09;
        c.drawOval(Rect.fromCenter(center: p, width: s * 2.2, height: s * 1.5), dark);
        c.drawOval(
          Rect.fromCenter(center: p.translate(-s * 0.3, -s * 0.3), width: s, height: s * 0.6),
          Paint()..color = Colors.white.withValues(alpha: 0.3),
        );
      }
    case FloorStyle.flagstone:
      // Rows of big flagstones: rings with staggered joints.
      for (var r = 0.8; r < R; r += 0.8) {
        c.drawArc(Rect.fromCircle(center: Offset.zero, radius: r), 0, kTwoPi, false, line);
        final count = max(5, (kTwoPi * (r + 0.4) / 1.0).round());
        final stagger = (r / 0.8).round().isOdd ? 0.5 : 0.0;
        for (var k = 0; k < count; k++) {
          final a = (k + stagger) * kTwoPi / count;
          c.drawLine(polar(r, a), polar(min(r + 0.8, R), a), line);
        }
      }
      for (var i = 0; i < R * R * 2; i++) {
        final p = polar(sqrt(rnd.nextDouble()) * (R - 0.3), rnd.nextDouble() * kTwoPi);
        c.drawCircle(p, 0.03 + rnd.nextDouble() * 0.04, dark);
      }
    case FloorStyle.cobble:
      // Round cobbles laid in staggered rings.
      var ring = 0;
      for (var r = 0.45; r < R; r += 0.46) {
        final count = max(6, (kTwoPi * r / 0.46).round());
        for (var k = 0; k < count; k++) {
          final a = (k + (ring.isOdd ? 0.5 : 0)) * kTwoPi / count;
          final p = polar(r, a);
          c.drawCircle(p, 0.2, Paint()..color = Colors.white.withValues(alpha: 0.1));
          c.drawCircle(
            p,
            0.2,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.04
              ..color = t.floorDark.withValues(alpha: 0.7),
          );
        }
        ring++;
      }
  }
}

// ---- walls -----------------------------------------------------------------

void _walls(Canvas c, PolarMaze m, WorldTheme t, Random rnd) {
  final walls = m.wallPath();
  Paint stroke(Color color, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = w
    ..color = color;

  // Soft shadow, thick dark outline, rim, body, highlight.
  c.save();
  c.translate(0.07, 0.12);
  c.drawPath(walls, stroke(Colors.black.withValues(alpha: 0.35), 0.48));
  c.restore();
  c.drawPath(walls, stroke(_ink, 0.45));
  c.drawPath(walls, stroke(t.wallBase, 0.37));
  c.drawPath(walls, stroke(t.wallMain, 0.29));
  c.save();
  c.translate(-0.02, -0.05);
  c.drawPath(walls, stroke(t.wallHi.withValues(alpha: 0.8), 0.08));
  c.restore();

  // Surface detail, placed along the walls.
  final light = Paint()..color = t.wallHi;
  final shade = Paint()..color = t.wallBase.withValues(alpha: 0.6);
  final joint = Paint()
    ..color = _ink.withValues(alpha: 0.45)
    ..strokeWidth = 0.03
    ..strokeCap = StrokeCap.round;
  final torches = <Offset>[];

  for (final metric in walls.computeMetrics()) {
    final step = switch (t.wallStyle) {
      WallStyle.hedge => 0.2,
      WallStyle.mossRock => 0.2,
      WallStyle.snowRock => 0.22,
      WallStyle.brick => 0.34,
      WallStyle.castle => 0.5,
    };
    var k = 0;
    for (var d = 0.0; d < metric.length; d += step, k++) {
      final tan = metric.getTangentForOffset(d);
      if (tan == null) continue;
      final normal = Offset(-tan.vector.dy, tan.vector.dx);
      final side = (rnd.nextDouble() - 0.5) * 0.18;
      switch (t.wallStyle) {
        case WallStyle.hedge:
          // Clumps of leaves.
          c.drawCircle(tan.position + normal * side, 0.04 + rnd.nextDouble() * 0.05,
              rnd.nextBool() ? light.withAlpha(150) : shade);
        case WallStyle.mossRock:
          if (k % 2 == 0) {
            c.drawLine(tan.position + normal * 0.07, tan.position - normal * 0.07, joint);
          }
          if (rnd.nextDouble() < 0.55) {
            // Moss growing on the top of the rock.
            c.drawCircle(tan.position + normal * -0.07 + normal * side * 0.4,
                0.05 + rnd.nextDouble() * 0.05, light);
          }
        case WallStyle.snowRock:
          if (rnd.nextDouble() < 0.85) {
            c.drawCircle(tan.position + normal * (-0.05 + side * 0.3),
                0.06 + rnd.nextDouble() * 0.05, light);
          }
          if (k % 3 == 0) {
            c.drawLine(tan.position + normal * 0.08, tan.position, joint);
          }
        case WallStyle.brick:
          // Brick joints across the wall, staggered by a half step.
          final off = k.isOdd ? 0.05 : -0.05;
          c.drawLine(tan.position + normal * (0.1 + off), tan.position - normal * (0.1 - off), joint);
          if (rnd.nextDouble() < 0.012) torches.add(tan.position);
        case WallStyle.castle:
          c.drawLine(tan.position + normal * 0.11, tan.position - normal * 0.11, joint);
          c.drawCircle(tan.position + normal * side * 0.4, 0.025, shade);
      }
    }
  }

  // Torches burning in the dungeon walls: a warm glow and a bright flame.
  for (final p in torches) {
    c.drawCircle(
      p,
      1.1,
      Paint()
        ..shader = ui.Gradient.radial(p, 1.1, [
          const Color(0xFFFFA030).withValues(alpha: 0.5),
          const Color(0xFFFFA030).withValues(alpha: 0),
        ]),
    );
    c.drawCircle(p, 0.09, Paint()..color = const Color(0xFFFFE08A));
    c.drawCircle(p, 0.055, Paint()..color = Colors.white);
  }
}

extension on Paint {
  /// A copy of this paint with an alpha out of 255.
  Paint withAlpha(int a) => Paint()..color = color.withAlpha(a);
}

// ---- ground and scenery outside the maze ---------------------------------------

void _ground(Canvas c, WorldTheme t, Random rnd, double R) {
  // Big soft patches so the ground is not one flat colour.
  for (var i = 0; i < 70; i++) {
    final p = polar(R + 1.5 + rnd.nextDouble() * 11, rnd.nextDouble() * kTwoPi);
    final lighter = rnd.nextBool();
    c.drawCircle(
      p,
      0.8 + rnd.nextDouble() * 2.2,
      Paint()
        ..color = (lighter ? Colors.white : Colors.black).withValues(alpha: 0.07),
    );
  }
}

Offset _spot(Random rnd, double R, {double inner = 1.9, double span = 10}) =>
    polar(R + inner + rnd.nextDouble() * span, rnd.nextDouble() * kTwoPi);

/// A round bush or tree crown: overlapping circles, outlined, lit from the
/// top left.
void _bush(Canvas c, Offset p, double s, Color base, Color mid, Color hi) {
  const lobes = [
    (0.0, 0.0, 1.0),
    (0.62, 0.18, 0.74),
    (-0.58, 0.22, 0.78),
    (0.08, -0.55, 0.7),
    (0.36, 0.56, 0.62),
    (-0.32, -0.36, 0.6),
  ];
  for (final (dx, dy, r) in lobes) {
    c.drawCircle(p + Offset(dx, dy) * s, r * s + 0.07, Paint()..color = _ink);
  }
  for (final (dx, dy, r) in lobes) {
    c.drawCircle(p + Offset(dx, dy) * s, r * s, Paint()..color = base);
  }
  for (final (dx, dy, r) in lobes) {
    c.drawCircle(p + Offset(dx - 0.12, dy - 0.14) * s, r * s * 0.62, Paint()..color = mid);
  }
  for (final (dx, dy, r) in lobes.take(4)) {
    c.drawCircle(p + Offset(dx - 0.22, dy - 0.26) * s, r * s * 0.22, Paint()..color = hi);
  }
}

void _mushroom(Canvas c, Offset p, double s) {
  final stem = Rect.fromCenter(center: p.translate(0, s * 0.25), width: s * 0.45, height: s * 0.6);
  c.drawRRect(RRect.fromRectAndRadius(stem.inflate(0.05), Radius.circular(s * 0.2)), Paint()..color = _ink);
  c.drawRRect(RRect.fromRectAndRadius(stem, Radius.circular(s * 0.2)), Paint()..color = const Color(0xFFF3E3C1));
  final cap = Rect.fromCenter(center: p, width: s * 1.5, height: s * 1.0);
  c.drawOval(cap.inflate(0.06), Paint()..color = _ink);
  c.drawOval(cap, Paint()..color = const Color(0xFFEA8A32));
  for (final d in [Offset(-0.3, -0.1), Offset(0.15, -0.22), Offset(0.35, 0.05)]) {
    c.drawCircle(p + d * s, s * 0.11, Paint()..color = const Color(0xFFFFF1D4));
  }
}

void _pine(Canvas c, Offset p, double s, {bool snow = true}) {
  final layers = [(0.0, 1.0), (-0.45, 0.78), (-0.85, 0.56)];
  c.drawRect(Rect.fromCenter(center: p.translate(0, s * 0.55), width: s * 0.22, height: s * 0.4),
      Paint()..color = const Color(0xFF6B4423));
  for (final (dy, w) in layers) {
    final path = Path()
      ..moveTo(p.dx, p.dy + (dy - 0.55) * s)
      ..lineTo(p.dx + w * s * 0.55, p.dy + (dy + 0.4) * s)
      ..lineTo(p.dx - w * s * 0.55, p.dy + (dy + 0.4) * s)
      ..close();
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.14
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
    c.drawPath(path, Paint()..color = const Color(0xFF2F7A3E));
    c.drawPath(
      Path()
        ..moveTo(p.dx, p.dy + (dy - 0.55) * s)
        ..lineTo(p.dx - w * s * 0.55, p.dy + (dy + 0.4) * s)
        ..lineTo(p.dx - w * s * 0.1, p.dy + (dy + 0.4) * s)
        ..close(),
      Paint()..color = const Color(0xFF58B766).withValues(alpha: 0.6),
    );
    if (snow) {
      c.drawPath(
        Path()
          ..moveTo(p.dx, p.dy + (dy - 0.55) * s)
          ..lineTo(p.dx + w * s * 0.28, p.dy + (dy - 0.12) * s)
          ..lineTo(p.dx - w * s * 0.28, p.dy + (dy - 0.12) * s)
          ..close(),
        Paint()..color = Colors.white,
      );
    }
  }
}

void _rock(Canvas c, Offset p, double s, Color body, Color top) {
  final shape = Rect.fromCenter(center: p, width: s * 2.0, height: s * 1.35);
  c.drawOval(shape.inflate(0.06), Paint()..color = _ink);
  c.drawOval(shape, Paint()..color = body);
  c.drawOval(
    Rect.fromCenter(center: p.translate(-s * 0.1, -s * 0.3), width: s * 1.5, height: s * 0.7),
    Paint()..color = top,
  );
}

void _crystal(Canvas c, Offset p, double s, Color body, Color facet) {
  final path = Path()
    ..moveTo(p.dx, p.dy - s * 1.1)
    ..lineTo(p.dx + s * 0.45, p.dy - s * 0.1)
    ..lineTo(p.dx + s * 0.25, p.dy + s * 0.55)
    ..lineTo(p.dx - s * 0.3, p.dy + s * 0.55)
    ..lineTo(p.dx - s * 0.5, p.dy - s * 0.15)
    ..close();
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.13
      ..strokeJoin = StrokeJoin.round
      ..color = _ink,
  );
  c.drawPath(path, Paint()..color = body);
  c.drawPath(
    Path()
      ..moveTo(p.dx, p.dy - s * 1.1)
      ..lineTo(p.dx - s * 0.5, p.dy - s * 0.15)
      ..lineTo(p.dx - s * 0.3, p.dy + s * 0.55)
      ..lineTo(p.dx - s * 0.02, p.dy + s * 0.05)
      ..close(),
    Paint()..color = facet.withValues(alpha: 0.7),
  );
}

void _roof(Canvas c, Offset p, double w, double h, double angle, Color roof) {
  c.save();
  c.translate(p.dx, p.dy);
  c.rotate(angle);
  final r = Rect.fromCenter(center: Offset.zero, width: w, height: h);
  c.drawRect(r.shift(const Offset(0.12, 0.18)), Paint()..color = Colors.black.withValues(alpha: 0.3));
  c.drawRect(r.inflate(0.07), Paint()..color = _ink);
  c.drawRect(r, Paint()..color = roof);
  c.drawRect(
    Rect.fromLTWH(r.left, r.top, w, h / 2),
    Paint()..color = Colors.white.withValues(alpha: 0.12),
  );
  final tile = Paint()
    ..color = Colors.black.withValues(alpha: 0.22)
    ..strokeWidth = 0.035;
  for (var y = r.top + 0.22; y < r.bottom; y += 0.22) {
    c.drawLine(Offset(r.left, y), Offset(r.right, y), tile);
  }
  c.drawLine(Offset(r.left, 0), Offset(r.right, 0),
      Paint()..color = _ink.withValues(alpha: 0.7)..strokeWidth = 0.07);
  c.restore();
}

void _scenery(Canvas c, WorldTheme t, Random rnd, double R) {
  switch (t.scenery) {
    case Scenery.trees:
      for (var i = 0; i < 80; i++) {
        final p = _spot(rnd, R);
        final s = 0.55 + rnd.nextDouble() * 0.6;
        if (i % 9 == 0) {
          _mushroom(c, p, 0.5 + rnd.nextDouble() * 0.3);
        } else {
          c.drawCircle(p + Offset(s * 0.3, s * 0.9), s * 1.2,
              Paint()..color = Colors.black.withValues(alpha: 0.2));
          _bush(c, p, s, const Color(0xFF3F8F2C), const Color(0xFF63B83A), const Color(0xFFB4F070));
        }
      }
    case Scenery.swamp:
      // Wet marshy ground: dark mud, small puddles with lily pads, reeds,
      // grass tufts and mossy rocks. Solid land all around the maze.
      for (var i = 0; i < 60; i++) {
        final p = _spot(rnd, R);
        c.drawOval(
          Rect.fromCenter(center: p, width: 0.8 + rnd.nextDouble() * 1.8, height: 0.5 + rnd.nextDouble() * 0.9),
          Paint()..color = const Color(0xFF4F4128).withValues(alpha: 0.45),
        );
      }
      for (var i = 0; i < 30; i++) {
        final p = _spot(rnd, R);
        final w = 0.9 + rnd.nextDouble() * 1.3;
        final puddle = Rect.fromCenter(center: p, width: w, height: w * 0.58);
        c.drawOval(puddle.inflate(0.07), Paint()..color = _ink);
        c.drawOval(puddle, Paint()..color = const Color(0xFF47AFBB));
        c.drawOval(
          Rect.fromCenter(center: p.translate(-w * 0.12, -w * 0.1), width: w * 0.55, height: w * 0.22),
          Paint()..color = Colors.white.withValues(alpha: 0.35),
        );
        if (i % 3 == 0) {
          final pad = p.translate(w * 0.12, w * 0.04);
          c.drawCircle(pad, w * 0.16 + 0.05, Paint()..color = _ink);
          c.drawCircle(pad, w * 0.16, Paint()..color = const Color(0xFF58B03A));
          c.drawCircle(pad.translate(-w * 0.03, -w * 0.03), w * 0.07, Paint()..color = const Color(0xFFF48FB1));
        }
      }
      for (var i = 0; i < 55; i++) {
        // Tufts of grass.
        final p = _spot(rnd, R);
        for (var k = -1; k <= 1; k++) {
          c.drawLine(
            p + Offset(k * 0.08, 0.12),
            p + Offset(k * 0.16, -0.18 - rnd.nextDouble() * 0.12),
            Paint()..color = const Color(0xFF5FA83A)..strokeWidth = 0.06..strokeCap = StrokeCap.round,
          );
        }
      }
      for (var i = 0; i < 40; i++) {
        final p = _spot(rnd, R);
        for (var k = -1; k <= 1; k++) {
          final top = p + Offset(k * 0.18, -0.9 - rnd.nextDouble() * 0.4);
          c.drawLine(p + Offset(k * 0.1, 0.2), top,
              Paint()..color = const Color(0xFF3E8F2A)..strokeWidth = 0.07..strokeCap = StrokeCap.round);
          c.drawOval(Rect.fromCenter(center: top.translate(0, 0.12), width: 0.15, height: 0.4),
              Paint()..color = const Color(0xFF7A4A24));
        }
      }
      for (var i = 0; i < 28; i++) {
        _rock(c, _spot(rnd, R), 0.45 + rnd.nextDouble() * 0.4, const Color(0xFF8A9690), const Color(0xFF7FCB45));
      }
    case Scenery.snowPines:
      for (var i = 0; i < 40; i++) {
        final p = _spot(rnd, R);
        final s = 0.5 + rnd.nextDouble() * 0.9;
        for (final d in [const Offset(-0.5, 0.1), Offset.zero, const Offset(0.55, 0.15), const Offset(0.1, -0.35)]) {
          c.drawCircle(p + d * s, s * 0.55, Paint()..color = Colors.white.withValues(alpha: 0.92));
        }
      }
      for (var i = 0; i < 34; i++) {
        _rock(c, _spot(rnd, R), 0.5 + rnd.nextDouble() * 0.5, const Color(0xFF8B9391), Colors.white);
      }
      for (var i = 0; i < 55; i++) {
        _pine(c, _spot(rnd, R), 0.8 + rnd.nextDouble() * 0.6);
      }
    case Scenery.crystals:
      for (var i = 0; i < 30; i++) {
        final p = _spot(rnd, R);
        c.drawCircle(
          p,
          1.4,
          Paint()
            ..shader = ui.Gradient.radial(p, 1.4, [
              const Color(0xFFFF9A30).withValues(alpha: 0.28),
              const Color(0xFFFF9A30).withValues(alpha: 0),
            ]),
        );
      }
      for (var i = 0; i < 40; i++) {
        _rock(c, _spot(rnd, R), 0.5 + rnd.nextDouble() * 0.5, const Color(0xFF4A4650), const Color(0xFF66626F));
      }
      for (var i = 0; i < 50; i++) {
        final p = _spot(rnd, R);
        final purple = rnd.nextBool();
        for (var k = 0; k < 3; k++) {
          _crystal(
            c,
            p + Offset((k - 1) * 0.45, k == 1 ? -0.15 : 0.1),
            0.35 + rnd.nextDouble() * 0.3 + (k == 1 ? 0.15 : 0),
            purple ? const Color(0xFF9B5BE6) : const Color(0xFF5BC8E8),
            Colors.white,
          );
        }
      }
    case Scenery.houses:
      for (var i = 0; i < 60; i++) {
        final p = _spot(rnd, R);
        _bush(c, p, 0.4 + rnd.nextDouble() * 0.4, const Color(0xFF3F8F2C), const Color(0xFF63B83A), const Color(0xFFB4F070));
      }
      for (var i = 0; i < 26; i++) {
        final p = _spot(rnd, R, inner: 2.2);
        final blue = i % 5 == 0;
        _roof(
          c,
          p,
          1.5 + rnd.nextDouble() * 1.0,
          1.2 + rnd.nextDouble() * 0.7,
          (rnd.nextInt(4)) * pi / 2 + (rnd.nextDouble() - 0.5) * 0.15,
          blue ? const Color(0xFF3F63B0) : const Color(0xFFC8553D),
        );
      }
      for (var i = 0; i < 6; i++) {
        // Market stalls with striped awnings.
        final p = _spot(rnd, R, inner: 2.2, span: 6);
        final r = Rect.fromCenter(center: p, width: 1.4, height: 0.9);
        c.drawRect(r.inflate(0.07), Paint()..color = _ink);
        for (var k = 0; k < 7; k++) {
          c.drawRect(
            Rect.fromLTWH(r.left + k * r.width / 7, r.top, r.width / 7, r.height),
            Paint()..color = k.isEven ? const Color(0xFFD9503C) : const Color(0xFFFBF1D2),
          );
        }
      }
  }
}
