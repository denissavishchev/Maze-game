import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/polar_maze.dart';
import '../game/world.dart';
import 'balls.dart';
import 'maze_art.dart';
import 'palette.dart';
import 'worlds.dart';

/// Visible width of the maze on screen, in maze units.
const double kViewUnits = 9;

/// Caches the static picture and the gate paths of one maze.
class MazeRender {
  MazeRender(this.maze, this.theme)
      : picture = buildMazePicture(maze, theme, maze.cellCount * 31 + maze.entrance),
        walls = maze.wallPath(),
        gates = [for (var j = 0; j < maze.gateCount; j++) maze.gatePath(j)];

  final PolarMaze maze;
  final WorldTheme theme;
  final ui.Picture picture;
  final Path walls;
  final List<Path> gates;

  Path _fog = Path();
  int _fogCount = -1;

  /// The explored part of the maze as one shape, rebuilt only when the ball
  /// uncovers new cells. Each cell is slightly enlarged so its walls show.
  Path fogFor(GameController game) {
    if (_fogCount == game.exploredCount) return _fog;
    _fogCount = game.exploredCount;
    final path = Path();
    for (var c = 0; c < maze.cellCount; c++) {
      if (!game.explored[c]) continue;
      final r = maze.ringOfCell[c];
      if (r == 0) {
        path.addOval(Rect.fromCircle(center: Offset.zero, radius: 1.15));
        continue;
      }
      final n = maze.sectors[r];
      final a0 = maze.sectorOf(c) * kTwoPi / n;
      final a1 = a0 + kTwoPi / n;
      final pad = 0.18 / (r + 0.5);
      final inner = r - 0.18;
      final outer = r + 1.18;
      path
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: outer), a0 - pad,
            a1 - a0 + 2 * pad, true)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: inner), a1 + pad,
            -(a1 - a0 + 2 * pad), false)
        ..close();
    }
    return _fog = path;
  }
}

double _clock() => DateTime.now().millisecondsSinceEpoch / 1000.0;

class GamePainter extends CustomPainter {
  GamePainter(this.game, this.render) : super(repaint: game);

  final GameController game;
  final MazeRender render;

  WorldTheme get theme => render.theme;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / kViewUnits;
    final t = _clock();

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.translate(-game.camera.dx, -game.camera.dy);

    canvas.drawPicture(render.picture);
    for (final m in game.mud) {
      _mud(canvas, m, t);
    }
    _goal(canvas, t);
    for (var j = 0; j < game.maze.gateCount; j++) {
      _button(canvas, j);
    }
    for (var i = 0; i < game.bonusCells.length; i++) {
      if (!game.bonusTaken[i]) _bonus(canvas, game.maze.cellCenter(game.bonusCells[i]), t);
    }
    for (var j = 0; j < game.maze.gateCount; j++) {
      _gate(canvas, j);
    }
    for (final h in game.hazards) {
      _hazard(canvas, h, t);
    }
    for (final c in game.creatures) {
      if (game.config.world == WorldKind.forest) {
        c.asleep ? _sleepingWolf(canvas, c, t) : _wolf(canvas, c);
      } else {
        _drone(canvas, c, t);
      }
    }
    if (game.config.world == WorldKind.forest ||
        game.config.world == WorldKind.city) {
      _noiseRing(canvas);
    }
    if (game.bonusLeft > 0) _aura(canvas, t);
    _ball(canvas);
    for (final b in game.bursts) {
      _burst(canvas, b);
    }
    _hint(canvas, t);
    canvas.restore();

    _wind(canvas, size, t);

    if (theme.dark) {
      // Only the surroundings of the ball are lit.
      final center = size.center(Offset.zero);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            s * game.config.lightRadius * game.lightFactor,
            [Colors.transparent, Colors.black.withValues(alpha: 0.7), const Color(0xFA000000)],
            [0.3, 0.62, 1],
          ),
      );
    }
  }

  /// Streaks flying across the screen with the wind: faint while it is only a
  /// warning, bold while it blows.
  void _wind(Canvas c, Size size, double t) {
    final active = game.windLeft > 0;
    if (!active && game.windWarnLeft <= 0) return;
    final dir = game.windDir;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: active ? 0.5 : 0.2)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final len = active ? 80.0 : 40.0;
    for (var i = 0; i < 22; i++) {
      final seed = (i + 1) * 0.6180339;
      final phase = (t * (active ? 1.3 : 0.25) + seed) % 1.0;
      final base = Offset(
        ((seed * 7.13) % 1.0) * size.width,
        ((seed * 3.77) % 1.0) * size.height,
      );
      final p = base + dir * ((phase - 0.5) * size.width * 1.3);
      c.drawLine(p, p + dir * len, paint);
    }
  }

  // ---- floor items ------------------------------------------------------

  void _mud(Canvas c, MudPatch m, double t) {
    c.drawCircle(m.pos, m.radius, Paint()..color = const Color(0xFF3B2A18));
    c.drawCircle(m.pos.translate(-0.05, -0.05), m.radius * 0.75,
        Paint()..color = const Color(0xFF5A4228));
    // Slow ripples running towards the middle: it is a bog that pulls.
    for (var i = 0; i < 2; i++) {
      final k = (t * 0.5 + i * 0.5) % 1.0;
      c.drawCircle(
        m.pos,
        m.radius * (1 - k * 0.8),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.03
          ..color = const Color(0xFF8A6A44).withValues(alpha: 0.6 * (1 - k)),
      );
    }
    c.drawCircle(m.pos.translate(-0.12, -0.12), m.radius * 0.2,
        Paint()..color = Colors.white.withValues(alpha: 0.15));
  }

  void _goal(Canvas c, double t) {
    final pulse = 0.5 + 0.5 * sin(t * 2.5);
    c.drawCircle(
      Offset.zero,
      0.95,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 0.95, [
          Palette.gold.withValues(alpha: 0.55 + 0.2 * pulse),
          Palette.gold.withValues(alpha: 0),
        ]),
    );
    c.drawCircle(Offset.zero, 0.42, Paint()..color = const Color(0xFFB8860B));
    c.drawCircle(Offset.zero, 0.36, Paint()..color = Palette.gold);
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? 0.26 : 0.11;
      final a = -pi / 2 + i * pi / 5;
      final p = Offset(r * cos(a), r * sin(a));
      i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
    }
    c.drawPath(star..close(), Paint()..color = Colors.white);
  }

  /// Floor switch styled after the world: a carved wooden plate with a leaf
  /// in the forest, a riveted rusty plate in the mud, a stone slab with an ice
  /// crystal in the mountains, a glowing rune in the caves and a hazard-striped
  /// metal pad in the city.
  void _button(Canvas c, int j) {
    final p = game.maze.cellCenter(game.maze.buttonCells[j]);
    final used = game.buttonUsed[j];
    final t = _clock();
    final r = used ? 0.3 : 0.34;
    Color dim(Color col) => used ? Color.lerp(col, Colors.black, 0.4)! : col;
    void disc(double rad, Color a, Color b, {Offset at = Offset.zero}) {
      final o = p + at;
      c.drawCircle(
        o,
        rad,
        Paint()
          ..shader = ui.Gradient.radial(
            o.translate(-rad * 0.3, -rad * 0.3),
            rad * 1.5,
            [dim(a), dim(b)],
          ),
      );
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.035
      ..color = Colors.black.withValues(alpha: 0.35);
    c.drawCircle(p.translate(0.03, 0.07), r + 0.03,
        Paint()..color = Colors.black.withValues(alpha: 0.38));

    switch (game.config.world) {
      case WorldKind.forest:
        disc(r + 0.03, const Color(0xFF6B4423), const Color(0xFF4A2D14));
        disc(r - 0.03, const Color(0xFFB07A44), const Color(0xFF8B5A2B));
        for (final rad in [0.18, 0.11]) {
          c.drawCircle(p, rad, ring);
        }
        // A leaf: two arcs meeting at the tips, with a midrib.
        final leaf = Path()
          ..moveTo(p.dx - 0.13, p.dy + 0.08)
          ..quadraticBezierTo(p.dx - 0.02, p.dy - 0.2, p.dx + 0.14, p.dy - 0.1)
          ..quadraticBezierTo(p.dx + 0.1, p.dy + 0.12, p.dx - 0.13, p.dy + 0.08)
          ..close();
        c.drawPath(leaf, Paint()..color = dim(const Color(0xFF5FB34A)));
        c.drawLine(p.translate(-0.12, 0.08), p.translate(0.1, -0.07),
            Paint()..color = dim(const Color(0xFF2E6B26))..strokeWidth = 0.025);
      case WorldKind.mud:
        disc(r + 0.03, const Color(0xFF2F3439), const Color(0xFF1C2024));
        disc(r - 0.03, const Color(0xFFA0623A), const Color(0xFF6B3F22));
        for (var i = 0; i < 4; i++) {
          final rp = p + polar(0.22, i * pi / 2 + pi / 4);
          c.drawCircle(rp, 0.035, Paint()..color = dim(const Color(0xFF3A3F45)));
          c.drawCircle(rp.translate(-0.01, -0.01), 0.012,
              Paint()..color = Colors.white.withValues(alpha: 0.4));
        }
        disc(0.1, const Color(0xFF8A8F96), const Color(0xFF4C5056));
      case WorldKind.mountains:
        disc(r + 0.03, const Color(0xFF3E4855), const Color(0xFF2B323C));
        disc(r - 0.03, const Color(0xFFDCE4EC), const Color(0xFF9AA6B3));
        final crystal = Path()
          ..moveTo(p.dx, p.dy - 0.17)
          ..lineTo(p.dx + 0.1, p.dy)
          ..lineTo(p.dx, p.dy + 0.17)
          ..lineTo(p.dx - 0.1, p.dy)
          ..close();
        c.drawPath(crystal, Paint()..color = dim(const Color(0xFF7FD0F2)));
        c.drawLine(p.translate(0, -0.17), p.translate(0, 0.17),
            Paint()..color = Colors.white.withValues(alpha: 0.55)..strokeWidth = 0.02);
      case WorldKind.underground:
        final glow = used ? 0.0 : 0.5 + 0.5 * sin(t * 3 + j);
        c.drawCircle(
          p,
          r + 0.3,
          Paint()
            ..shader = ui.Gradient.radial(p, r + 0.3, [
              const Color(0xFF3FD6C0).withValues(alpha: 0.35 * glow),
              const Color(0xFF3FD6C0).withValues(alpha: 0),
            ]),
        );
        disc(r + 0.03, const Color(0xFF191222), const Color(0xFF0E0A16));
        disc(r - 0.03, const Color(0xFF4A3D66), const Color(0xFF2B2140));
        // Carved rune: ring with three spokes, glowing teal.
        final rune = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.04
          ..strokeCap = StrokeCap.round
          ..color = (used ? const Color(0xFF3A3050) : const Color(0xFF3FD6C0));
        c.drawCircle(p, 0.15, rune);
        for (var i = 0; i < 3; i++) {
          c.drawLine(p, p + polar(0.15, i * 2 * pi / 3 - pi / 2), rune);
        }
      case WorldKind.city:
        disc(r + 0.03, const Color(0xFF2B2F36), const Color(0xFF1C1F24));
        // Hazard stripes around the pad.
        for (var i = 0; i < 12; i++) {
          c.drawArc(
            Rect.fromCircle(center: p, radius: r - 0.03),
            i * pi / 6,
            pi / 6,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.07
              ..color = dim(i.isEven ? const Color(0xFFFFC107) : const Color(0xFF22252B)),
          );
        }
        disc(r - 0.1, const Color(0xFF5C636D), const Color(0xFF3A3F47));
        // Status LED: red until pressed, then green.
        c.drawCircle(
          p,
          0.07,
          Paint()..color = used ? const Color(0xFF3DDC84) : Color.lerp(const Color(0xFFB71C1C), Colors.redAccent, 0.5 + 0.5 * sin(t * 5))!,
        );
    }
    c.drawCircle(p, r + 0.03, ring);
  }

  /// Bonus pickup: a pulsing golden orb with a symbol for what it does.
  void _bonus(Canvas c, Offset p, double t) {
    final pulse = 0.5 + 0.5 * sin(t * 3 + p.dx);
    c.drawCircle(
      p,
      0.7,
      Paint()
        ..shader = ui.Gradient.radial(p, 0.7, [
          const Color(0xFF7DF9FF).withValues(alpha: 0.35 + 0.25 * pulse),
          const Color(0xFF7DF9FF).withValues(alpha: 0),
        ]),
    );
    c.drawCircle(p.translate(0.03, 0.06), 0.3, Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.drawCircle(p, 0.3, Paint()..color = const Color(0xFF1E2A3A));
    c.drawCircle(
      p,
      0.3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05
        ..color = Color.lerp(Palette.gold, Colors.white, pulse * 0.5)!,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.045
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    switch (game.config.world) {
      case WorldKind.forest:
        // Crescent moon: the wolf goes to sleep.
        c.drawCircle(p.translate(-0.02, 0), 0.13, Paint()..color = Palette.gold);
        c.drawCircle(p.translate(0.05, -0.03), 0.12, Paint()..color = const Color(0xFF1E2A3A));
      case WorldKind.mud:
        // Spike with a slash: traps off.
        c.drawPath(
          Path()
            ..moveTo(p.dx - 0.1, p.dy + 0.12)
            ..lineTo(p.dx, p.dy - 0.14)
            ..lineTo(p.dx + 0.1, p.dy + 0.12)
            ..close(),
          Paint()..color = const Color(0xFFD5DCE0),
        );
        c.drawLine(p.translate(-0.15, 0.15), p.translate(0.15, -0.15),
            Paint()..color = Colors.redAccent..strokeWidth = 0.05..strokeCap = StrokeCap.round);
      case WorldKind.mountains:
        // Boulder with a slash.
        c.drawCircle(p, 0.13, Paint()..color = const Color(0xFF9AA3AD));
        c.drawLine(p.translate(-0.15, 0.15), p.translate(0.15, -0.15),
            Paint()..color = Colors.redAccent..strokeWidth = 0.05..strokeCap = StrokeCap.round);
      case WorldKind.underground:
        // Sun: more light.
        c.drawCircle(p, 0.09, Paint()..color = Palette.gold);
        for (var i = 0; i < 8; i++) {
          c.drawLine(p + polar(0.13, i * pi / 4), p + polar(0.19, i * pi / 4), line..color = Palette.gold);
        }
      case WorldKind.city:
        // Power symbol: drones off.
        c.drawArc(Rect.fromCircle(center: p, radius: 0.13), -pi / 2 + 0.6, 2 * pi - 1.2, false, line);
        c.drawLine(p.translate(0, -0.15), p.translate(0, -0.02), line);
    }
  }

  /// How far the ball can be heard right now, green when quiet, red when loud.
  void _noiseRing(Canvas c) {
    final r = game.hearingRadius;
    if (r <= 0) return;
    final n = game.noiseLevel;
    final color = Color.lerp(Colors.lightGreenAccent, Colors.redAccent, n)!;
    c.drawCircle(game.pos, r, Paint()..color = color.withValues(alpha: 0.05 + 0.07 * n));
    c.drawCircle(
      game.pos,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.05
        ..color = color.withValues(alpha: 0.25 + 0.4 * n),
    );
  }

  /// Ring around the ball while a bonus is running, shrinking as it runs out.
  void _aura(Canvas c, double t) {
    final k = game.bonusLeft / GameController.bonusDuration;
    c.drawCircle(
      game.pos,
      0.5 + 0.04 * sin(t * 8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..color = const Color(0xFF7DF9FF).withValues(alpha: 0.35 + 0.5 * k),
    );
  }

  void _gate(Canvas c, int j) {
    final a = game.gateAnim[j];
    if (a >= 1) return;
    final path = render.gates[j];
    final fade = 1 - a;
    final w = 0.3 * (1 - 0.6 * a);
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = color.withValues(alpha: color.a * fade);
    c.drawPath(path.shift(const Offset(0.05, 0.08)),
        stroke(Colors.black.withValues(alpha: 0.35), w + 0.04));
    c.drawPath(path, stroke(const Color(0xFF2B2118), w + 0.04));
    c.drawPath(path, stroke(theme.gate, w));
    // Bars across the gate so it reads as a barrier, not a hedge.
    final bar = stroke(Colors.black.withValues(alpha: 0.55), 0.035);
    for (final metric in path.computeMetrics()) {
      for (var d = 0.05; d < metric.length; d += 0.17) {
        final tan = metric.getTangentForOffset(d);
        if (tan == null) continue;
        final n = Offset(-tan.vector.dy, tan.vector.dx) * (w * 0.45);
        c.drawLine(tan.position - n, tan.position + n, bar);
      }
    }
  }

  // ---- hazards ----------------------------------------------------------

  void _hazard(Canvas c, Hazard h, double t) {
    final mountains = game.config.world == WorldKind.mountains;
    final fadeOut = ((h.life - h.age) / 0.6).clamp(0.0, 1.0);
    if (mountains) {
      if (!h.armed) {
        final k = (h.age / h.armAt).clamp(0.0, 1.0);
        final pulse = 0.5 + 0.5 * sin(t * 14);
        c.drawCircle(h.pos, h.radius,
            Paint()..color = Colors.redAccent.withValues(alpha: 0.15 + 0.2 * k * pulse));
        c.drawCircle(
          h.pos,
          h.radius * (1.0 - 0.5 * k),
          Paint()
            ..color = Colors.redAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.06,
        );
      } else {
        c.drawCircle(h.pos.translate(0.06, 0.1), 0.42,
            Paint()..color = Colors.black.withValues(alpha: 0.35 * fadeOut));
        c.drawCircle(h.pos, 0.42, Paint()..color = const Color(0xFF6E7378).withValues(alpha: fadeOut));
        c.drawCircle(h.pos.translate(-0.1, -0.1), 0.2,
            Paint()..color = const Color(0xFFA2A7AC).withValues(alpha: fadeOut));
      }
      return;
    }
    // Spikes pop out of the ground.
    final k = (h.age / h.armAt).clamp(0.0, 1.0);
    c.drawCircle(h.pos, 0.34 * k, Paint()..color = const Color(0xFF140C06).withValues(alpha: fadeOut));
    if (h.armed) {
      final spike = Paint()..color = const Color(0xFFD5DCE0).withValues(alpha: fadeOut);
      for (var i = 0; i < 7; i++) {
        final a = i * 2 * pi / 7;
        final base = h.pos + polar(0.17, a);
        c.drawPath(
          Path()
            ..moveTo(base.dx + 0.05 * cos(a + pi / 2), base.dy + 0.05 * sin(a + pi / 2))
            ..lineTo(base.dx - 0.05 * cos(a + pi / 2), base.dy - 0.05 * sin(a + pi / 2))
            ..lineTo(base.dx + 0.05 * cos(a), base.dy + 0.05 * sin(a) - 0.2)
            ..close(),
          spike,
        );
      }
      c.drawCircle(h.pos.translate(0, -0.2), 0.06, spike);
    } else {
      c.drawCircle(
        h.pos,
        0.34,
        Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.04,
      );
    }
  }

  void _wolf(Canvas c, Creature w) {
    c.save();
    c.translate(w.pos.dx, w.pos.dy);
    c.drawOval(Rect.fromCenter(center: const Offset(0.05, 0.12), width: 0.9, height: 0.5),
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.rotate(w.angle);
    final fur = Paint()..color = const Color(0xFF8A8F98);
    final dark = Paint()..color = const Color(0xFF555A64);
    // Tail, body, head, ears.
    c.drawOval(Rect.fromCenter(center: const Offset(-0.42, 0), width: 0.4, height: 0.14), dark);
    c.drawOval(Rect.fromCenter(center: const Offset(-0.05, 0), width: 0.7, height: 0.4), fur);
    c.drawCircle(const Offset(0.35, 0), 0.19, fur);
    c.drawOval(Rect.fromCenter(center: const Offset(0.52, 0), width: 0.22, height: 0.16),
        Paint()..color = const Color(0xFFCDD1D7));
    c.drawCircle(const Offset(0.6, 0), 0.035, Paint()..color = Colors.black);
    c.drawCircle(const Offset(0.36, -0.1), 0.07, dark);
    c.drawCircle(const Offset(0.36, 0.1), 0.07, dark);
    c.drawCircle(const Offset(0.44, -0.07), 0.03, Paint()..color = const Color(0xFFFF3D00));
    c.drawCircle(const Offset(0.44, 0.07), 0.03, Paint()..color = const Color(0xFFFF3D00));
    c.restore();
  }

  void _sleepingWolf(Canvas c, Creature w, double t) {
    final p = w.pos;
    c.drawOval(Rect.fromCenter(center: p.translate(0.05, 0.12), width: 0.8, height: 0.55),
        Paint()..color = Colors.black.withValues(alpha: 0.3));
    // Curled up: body ring, head tucked in, tail around.
    c.drawCircle(p, 0.3, Paint()..color = const Color(0xFF7C818B));
    c.drawCircle(p.translate(-0.05, 0.03), 0.2, Paint()..color = const Color(0xFF8A8F98));
    c.drawCircle(p.translate(0.14, -0.1), 0.13, Paint()..color = const Color(0xFF8A8F98));
    c.drawCircle(p.translate(0.17, -0.15), 0.035, Paint()..color = const Color(0xFF555A64));
    c.drawLine(p.translate(0.1, -0.08), p.translate(0.2, -0.08),
        Paint()..color = Colors.black54..strokeWidth = 0.025);
    // Floating "z" letters.
    for (var i = 0; i < 3; i++) {
      final k = ((t * 0.7 + i / 3) % 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontSize: 0.22 + 0.12 * k,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 1 - k),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, p.translate(0.25 + k * 0.25, -0.3 - k * 0.6));
    }
  }

  void _drone(Canvas c, Creature d, double t) {
    final p = d.pos;
    if (d.asleep) {
      // Landed: rotors still, no light, little "z" letters.
      c.drawCircle(p.translate(0.04, 0.08), 0.3, Paint()..color = Colors.black.withValues(alpha: 0.3));
      for (var i = 0; i < 4; i++) {
        c.drawCircle(p + polar(0.26, i * pi / 2 + pi / 4), 0.12,
            Paint()..color = const Color(0xFF6A7280).withValues(alpha: 0.6));
      }
      c.drawCircle(p, 0.2, Paint()..color = const Color(0xFF2A2E35));
      c.drawCircle(p, 0.07, Paint()..color = const Color(0xFF4A2020));
      for (var i = 0; i < 3; i++) {
        final k = (t * 0.7 + i / 3) % 1.0;
        final tp = TextPainter(
          text: TextSpan(
            text: 'z',
            style: TextStyle(
              fontSize: 0.22 + 0.12 * k,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 1 - k),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, p.translate(0.25 + k * 0.25, -0.3 - k * 0.6));
      }
      return;
    }
    // The real view cone, turning red as the drone makes up its mind.
    final k = (d.alert / GameController.droneReaction).clamp(0.0, 1.0);
    final cone = Path()
      ..moveTo(p.dx, p.dy)
      ..arcTo(
        Rect.fromCircle(center: p, radius: GameController.droneRange),
        d.viewAngle - GameController.droneHalfAngle,
        GameController.droneHalfAngle * 2,
        false,
      )
      ..close();
    c.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.radial(
          p,
          GameController.droneRange,
          [
            Color.lerp(const Color(0xFFFFF59D), Colors.redAccent, k)!
                .withValues(alpha: 0.5),
            Color.lerp(const Color(0xFFFFF59D), Colors.redAccent, k)!
                .withValues(alpha: 0.08),
          ],
        ),
    );
    c.drawCircle(p.translate(0.05, 0.1), 0.32, Paint()..color = Colors.black.withValues(alpha: 0.3));
    final rotor = Paint()..color = const Color(0xFF8C96A5).withValues(alpha: 0.55);
    for (var i = 0; i < 4; i++) {
      final a = i * pi / 2 + pi / 4;
      final rp = p + polar(0.28, a);
      c.drawCircle(rp, 0.14, rotor);
      final spin = t * 25 + i;
      c.drawLine(rp + polar(0.14, spin), rp - polar(0.14, spin),
          Paint()..color = Colors.black54..strokeWidth = 0.03);
    }
    c.drawCircle(p, 0.2, Paint()..color = const Color(0xFF2F343D));
    c.drawCircle(p, 0.09,
        Paint()..color = Colors.redAccent.withValues(alpha: 0.6 + 0.4 * sin(t * 8)));
    if (d.searching && k <= 0.15) {
      final tp = TextPainter(
        text: const TextSpan(
          text: '?',
          style: TextStyle(fontSize: 0.6, fontWeight: FontWeight.w900, color: Colors.amberAccent),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, p.translate(-tp.width / 2, -0.95));
    }
    if (k > 0.15) {
      final tp = TextPainter(
        text: const TextSpan(
          text: '!',
          style: TextStyle(fontSize: 0.6, fontWeight: FontWeight.w900, color: Colors.redAccent),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, p.translate(-tp.width / 2, -0.95));
    }
  }

  // ---- ball and effects -------------------------------------------------

  void _ball(Canvas c) {
    final sink = game.sink;
    final p = game.pos.translate(0, sink * 0.08);
    final r = game.ballRadius * (1 - 0.4 * sink);
    c.drawOval(
      Rect.fromCenter(center: p.translate(0.06, 0.12), width: r * 2.2, height: r * 1.7),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );
    paintBall(c, p, r, game.config.ball, game.ballRot);
    if (sink > 0) {
      // Mud creeping over the ball.
      c.drawCircle(
        p,
        r,
        Paint()..color = const Color(0xFF4A3520).withValues(alpha: 0.75 * sink),
      );
    }
  }

  void _burst(Canvas c, Burst b) {
    final k = b.age / 0.9;
    final fade = (1 - k).clamp(0.0, 1.0);
    if (b.kind == 3) {
      // Sound of a hard bump spreading as far as sleeping wolves can hear.
      c.drawCircle(
        b.pos,
        GameController.noiseRadius * min(1.0, k * 1.4),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.08,
      );
      return;
    }
    final color = switch (b.kind) {
      0 => Colors.white,
      1 => Colors.redAccent,
      _ => Palette.gold,
    };
    c.drawCircle(
      b.pos,
      0.2 + k * (b.kind == 1 ? 1.4 : 1.0),
      Paint()
        ..color = color.withValues(alpha: fade)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.07,
    );
    final dot = Paint()..color = color.withValues(alpha: fade);
    for (var i = 0; i < 8; i++) {
      c.drawCircle(b.pos + polar(0.1 + k * 0.8, i * pi / 4 + 0.3), 0.045, dot);
    }
  }

  /// After a button: a pulsing arrow from the ball towards the gate it opened.
  void _hint(Canvas c, double t) {
    if (game.hintGate < 0) return;
    final target = game.maze.gateCenter(game.hintGate);
    final d = target - game.pos;
    if (d.distance < 1.2) return;
    final dir = d / d.distance;
    final tip = game.pos + dir * (0.95 + 0.1 * sin(t * 6));
    final side = Offset(-dir.dy, dir.dx);
    c.drawPath(
      Path()
        ..moveTo(tip.dx + dir.dx * 0.18, tip.dy + dir.dy * 0.18)
        ..lineTo(tip.dx + side.dx * 0.13, tip.dy + side.dy * 0.13)
        ..lineTo(tip.dx - side.dx * 0.13, tip.dy - side.dy * 0.13)
        ..close(),
      Paint()..color = Palette.gold.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(GamePainter old) => old.render != render;
}

/// Round overview of the maze with fog of war: only the parts the ball has
/// been near are drawn, everything else stays dark.
class MiniMapPainter extends CustomPainter {
  MiniMapPainter(this.game, this.render) : super(repaint: game);

  final GameController game;
  final MazeRender render;

  @override
  void paint(Canvas canvas, Size size) {
    final m = game.maze;
    final extent = m.radius + 0.6;
    final s = size.width / (2 * extent);
    final center = size.center(Offset.zero);

    // Unexplored: a dark disc.
    canvas.drawCircle(center, size.width / 2, Paint()..color = const Color(0xE6101418));
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    canvas.translate(center.dx, center.dy);
    canvas.scale(s);

    final fog = render.fogFor(game);
    canvas.drawPath(fog, Paint()..color = render.theme.floor.withValues(alpha: 0.92));
    canvas.save();
    canvas.clipPath(fog);
    canvas.drawPath(
      render.walls,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.2, 1.3 / s)
        ..color = render.theme.wallMain,
    );
    for (var j = 0; j < m.gateCount; j++) {
      if (game.gateOpen[j]) continue;
      canvas.drawPath(
        render.gates[j],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.25, 2.2 / s)
          ..color = render.theme.gate,
      );
    }
    canvas.restore();

    bool seen(int cell) => game.explored[cell];
    final dot = 3.2 / s;
    for (var j = 0; j < m.gateCount; j++) {
      if (game.buttonUsed[j] || !seen(m.buttonCells[j])) continue;
      canvas.drawCircle(m.cellCenter(m.buttonCells[j]), dot, Paint()..color = Palette.gold);
    }
    for (var i = 0; i < game.bonusCells.length; i++) {
      if (game.bonusTaken[i] || !seen(game.bonusCells[i])) continue;
      canvas.drawCircle(m.cellCenter(game.bonusCells[i]), dot,
          Paint()..color = const Color(0xFF7DF9FF));
    }
    // The goal is always known.
    canvas.drawCircle(Offset.zero, dot * 1.4, Paint()..color = Colors.white);
    canvas.drawCircle(Offset.zero, dot * 1.1, Paint()..color = Palette.gold);
    // Creatures only show while they are near the ball and in explored ground.
    for (final c in game.creatures) {
      if ((c.pos - game.pos).distance > 6 || !seen(m.cellAt(c.pos))) continue;
      canvas.drawCircle(
        c.pos,
        dot,
        Paint()..color = c.asleep ? Colors.blueGrey : Colors.redAccent,
      );
    }
    canvas.drawCircle(game.pos, dot * 1.2, Paint()..color = Colors.white);
    canvas.drawCircle(game.pos, dot * 0.8, Paint()..color = const Color(0xFFE53935));
    canvas.restore();
    canvas.drawCircle(
      center,
      size.width / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..color = Palette.ink,
    );
  }

  @override
  bool shouldRepaint(MiniMapPainter old) => old.render != render;
}
