import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/maze.dart';
import '../game/polar_maze.dart';
import '../game/rect_maze.dart';
import '../game/world.dart';
import 'balls.dart';
import 'maze_art.dart';
import 'palette.dart';
import 'worlds.dart';

/// Visible width of the maze on screen, in maze units.
const double kViewUnits = 9;

/// Floor items (buttons, bonuses) are drawn at this fraction of their full
/// size, so they fit between the walls of a corridor.
const double kItemScale = 0.68;

/// Caches the static picture and the gate paths of one maze.
class MazeRender {
  MazeRender(this.maze, this.theme)
      : picture = switch (maze) {
          final RectMaze r =>
            buildRectMazePicture(r, theme, r.cellCount * 31 + r.start),
          final PolarMaze p =>
            buildMazePicture(p, theme, p.cellCount * 31 + p.entrance),
          _ => throw ArgumentError('unknown maze ${maze.runtimeType}'),
        },
        walls = maze.wallPath(),
        gates = [for (var j = 0; j < maze.gateCount; j++) maze.gatePath(j)];

  final Maze maze;
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
    final maze = this.maze as PolarMaze; // only the round maze has a minimap
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
  GamePainter(this.game, this.render, {this.prevRender}) : super(repaint: game);

  final GameController game;
  final MazeRender render;

  /// Endless mode, while scrolling: the maze being left.
  final MazeRender? prevRender;

  WorldTheme get theme => render.theme;

  @override
  void paint(Canvas canvas, Size size) {
    final maze = game.maze;
    // The round maze scrolls with the ball; the rectangular one is shown whole.
    final s = maze is RectMaze
        ? min(size.width / (maze.cols + RectMaze.padX),
            size.height / (maze.rows + RectMaze.padTop + RectMaze.padBottom))
        : size.width / kViewUnits;
    final t = _clock();

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Where the maze's origin is on the screen. The rectangular maze sits
    // against the bottom, centred sideways; while scrolling it starts one maze
    // lower, so the maze being left slides up out of view.
    var origin = Offset(size.width / 2, size.height / 2) - game.camera * s;
    if (maze is RectMaze) {
      final e = Curves.easeInOut.transform(game.transition);
      origin = Offset(
        (size.width - maze.cols * s) / 2,
        size.height - (maze.rows + RectMaze.padBottom) * s + (1 - e) * maze.rows * s,
      );
    }
    // The shifting maze turns about the ball, which stays in the middle.
    if (game.spins) {
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(game.spinAngle);
      canvas.translate(-size.width / 2, -size.height / 2);
    }
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(s);

    final left = prevRender;
    if (maze is RectMaze && game.scrolling && left != null) {
      // The new maze below, the old one above it; each only in its own band.
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(-50, -0.3, 50, maze.rows + 3.0));
      canvas.drawPicture(render.picture);
      canvas.restore();
      final oldRows = (left.maze as RectMaze).rows;
      canvas.save();
      canvas.translate(0, -oldRows.toDouble());
      canvas.clipRect(Rect.fromLTRB(-50, -3, 50, oldRows.toDouble()));
      canvas.drawPicture(left.picture);
      canvas.restore();
    } else {
      canvas.drawPicture(render.picture);
    }
    for (final m in game.mud) {
      _mud(canvas, m, t);
    }
    for (final g in game.goos) {
      _goo(canvas, g, t);
    }
    for (final b in game.belts) {
      _belt(canvas, b, t);
    }
    for (final w in game.worms) {
      _worm(canvas, w, t);
    }
    for (final tt in game.turntables) {
      _turntable(canvas, tt, t);
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
    for (final a in game.airlocks) {
      _airlock(canvas, a, t);
    }
    for (final m in game.magnets) {
      _magnet(canvas, m, t);
    }
    for (final p in game.presses) {
      _press(canvas, p, t);
    }
    for (final p in game.pendulums) {
      _pendulum(canvas, p, t);
    }
    for (final d in game.doors) {
      _door(canvas, d, t);
    }
    for (final k in game.cracks) {
      _crack(canvas, k, t);
    }
    for (final k in game.crusts) {
      _crust(canvas, k, t);
    }
    for (final g in game.geysers) {
      _geyser(canvas, g, t);
    }
    for (final l in game.lavas) {
      _lava(canvas, l, t);
    }
    for (final j in game.jellies) {
      switch (game.config.world) {
        case WorldKind.candy:
          _gummy(canvas, j, t);
        default:
          _jelly(canvas, j, t);
      }
    }
    for (final l in game.lasers) {
      _laser(canvas, l, t);
    }
    for (final cam in game.cameras) {
      _camera(canvas, cam, t);
    }
    for (final h in game.hazards) {
      _hazard(canvas, h, t);
    }
    for (final f in game.fog) {
      _fog(canvas, f, t);
    }
    for (final c in game.creatures) {
      if (game.config.world == WorldKind.graveyard) {
        _ghost(canvas, c, t);
      } else if (game.config.world == WorldKind.forest) {
        c.asleep ? _sleepingWolf(canvas, c, t) : _wolf(canvas, c);
      } else {
        _drone(canvas, c, t);
      }
    }
    if (game.config.world == WorldKind.forest ||
        game.config.world == WorldKind.graveyard ||
        game.config.world == WorldKind.city) {
      _noiseRing(canvas);
    }
    if (game.bonusLeft > 0) _aura(canvas, t);
    _ball(canvas);
    for (final b in game.beams) {
      _beam(canvas, b, t);
    }
    for (final b in game.bursts) {
      _burst(canvas, b);
    }
    _hint(canvas, t);
    canvas.restore();

    _wind(canvas, size, t);

    if (theme.dark) {
      // Only the surroundings of the ball are lit.
      final center = maze is RectMaze
          ? origin + game.pos * s
          : size.center(Offset.zero);
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
      ..color = (game.config.world == WorldKind.ocean ? const Color(0xFF9FF0FF) : Colors.white)
          .withValues(alpha: active ? 0.5 : 0.2)
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
    final m = game.maze;
    if (m is RectMaze) {
      _exitMarker(c, t, Offset(m.goalCol + 0.5, m.rows.toDouble()));
      return;
    }
    final at = m.cellCenter(m.goal);
    c.save();
    c.translate(at.dx, at.dy);
    _goalMarker(c, t);
    c.restore();
  }

  /// The exit in the bottom wall: a soft golden glow in the gap.
  void _exitMarker(Canvas c, double t, Offset gap) {
    final pulse = 0.5 + 0.5 * sin(t * 2.5);
    final glow = gap.translate(0, -0.35);
    c.drawCircle(
      glow,
      1.1,
      Paint()
        ..shader = ui.Gradient.radial(glow, 1.1, [
          Palette.gold.withValues(alpha: 0.5 + 0.2 * pulse),
          Palette.gold.withValues(alpha: 0),
        ]),
    );
  }

  void _goalMarker(Canvas c, double t) {
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
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(kItemScale);
    c.translate(-p.dx, -p.dy);
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
      case WorldKind.graveyard:
        // A stone slab with a cross, and a candle that burns until pressed.
        disc(r + 0.03, const Color(0xFF2A2F3A), const Color(0xFF171A21));
        disc(r - 0.03, const Color(0xFF9AA0AE), const Color(0xFF5E6472));
        final cross = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.06
          ..strokeCap = StrokeCap.round
          ..color = dim(const Color(0xFF3A3F4B));
        c.drawLine(p.translate(0, -0.17), p.translate(0, 0.17), cross);
        c.drawLine(p.translate(-0.11, -0.05), p.translate(0.11, -0.05), cross);
        if (!used) {
          final flick = 0.8 + 0.2 * sin(t * 9 + j);
          c.drawCircle(
            p.translate(0, -0.2),
            0.16 * flick,
            Paint()
              ..shader = ui.Gradient.radial(p.translate(0, -0.2), 0.16 * flick, [
                const Color(0xFFFFC857).withValues(alpha: 0.6),
                const Color(0xFFFFC857).withValues(alpha: 0),
              ]),
          );
          c.drawCircle(p.translate(0, -0.2), 0.045, Paint()..color = const Color(0xFFFFE9A8));
        }
      case WorldKind.ocean:
        // A scallop shell holding a pearl that glows until pressed.
        disc(r + 0.03, const Color(0xFF8A4A5A), const Color(0xFF4E2432));
        disc(r - 0.03, const Color(0xFFFFD6C4), const Color(0xFFE59A92));
        for (var i = -3; i <= 3; i++) {
          c.drawLine(p.translate(0, 0.17), p + polar(0.2, -pi / 2 + i * 0.4),
              Paint()..strokeWidth = 0.03..color = const Color(0xFFB8636C)..strokeCap = StrokeCap.round);
        }
        c.drawCircle(p, 0.09, Paint()..color = used ? const Color(0xFFB9B3BD) : Colors.white);
        c.drawCircle(p.translate(-0.03, -0.03), 0.03, Paint()..color = Colors.white.withValues(alpha: 0.9));
        if (!used) {
          c.drawCircle(p, 0.2, Paint()..shader = ui.Gradient.radial(p, 0.2, [
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0),
          ]));
        }
      case WorldKind.glass:
        // A glass pad with a small prism that glows until pressed.
        disc(r + 0.03, const Color(0xFF2B6F93), const Color(0xFF153A50));
        disc(r - 0.03, const Color(0xFFCFEFFF), const Color(0xFF6FB8D8));
        final prism = Path()
          ..moveTo(p.dx, p.dy - 0.17)
          ..lineTo(p.dx + 0.15, p.dy + 0.11)
          ..lineTo(p.dx - 0.15, p.dy + 0.11)
          ..close();
        c.drawPath(
          prism,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.05
            ..strokeJoin = StrokeJoin.round
            ..color = used ? const Color(0xFF7FA3B8) : Colors.white,
        );
        if (!used) {
          c.drawLine(p.translate(-0.2, -0.02), p.translate(-0.03, 0.0),
              Paint()..color = Colors.white..strokeWidth = 0.03..strokeCap = StrokeCap.round);
          for (var i = 0; i < 3; i++) {
            c.drawLine(
              p.translate(0.03, 0.0 + i * 0.03),
              p.translate(0.2, -0.04 + i * 0.07),
              Paint()
                ..color = [const Color(0xFFFF6B9D), const Color(0xFFFFE066), const Color(0xFF66E0FF)][i]
                ..strokeWidth = 0.03
                ..strokeCap = StrokeCap.round,
            );
          }
        }
      case WorldKind.factory:
        // A hazard-striped plate with a big red push button.
        disc(r + 0.03, const Color(0xFF2B2F36), const Color(0xFF15181C));
        disc(r - 0.03, const Color(0xFFE0A526), const Color(0xFF9A6E10));
        for (var i = 0; i < 8; i++) {
          final a = i * pi / 4;
          c.drawLine(p + polar(0.2, a), p + polar(0.3, a + 0.2),
              Paint()..color = dim(const Color(0xFF2B2F36))..strokeWidth = 0.05..strokeCap = StrokeCap.round);
        }
        disc(0.15, const Color(0xFF3A1010), const Color(0xFF1A0808));
        disc(used ? 0.11 : 0.13, const Color(0xFFFF6A5A), const Color(0xFFB02020));
        if (!used) {
          c.drawCircle(p.translate(-0.04, -0.04), 0.035, Paint()..color = Colors.white.withValues(alpha: 0.6));
        }
      case WorldKind.candy:
        // A swirled sweet.
        disc(r + 0.03, const Color(0xFFB0285F), const Color(0xFF7A1840));
        disc(r - 0.03, const Color(0xFFFFE3F1), const Color(0xFFFF9AC4));
        final swirl = Path()..moveTo(p.dx, p.dy);
        for (var k = 1; k <= 30; k++) {
          final a = k * 0.55;
          final rad = 0.22 * k / 30;
          swirl.lineTo(p.dx + cos(a) * rad, p.dy + sin(a) * rad);
        }
        c.drawPath(swirl, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.05..strokeCap = StrokeCap.round..color = dim(const Color(0xFFFF4F9A)));
      case WorldKind.shifting:
        // A rune pad that glows until pressed.
        disc(r + 0.03, const Color(0xFF241A4A), const Color(0xFF110A28));
        disc(r - 0.03, const Color(0xFF5B4B9A), const Color(0xFF332A66));
        final glow = used ? const Color(0xFF4A4270) : const Color(0xFFD9CCFF);
        c.drawCircle(p, 0.2, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.035..color = glow);
        final tri = Path();
        for (var k = 0; k < 3; k++) {
          final q = p + polar(0.14, k * 2 * pi / 3 - pi / 2);
          k == 0 ? tri.moveTo(q.dx, q.dy) : tri.lineTo(q.dx, q.dy);
        }
        c.drawPath(tri..close(), Paint()..style = PaintingStyle.stroke..strokeWidth = 0.035..strokeJoin = StrokeJoin.round..color = glow);
        if (!used) {
          c.drawCircle(p, 0.3, Paint()..shader = ui.Gradient.radial(p, 0.3, [
            const Color(0xFFA98BFF).withValues(alpha: 0.4),
            const Color(0xFFA98BFF).withValues(alpha: 0),
          ]));
        }
      case WorldKind.volcano:
        // An obsidian plate with a flame that burns until pressed.
        disc(r + 0.03, const Color(0xFF2A1512), const Color(0xFF120807));
        disc(r - 0.03, const Color(0xFF5E4038), const Color(0xFF34201C));
        final flame = Path()
          ..moveTo(p.dx, p.dy - 0.2)
          ..quadraticBezierTo(p.dx + 0.17, p.dy - 0.02, p.dx + 0.1, p.dy + 0.12)
          ..quadraticBezierTo(p.dx, p.dy + 0.2, p.dx - 0.1, p.dy + 0.12)
          ..quadraticBezierTo(p.dx - 0.16, p.dy - 0.02, p.dx, p.dy - 0.2)
          ..close();
        if (!used) {
          c.drawCircle(p, 0.3, Paint()..shader = ui.Gradient.radial(p, 0.3, [
            const Color(0xFFFF7A2E).withValues(alpha: 0.4),
            const Color(0xFFFF7A2E).withValues(alpha: 0),
          ]));
        }
        c.drawPath(flame, Paint()..color = used ? const Color(0xFF4A3530) : const Color(0xFFFF7A2E));
        if (!used) {
          c.drawCircle(p.translate(0, 0.06), 0.06, Paint()..color = const Color(0xFFFFE08A));
        }
      case WorldKind.space:
        final glow = used ? 0.0 : 0.5 + 0.5 * sin(t * 4 + j);
        c.drawCircle(
          p,
          r + 0.3,
          Paint()
            ..shader = ui.Gradient.radial(p, r + 0.3, [
              const Color(0xFF45C4F2).withValues(alpha: 0.4 * glow),
              const Color(0xFF45C4F2).withValues(alpha: 0),
            ]),
        );
        disc(r + 0.03, const Color(0xFF1B2233), const Color(0xFF0E1320));
        disc(r - 0.03, const Color(0xFF3C4A6A), const Color(0xFF222C44));
        // A glowing hexagon with a light in the middle.
        final hex = Path();
        for (var i = 0; i < 6; i++) {
          final q = p + polar(0.2, i * pi / 3);
          i == 0 ? hex.moveTo(q.dx, q.dy) : hex.lineTo(q.dx, q.dy);
        }
        c.drawPath(
          hex..close(),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.05
            ..strokeJoin = StrokeJoin.round
            ..color = used ? const Color(0xFF2E3A52) : const Color(0xFF45C4F2),
        );
        disc(0.08, const Color(0xFF9BE8FF), const Color(0xFF2E8CB0));
    }
    c.drawCircle(p, r + 0.03, ring);
    c.restore();
  }

  /// Bonus pickup: a pulsing golden orb with a symbol for what it does.
  void _bonus(Canvas c, Offset p, double t) {
    final pulse = 0.5 + 0.5 * sin(t * 3 + p.dx);
    c.save();
    c.translate(p.dx, p.dy);
    c.scale(0.8);
    c.translate(-p.dx, -p.dy);
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
      case WorldKind.graveyard:
        // A drop of holy water.
        final drop = Path()
          ..moveTo(p.dx, p.dy - 0.17)
          ..quadraticBezierTo(p.dx + 0.15, p.dy + 0.02, p.dx, p.dy + 0.15)
          ..quadraticBezierTo(p.dx - 0.15, p.dy + 0.02, p.dx, p.dy - 0.17)
          ..close();
        c.drawPath(drop, line);
        c.drawLine(p.translate(0, -0.03), p.translate(0, 0.09), line);
        c.drawLine(p.translate(-0.05, 0.02), p.translate(0.05, 0.02), line);
      case WorldKind.ocean:
        // An anchor: currents and jellyfish hold still.
        c.drawCircle(p.translate(0, -0.13), 0.04, line);
        c.drawLine(p.translate(0, -0.09), p.translate(0, 0.14), line);
        c.drawLine(p.translate(-0.07, -0.03), p.translate(0.07, -0.03), line);
        c.drawArc(Rect.fromCenter(center: p.translate(0, 0.04), width: 0.28, height: 0.2), 0.2, pi - 0.4, false, line);
      case WorldKind.glass:
        // A prism splitting light: the lasers and the floor
        // leave you alone.
        c.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - 0.15)
            ..lineTo(p.dx + 0.14, p.dy + 0.11)
            ..lineTo(p.dx - 0.14, p.dy + 0.11)
            ..close(),
          line,
        );
        c.drawLine(p.translate(-0.2, 0.0), p.translate(-0.04, 0.02), line);
        c.drawLine(p.translate(0.05, 0.02), p.translate(0.2, 0.09), line..color = const Color(0xFFFF6B9D));
      case WorldKind.factory:
        // A stop sign: the machines halt.
        final stop = Path();
        for (var i = 0; i < 8; i++) {
          final q = p + polar(0.16, i * pi / 4 + pi / 8);
          i == 0 ? stop.moveTo(q.dx, q.dy) : stop.lineTo(q.dx, q.dy);
        }
        c.drawPath(stop..close(), line);
        c.drawLine(p.translate(-0.07, 0), p.translate(0.07, 0), line);
      case WorldKind.candy:
        // A peppermint: a disc with swirled stripes.
        c.drawCircle(p, 0.14, line);
        for (var i = 0; i < 3; i++) {
          final a = i * 2 * pi / 3;
          c.drawArc(Rect.fromCircle(center: p + polar(0.07, a), radius: 0.07), a, pi, false, line);
        }
      case WorldKind.shifting:
        // An eye: the moving walls show themselves.
        final eye = Path()
          ..moveTo(p.dx - 0.17, p.dy)
          ..quadraticBezierTo(p.dx, p.dy - 0.2, p.dx + 0.17, p.dy)
          ..quadraticBezierTo(p.dx, p.dy + 0.2, p.dx - 0.17, p.dy);
        c.drawPath(eye, line);
        c.drawCircle(p, 0.05, Paint()..color = Colors.white);
      case WorldKind.volcano:
        // A snowflake: the lava, the steam and the crust cool down.
        for (var i = 0; i < 3; i++) {
          final a = i * pi / 3 + pi / 2;
          c.drawLine(p + polar(0.17, a), p + polar(0.17, a + pi), line);
        }
      case WorldKind.space:
        // Crosshair: the stabilizer holds the ball steady.
        c.drawCircle(p, 0.1, line);
        for (var i = 0; i < 4; i++) {
          c.drawLine(p + polar(0.1, i * pi / 2), p + polar(0.19, i * pi / 2), line);
        }
    }
    c.restore();
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
    // Thinner than the walls it sits between, and not reaching into them.
    final w = 0.18 * (1 - 0.6 * a);
    Paint stroke(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
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

  // ---- graveyard --------------------------------------------------------

  /// A ghost: a pale sheet with a wavy hem. Asleep it is faint and low; driven
  /// off by holy water it turns blue and flickers.
  void _ghost(Canvas c, Creature g, double t) {
    final fleeing = g.lockLeft > 0;
    final alpha = g.asleep && !fleeing
        ? 0.3
        : fleeing
            ? 0.45 + 0.2 * sin(t * 20)
            : 0.85;
    final bob = g.asleep && !fleeing ? 0.0 : sin(t * 3 + g.phase) * 0.05;
    final p = g.pos.translate(0, bob);
    final body = fleeing ? const Color(0xFFBFE6FF) : const Color(0xFFF1F4FF);
    const w = 0.24;
    final path = Path()..moveTo(p.dx - w, p.dy + 0.2);
    path.lineTo(p.dx - w, p.dy - 0.05);
    path.arcToPoint(Offset(p.dx + w, p.dy - 0.05),
        radius: const Radius.circular(w), clockwise: true);
    path.lineTo(p.dx + w, p.dy + 0.2);
    // The wavy hem.
    for (var i = 0; i < 4; i++) {
      final x0 = p.dx + w - i * (2 * w / 4);
      final x1 = p.dx + w - (i + 1) * (2 * w / 4);
      final lift = (i.isEven ? -0.07 : 0.0) + sin(t * 5 + i) * 0.015;
      path.quadraticBezierTo((x0 + x1) / 2, p.dy + 0.2 + lift * 2, x1, p.dy + 0.2);
    }
    path.close();
    c.drawPath(path.shift(const Offset(0.04, 0.07)),
        Paint()..color = Colors.black.withValues(alpha: 0.25 * alpha));
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..strokeJoin = StrokeJoin.round
        ..color = Palette.ink.withValues(alpha: alpha),
    );
    c.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(
          p.translate(0, -0.3),
          p.translate(0, 0.25),
          [body.withValues(alpha: alpha), body.withValues(alpha: alpha * 0.55)],
        ),
    );
    final eye = Paint()..color = const Color(0xFF1B2433).withValues(alpha: alpha);
    if (g.asleep && !fleeing) {
      // Closed eyes.
      for (final dx in [-0.09, 0.09]) {
        c.drawLine(p.translate(dx - 0.04, -0.04), p.translate(dx + 0.04, -0.04),
            Paint()..color = eye.color..strokeWidth = 0.03..strokeCap = StrokeCap.round);
      }
    } else {
      c.drawOval(Rect.fromCenter(center: p.translate(-0.09, -0.04), width: 0.07, height: 0.11), eye);
      c.drawOval(Rect.fromCenter(center: p.translate(0.09, -0.04), width: 0.07, height: 0.11), eye);
      c.drawOval(Rect.fromCenter(center: p.translate(0, 0.08), width: 0.07, height: 0.09), eye);
    }
  }

  /// Cold fog: soft drifting clouds. They only slow the ball, so they are
  /// light, and they do not hide the walls.
  void _fog(Canvas c, MudPatch f, double t) {
    for (var i = 0; i < 4; i++) {
      final a = t * 0.25 + i * pi / 2 + f.pos.dx;
      final at = f.pos + polar(f.radius * 0.28, a);
      final r = f.radius * (0.72 + 0.12 * sin(t * 0.7 + i));
      c.drawCircle(
        at,
        r,
        Paint()
          ..shader = ui.Gradient.radial(at, r, [
            const Color(0xFFDDE8FF).withValues(alpha: 0.34),
            const Color(0xFFB9CCF2).withValues(alpha: 0.18),
            const Color(0xFFB9CCF2).withValues(alpha: 0),
          ], const [0, 0.55, 1]),
      );
    }
  }

  /// A grave that caves in: a headstone while the ground cracks and shakes,
  /// then an open pit.
  void _grave(Canvas c, Hazard h, double t, double fadeOut) {
    // The open pit is half the width of a corridor.
    const scale = 0.4 / 0.86;
    c.save();
    c.translate(h.pos.dx, h.pos.dy);
    c.scale(scale);
    if (!h.armed) {
      final k = (h.age / h.armAt).clamp(0.0, 1.0);
      final shake = sin(t * 40) * 0.025 * k;
      // The mound, with cracks that spread.
      c.drawOval(Rect.fromCenter(center: const Offset(0, 0.06), width: 0.62, height: 0.34),
          Paint()..color = const Color(0xFF4A3B2C));
      final crack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF140C06);
      for (var i = 0; i < 5; i++) {
        final a = i * 2 * pi / 5 + 0.4;
        c.drawLine(const Offset(0, 0.06), Offset.zero.translate(cos(a) * 0.28 * k, 0.06 + sin(a) * 0.15 * k), crack);
      }
      // The headstone, trembling.
      final stone = RRect.fromRectAndCorners(
        Rect.fromCenter(center: Offset(shake, -0.12), width: 0.3, height: 0.36),
        topLeft: const Radius.circular(0.15),
        topRight: const Radius.circular(0.15),
      );
      c.drawRRect(stone.inflate(0.035), Paint()..color = Palette.ink);
      c.drawRRect(stone, Paint()..color = const Color(0xFFA9AFBC));
      final rip = Paint()..color = const Color(0xFF5E6472)..strokeWidth = 0.035..strokeCap = StrokeCap.round;
      c.drawLine(Offset(shake, -0.24), Offset(shake, -0.04), rip);
      c.drawLine(Offset(shake - 0.07, -0.17), Offset(shake + 0.07, -0.17), rip);
    } else {
      // The ground has fallen in.
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.86, height: 0.6),
          Paint()..color = const Color(0xFF3A2A1A).withValues(alpha: fadeOut));
      c.drawOval(Rect.fromCenter(center: const Offset(0, 0.02), width: 0.7, height: 0.46),
          Paint()..color = const Color(0xFF0B0704).withValues(alpha: fadeOut));
      c.drawOval(Rect.fromCenter(center: const Offset(0, 0.06), width: 0.34, height: 0.2),
          Paint()..color = Colors.black.withValues(alpha: fadeOut));
    }
    c.restore();
  }

  // ---- spaceship --------------------------------------------------------

  /// A security camera: its view cone, cut short by the walls, turning from
  /// pale blue to red as it makes up its mind, and the camera itself, turned
  /// to where it looks.
  void _camera(Canvas c, SecurityCamera cam, double t) {
    final angle = game.cameraAngle(cam);
    final k = (cam.alert / GameController.cameraReaction).clamp(0.0, 1.0);
    const rays = 14;
    final cone = Path()..moveTo(cam.pos.dx, cam.pos.dy);
    for (var i = 0; i <= rays; i++) {
      final a = angle - GameController.cameraHalfAngle +
          2 * GameController.cameraHalfAngle * i / rays;
      final d = game.sightDistance(cam.pos, a, GameController.cameraRange);
      final q = cam.pos + polar(d, a);
      cone.lineTo(q.dx, q.dy);
    }
    cone.close();
    final tint = Color.lerp(const Color(0xFF7DF9FF), const Color(0xFFFF3B3B), k)!;
    c.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.radial(
          cam.pos,
          GameController.cameraRange,
          [tint.withValues(alpha: 0.5), tint.withValues(alpha: 0.06)],
        ),
    );

    c.save();
    c.translate(cam.pos.dx, cam.pos.dy);
    c.drawCircle(const Offset(0.03, 0.06), 0.19, Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.drawCircle(Offset.zero, 0.19, Paint()..color = Palette.ink);
    c.drawCircle(Offset.zero, 0.15, Paint()..color = const Color(0xFF59627A));
    c.rotate(angle);
    // The housing, with the lens in front.
    final housing = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0.03, 0), width: 0.36, height: 0.2),
        const Radius.circular(0.06));
    c.drawRRect(housing.inflate(0.03), Paint()..color = Palette.ink);
    c.drawRRect(
      housing,
      Paint()
        ..shader = ui.Gradient.linear(const Offset(0, -0.1), const Offset(0, 0.1),
            const [Color(0xFFDDE5F2), Color(0xFF7C88A3)]),
    );
    c.drawCircle(const Offset(0.2, 0), 0.075, Paint()..color = Palette.ink);
    c.drawCircle(const Offset(0.2, 0), 0.055, Paint()..color = tint);
    c.drawCircle(const Offset(0.185, -0.018), 0.018, Paint()..color = Colors.white);
    c.restore();
    final blink = sin(t * 6 + cam.phase) > 0.2;
    c.drawCircle(cam.pos.translate(-0.06, -0.06), 0.03,
        Paint()..color = (blink || k > 0 ? const Color(0xFFFF3B3B) : const Color(0xFF5A1E1E)));
  }

  /// A jellyfish: a soft glowing bell with trailing tentacles, inside a
  /// ring that shows how far its sting reaches. It glows brighter just before
  /// it turns round.
  void _jelly(Canvas c, Jellyfish j, double t) {
    const reach = GameController.jellyReach;
    final glow = 0.45 + 0.55 * j.glow;
    final p = j.pos.translate(0, sin(t * 2 + j.home.dx) * 0.03);
    // Danger zone.
    c.drawCircle(
      p,
      reach,
      Paint()
        ..shader = ui.Gradient.radial(p, reach, [
          const Color(0xFFFF8AE8).withValues(alpha: 0.12 + 0.22 * glow),
          const Color(0xFFFF8AE8).withValues(alpha: 0),
        ], const [0.5, 1]),
    );
    c.drawCircle(
      p,
      reach,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03
        ..color = const Color(0xFFFFB3F0).withValues(alpha: 0.25 + 0.4 * glow),
    );
    // Tentacles trailing behind and waving.
    final tent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.035
      ..color = const Color(0xFFFFC9F4).withValues(alpha: 0.5 + 0.4 * glow);
    for (var i = -2; i <= 2; i++) {
      final x = p.dx + i * 0.07;
      final sway = sin(t * 3 + i) * 0.05;
      c.drawPath(
        Path()
          ..moveTo(x, p.dy + 0.05)
          ..quadraticBezierTo(x + sway, p.dy + 0.2, x - sway, p.dy + 0.34),
        tent,
      );
    }
    // The bell.
    final bell = Path()
      ..moveTo(p.dx - 0.18, p.dy + 0.05)
      ..quadraticBezierTo(p.dx - 0.18, p.dy - 0.22, p.dx, p.dy - 0.22)
      ..quadraticBezierTo(p.dx + 0.18, p.dy - 0.22, p.dx + 0.18, p.dy + 0.05)
      ..quadraticBezierTo(p.dx, p.dy + 0.0, p.dx - 0.18, p.dy + 0.05)
      ..close();
    c.drawPath(bell, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.05..strokeJoin = StrokeJoin.round..color = Palette.ink);
    c.drawPath(
      bell,
      Paint()
        ..shader = ui.Gradient.radial(p.translate(-0.04, -0.1), 0.3, [
          Color.lerp(const Color(0xFFFFE6FA), Colors.white, j.glow)!,
          Color.lerp(const Color(0xFFE68AD8), const Color(0xFFFF6FD8), j.glow)!,
        ]),
    );
    c.drawCircle(p.translate(-0.06, -0.12), 0.03, Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  /// Cracking floor: hairlines at first, then wider cracks, then missing
  /// chips, and finally a hole.
  void _crack(Canvas c, Crumble k, double t) {
    if (k.level < 0.05) return;
    final rnd = Random((k.pos.dx * 997 + k.pos.dy * 131).round());
    final level = k.level.clamp(0.0, 1.0);
    final reach = 0.28 + 0.4 * level;
    final shake = k.stage >= 3 ? Offset(sin(t * 60), cos(t * 53)) * 0.012 : Offset.zero;
    final center = k.pos + shake;
    if (level > 0.5) {
      // Chips that have already fallen away.
      final hole = Path();
      const n = 9;
      for (var i = 0; i < n; i++) {
        final q = center + polar(reach * (0.35 + 0.25 * rnd.nextDouble()), i * 2 * pi / n);
        i == 0 ? hole.moveTo(q.dx, q.dy) : hole.lineTo(q.dx, q.dy);
      }
      c.drawPath(hole..close(), Paint()..color = const Color(0xFF0C2230).withValues(alpha: (level - 0.5) * 1.6));
    }
    final dark = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 0.02 + 0.03 * level
      ..color = const Color(0xFF2E6C8C).withValues(alpha: 0.9);
    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.012
      ..color = Colors.white.withValues(alpha: 0.8);
    final lines = 3 + (level * 7).floor();
    for (var i = 0; i < lines; i++) {
      final a = i * 2 * pi / lines + rnd.nextDouble() * 0.5;
      final len = reach * (0.6 + 0.4 * rnd.nextDouble());
      final mid = center + polar(len * 0.5, a + (rnd.nextDouble() - 0.5) * 0.7);
      final end = center + polar(len, a);
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(mid.dx, mid.dy)
        ..lineTo(end.dx, end.dy);
      c.drawPath(path, dark);
      c.save();
      c.translate(-0.012, -0.012);
      c.drawPath(path, light);
      c.restore();
    }
  }

  /// A laser cutting the whole maze: a warning band first, then the beam.
  void _beam(Canvas c, GlassBeam b, double t) {
    final d = b.b - b.a;
    final len = d.distance;
    if (len < 1e-6) return;
    Paint line(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = width
      ..color = color;
    const pink = Color(0xFFFF4FD8);
    final w = b.halfWidth * 2;
    if (!b.burning) {
      final k = b.age / GlassBeam.warning;
      final on = sin(t * (10 + 14 * k)) > 0;
      c.drawLine(b.a, b.b, line(pink.withValues(alpha: 0.08 + 0.1 * k), w));
      c.drawLine(b.a, b.b, line(pink.withValues(alpha: on ? 0.9 : 0.3), 0.05));
    } else {
      final fade = (1 - (b.age - GlassBeam.warning) / GlassBeam.burn).clamp(0.0, 1.0);
      final grow = min(1.0, (b.age - GlassBeam.warning) / 0.06);
      c.drawLine(b.a, b.b, line(pink.withValues(alpha: 0.3 * fade), w * grow));
      c.drawLine(b.a, b.b, line(pink.withValues(alpha: 0.9 * fade), 0.2 * grow));
      c.drawLine(b.a, b.b, line(Colors.white.withValues(alpha: fade), 0.07 * grow));
    }
    for (final e in [b.a, b.b]) {
      c.drawCircle(e, 0.12, Paint()..color = Palette.ink);
      c.drawCircle(e, 0.085, Paint()..color = b.burning ? pink : const Color(0xFF7A3A6A));
    }
  }

  /// A laser across the corridor: emitters in the walls, a thin blinking line
  /// as a warning, then the burning beam.
  void _laser(Canvas c, Laser l, double t) {
    final phase = game.laserPhase(l);
    final perp = Offset(-l.along.dy, l.along.dx);
    final a = l.center - perp * 0.5;
    final b = l.center + perp * 0.5;
    Paint line(Color color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = width
      ..color = color;
    const red = Color(0xFFFF3B3B);
    if (phase == 2) {
      c.drawLine(a, b, line(red.withValues(alpha: 0.3), 0.4));
      c.drawLine(a, b, line(red, 0.14));
      c.drawLine(a, b, line(Colors.white, 0.05));
    } else if (phase == 1) {
      final on = sin(t * 18) > 0;
      c.drawLine(a, b, line(red.withValues(alpha: on ? 0.85 : 0.25), 0.04));
    } else {
      c.drawLine(a, b, line(red.withValues(alpha: 0.14), 0.025));
    }
    for (final e in [a, b]) {
      c.drawCircle(e, 0.095, Paint()..color = Palette.ink);
      c.drawCircle(e, 0.07, Paint()..color = phase == 0 ? const Color(0xFF6A3A3A) : red);
    }
  }

  /// An airlock door: a shut one is a striped metal bar across the corridor;
  /// an open one is only the two panels in the walls, with a green light (amber
  /// and blinking just before it shuts).
  void _airlock(Canvas c, Airlock a, double t) {
    final phase = game.airlockPhase(a);
    final perp = Offset(-a.along.dy, a.along.dx);
    final p1 = a.center - perp * 0.5;
    final p2 = a.center + perp * 0.5;
    Paint line(Color color, double width, [StrokeCap cap = StrokeCap.butt]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = cap
      ..strokeWidth = width
      ..color = color;
    if (phase == 2) {
      c.drawLine(p1 + const Offset(0.04, 0.07), p2 + const Offset(0.04, 0.07),
          line(Colors.black.withValues(alpha: 0.35), 0.26));
      c.drawLine(p1, p2, line(Palette.ink, 0.26));
      c.drawLine(p1, p2, line(const Color(0xFF8995AA), 0.2));
      // Hazard stripes across the door.
      for (var d = 0.06; d < 0.94; d += 0.16) {
        final s = p1 + (p2 - p1) * d;
        c.drawLine(s, s + (p2 - p1) * 0.08, line(const Color(0xFFFFC107), 0.2));
      }
    } else {
      final amber = phase == 1;
      final blink = !amber || sin(t * 16) > 0;
      for (final e in [(p1, p2), (p2, p1)]) {
        final end = e.$1 + (e.$2 - e.$1) * 0.16;
        c.drawLine(e.$1, end, line(Palette.ink, 0.24));
        c.drawLine(e.$1, end, line(const Color(0xFF8995AA), 0.17));
      }
      if (amber) {
        // A ghost of the door about to close.
        c.drawLine(p1, p2, line(const Color(0xFFFFC107).withValues(alpha: blink ? 0.35 : 0.1), 0.1));
      }
      final led = amber ? const Color(0xFFFFB300) : const Color(0xFF3DDC84);
      c.drawCircle(a.center, 0.065, Paint()..color = Palette.ink);
      c.drawCircle(a.center, 0.045, Paint()..color = blink ? led : led.withValues(alpha: 0.3));
    }
  }

  // ---- factory ----------------------------------------------------------

  /// A conveyor belt across the corridor: chevrons run along it, and blink red
  /// just before it reverses.
  void _belt(Canvas c, Belt b, double t) {
    final dir = game.beltDir(b);
    c.save();
    c.translate(b.center.dx, b.center.dy);
    c.rotate(b.along.direction);
    final body = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 1.0, height: 0.62), const Radius.circular(0.12));
    c.drawRRect(body.shift(const Offset(0.03, 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.drawRRect(body.inflate(0.05), Paint()..color = Palette.ink);
    c.drawRRect(body, Paint()..color = const Color(0xFF353C46));
    // Hazard rails along both sides.
    for (final side in [-0.26, 0.26]) {
      for (var x = -0.46; x < 0.46; x += 0.16) {
        c.drawLine(Offset(x, side), Offset(x + 0.08, side),
            Paint()..strokeWidth = 0.07..color = const Color(0xFFE0A526));
      }
    }
    if (dir != 0) {
      final reversing = game.beltReversing(b);
      final tint = reversing && sin(t * 20) > 0 ? const Color(0xFFFF5A4A) : const Color(0xFFFFC94A);
      final arrow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.06
        ..color = tint.withValues(alpha: 0.9);
      for (var i = 0; i < 4; i++) {
        final k = (i / 4 + t * 0.4 * dir) % 1.0;
        final x = (k - 0.5) * 0.9;
        c.drawPath(
          Path()
            ..moveTo(x - 0.06 * dir, -0.1)
            ..lineTo(x + 0.06 * dir, 0)
            ..lineTo(x - 0.06 * dir, 0.1),
          arrow,
        );
      }
    } else {
      c.drawCircle(Offset.zero, 0.06, Paint()..color = const Color(0xFF8995AA));
    }
    c.restore();
  }

  /// A press: pistons in the walls and a faint stripe-edged square while it is
  /// raised, a blinking red square as it comes down, a steel plate when it
  /// slams.
  void _press(Canvas c, Press p, double t) {
    final phase = game.pressPhase(p);
    c.save();
    c.translate(p.center.dx, p.center.dy);
    c.rotate(p.along.direction);
    final pad = Rect.fromCenter(center: Offset.zero, width: 0.62, height: 0.7);
    if (phase == 2) {
      c.drawRect(pad.shift(const Offset(0.03, 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.4));
      c.drawRect(pad.inflate(0.05), Paint()..color = Palette.ink);
      c.drawRect(pad, Paint()..color = const Color(0xFF9AA5B5));
      for (var y = pad.top + 0.04; y < pad.bottom - 0.08; y += 0.14) {
        c.drawLine(Offset(pad.left, y + 0.1), Offset(pad.right, y),
            Paint()..strokeWidth = 0.06..color = const Color(0xFFE0A526));
      }
      for (final q in [pad.topLeft, pad.topRight, pad.bottomLeft, pad.bottomRight]) {
        c.drawCircle(Offset.lerp(q, Offset.zero, 0.18)!, 0.025, Paint()..color = Palette.ink);
      }
    } else {
      final warn = phase == 1;
      final on = !warn || sin(t * 18) > 0;
      final tint = warn ? const Color(0xFFFF4040) : const Color(0xFFE0A526);
      c.drawRect(pad, Paint()..color = tint.withValues(alpha: warn ? (on ? 0.3 : 0.08) : 0.08));
      c.drawRect(
        pad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.04
          ..color = tint.withValues(alpha: warn ? (on ? 0.95 : 0.3) : 0.3),
      );
    }
    // The pistons in the walls.
    for (final side in [-1.0, 1.0]) {
      final piston = Rect.fromCenter(center: Offset(0, side * 0.5), width: 0.28, height: 0.16);
      c.drawRect(piston.inflate(0.03), Paint()..color = Palette.ink);
      c.drawRect(piston, Paint()..color = const Color(0xFF8995AA));
    }
    c.restore();
  }

  /// An electromagnet: a horseshoe that glows red and blue while it pulls,
  /// with field rings drawn in towards it.
  void _magnet(Canvas c, Magnet m, double t) {
    final phase = game.magnetPhase(m);
    if (phase == 2) {
      c.drawCircle(
        m.pos,
        GameController.magnetReach,
        Paint()
          ..shader = ui.Gradient.radial(m.pos, GameController.magnetReach, [
            const Color(0xFF8E6BFF).withValues(alpha: 0.18),
            const Color(0xFF8E6BFF).withValues(alpha: 0),
          ]),
      );
      for (var i = 0; i < 3; i++) {
        final k = (t * 0.8 + i / 3) % 1.0;
        c.drawCircle(
          m.pos,
          GameController.magnetReach * (1 - k),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.035
            ..color = const Color(0xFFB9A6FF).withValues(alpha: 0.5 * k),
        );
      }
    } else if (phase == 1 && sin(t * 16) > 0) {
      c.drawCircle(m.pos, 0.42, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.04..color = const Color(0xFFFFC94A));
    }
    final on = phase == 2;
    c.drawCircle(m.pos.translate(0.03, 0.06), 0.3, Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.drawCircle(m.pos, 0.3, Paint()..color = Palette.ink);
    c.drawCircle(m.pos, 0.25, Paint()..color = const Color(0xFF59627A));
    final shoe = Path()
      ..moveTo(m.pos.dx - 0.13, m.pos.dy + 0.12)
      ..lineTo(m.pos.dx - 0.13, m.pos.dy - 0.02)
      ..arcToPoint(Offset(m.pos.dx + 0.13, m.pos.dy - 0.02), radius: const Radius.circular(0.13))
      ..lineTo(m.pos.dx + 0.13, m.pos.dy + 0.12);
    c.drawPath(shoe, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.11..strokeCap = StrokeCap.butt..color = Palette.ink);
    c.drawPath(shoe, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.07..strokeCap = StrokeCap.butt..color = const Color(0xFFC8D0DC));
    c.drawLine(m.pos.translate(-0.13, 0.1), m.pos.translate(-0.13, 0.15),
        Paint()..strokeWidth = 0.07..color = on ? const Color(0xFFFF4040) : const Color(0xFF8A4A4A));
    c.drawLine(m.pos.translate(0.13, 0.1), m.pos.translate(0.13, 0.15),
        Paint()..strokeWidth = 0.07..color = on ? const Color(0xFF4F8CFF) : const Color(0xFF4A5A8A));
  }

  /// A turntable: a toothed disc that turns the floor under the ball, with
  /// arrows round it showing which way, blinking red before it reverses.
  void _turntable(Canvas c, Turntable tt, double t) {
    final dir = game.turntableDir(tt);
    final reversing = game.turntableReversing(tt);
    final spin = dir == 0 ? tt.phase : t * 1.3 * dir + tt.phase;
    const r = GameController.turntableReach;
    c.drawCircle(tt.pos.translate(0.03, 0.06), r, Paint()..color = Colors.black.withValues(alpha: 0.28));
    c.drawCircle(tt.pos, r, Paint()..color = Palette.ink);
    c.drawCircle(tt.pos, r - 0.05, Paint()..color = const Color(0xFF414A56));
    // Teeth round the rim, turning.
    for (var i = 0; i < 12; i++) {
      final a = spin + i * pi / 6;
      c.drawLine(tt.pos + polar(r - 0.16, a), tt.pos + polar(r - 0.06, a),
          Paint()..strokeWidth = 0.07..strokeCap = StrokeCap.butt..color = const Color(0xFF8995AA));
    }
    c.drawCircle(tt.pos, 0.1, Paint()..color = Palette.ink);
    c.drawCircle(tt.pos, 0.06, Paint()..color = const Color(0xFFE0A526));
    if (dir != 0) {
      final tint = reversing && sin(t * 20) > 0 ? const Color(0xFFFF5A4A) : const Color(0xFFFFC94A);
      final arrow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.055
        ..color = tint.withValues(alpha: 0.9);
      for (var i = 0; i < 2; i++) {
        final a0 = i * pi + 0.3;
        c.drawArc(Rect.fromCircle(center: tt.pos, radius: 0.27), a0, dir * 1.7, false, arrow);
        final tip = a0 + dir * 1.7;
        final at = tt.pos + polar(0.27, tip);
        final back = tip - dir * 0.5;
        c.drawLine(at, tt.pos + polar(0.34, back), arrow);
        c.drawLine(at, tt.pos + polar(0.2, back), arrow);
      }
    }
  }

  /// A wrecking ball on a rail across the corridor, swinging from side to
  /// side. Its reach is ringed, and it hangs still while the stop holds.
  void _pendulum(Canvas c, Pendulum p, double t) {
    final across = game.pendulumAcross(p);
    c.save();
    c.translate(p.center.dx, p.center.dy);
    c.rotate(p.along.direction);
    final rail = Paint()..strokeCap = StrokeCap.round;
    c.drawLine(const Offset(0, -0.5), const Offset(0, 0.5), rail..strokeWidth = 0.1..color = Palette.ink);
    c.drawLine(const Offset(0, -0.5), const Offset(0, 0.5), rail..strokeWidth = 0.05..color = const Color(0xFF8995AA));
    for (final end in [-0.5, 0.5]) {
      c.drawCircle(Offset(0, end), 0.07, Paint()..color = Palette.ink);
      c.drawCircle(Offset(0, end), 0.045, Paint()..color = const Color(0xFFE0A526));
    }
    final bob = Offset(0, across);
    if (game.bonusLeft <= 0) {
      c.drawCircle(bob, GameController.pendulumBob + 0.12,
          Paint()..color = const Color(0xFFFF4040).withValues(alpha: 0.12));
    }
    c.drawCircle(bob.translate(0.03, 0.06), GameController.pendulumBob, Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.drawCircle(bob, GameController.pendulumBob + 0.04, Paint()..color = Palette.ink);
    c.drawCircle(
      bob,
      GameController.pendulumBob,
      Paint()
        ..shader = ui.Gradient.radial(bob.translate(-0.05, -0.05), GameController.pendulumBob * 1.6, const [
          Color(0xFFB8C0CC),
          Color(0xFF3A414C),
        ]),
    );
    c.drawCircle(bob.translate(-0.06, -0.06), 0.04, Paint()..color = Colors.white.withValues(alpha: 0.7));
    c.restore();
  }

  // ---- candy ------------------------------------------------------------

  /// Caramel and chocolate. Caramel (and chocolate while it is melted) is a
  /// glossy sticky puddle; set chocolate is a matte square-ribbed slab.
  void _goo(Canvas c, Goo g, double t) {
    final sticky = game.gooSticky(g);
    final caramel = !g.melts;
    final base = caramel ? const Color(0xFFD98A1F) : const Color(0xFF5B3321);
    final hi = caramel ? const Color(0xFFFFD27A) : const Color(0xFF9A6444);
    const n = 16;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = i * kTwoPi / n;
      final wob = sticky ? 1 + 0.07 * sin(t * 2 + i * 1.9 + g.phase) : 1 + 0.02 * sin(i * 1.9);
      final q = g.pos + polar(g.radius * wob, a);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    path.close();
    c.drawPath(path.shift(const Offset(0.03, 0.06)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.08..strokeJoin = StrokeJoin.round..color = Palette.ink);
    c.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.radial(g.pos.translate(-0.1, -0.1), g.radius * 1.3, [
          sticky ? hi : Color.lerp(hi, Colors.white, 0.1)!,
          base,
        ]),
    );
    if (sticky) {
      // A shine, and a bubble rising now and then.
      c.drawOval(
        Rect.fromCenter(center: g.pos.translate(-0.12, -0.14), width: 0.26, height: 0.11),
        Paint()..color = Colors.white.withValues(alpha: 0.5),
      );
      final k = (t * 0.4 + g.phase) % 1.0;
      c.drawCircle(g.pos.translate(0.1, 0.08), 0.03 + 0.04 * k,
          Paint()..color = Colors.white.withValues(alpha: 0.5 * (1 - k)));
    } else {
      // A set slab: ribs like a bar of chocolate.
      final rib = Paint()..strokeWidth = 0.03..color = Colors.black.withValues(alpha: 0.35);
      c.drawLine(g.pos.translate(-g.radius * 0.8, 0), g.pos.translate(g.radius * 0.8, 0), rib);
      c.drawLine(g.pos.translate(0, -g.radius * 0.8), g.pos.translate(0, g.radius * 0.8), rib);
    }
  }

  /// A gummy worm: a mound that bulges and shivers under the floor, then a
  /// striped worm wriggling across the corridor, then gone.
  void _worm(Canvas c, Worm w, double t) {
    final phase = game.wormPhase(w);
    c.save();
    c.translate(w.center.dx, w.center.dy);
    c.rotate(w.along.direction);
    if (phase == 0) {
      // A little hole with a sprinkle of sugar round it.
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.2, height: 0.32),
          Paint()..color = const Color(0xFFB07A8C).withValues(alpha: 0.5));
      c.restore();
      return;
    }
    const hues = [Color(0xFF7CE08A), Color(0xFFFFA630), Color(0xFFFF4F9A), Color(0xFFFFE04A)];
    final hue = hues[(w.center.dx * 5 + w.center.dy * 9).abs().floor() % hues.length];
    final out = phase == 2;
    // How much of the worm is up, 0 to 1.
    final up = out ? 1.0 : 0.25 + 0.2 * sin(t * 18);
    final half = 0.5 * up;
    const n = 18;
    Offset at(int i) {
      final u = (i / n - 0.5) * 2 * half;
      return Offset(sin(t * 6 + i * 0.7) * 0.07 * up, u);
    }

    if (!out) {
      c.drawOval(Rect.fromCenter(center: Offset.zero, width: 0.34, height: 0.7 * up + 0.2),
          Paint()..color = Colors.black.withValues(alpha: 0.25));
    }
    for (var i = 0; i < n; i++) {
      final a = at(i), b = at(i + 1);
      c.drawLine(a, b, Paint()..strokeCap = StrokeCap.round..strokeWidth = 0.31..color = Palette.ink);
    }
    for (var i = 0; i < n; i++) {
      final a = at(i), b = at(i + 1);
      c.drawLine(a, b,
          Paint()..strokeCap = StrokeCap.round..strokeWidth = 0.23..color = i.isEven ? hue : Color.lerp(hue, Colors.white, 0.55)!);
      c.drawLine(a.translate(-0.05, 0), b.translate(-0.05, 0),
          Paint()..strokeCap = StrokeCap.round..strokeWidth = 0.05..color = Colors.white.withValues(alpha: 0.5));
    }
    if (out) {
      // The head at one end, with two eyes.
      final head = at(n);
      c.drawCircle(head, 0.17, Paint()..color = Palette.ink);
      c.drawCircle(head, 0.14, Paint()..color = hue);
      for (final dx in [-0.05, 0.05]) {
        c.drawCircle(head.translate(0.04, dx), 0.03, Paint()..color = Colors.white);
        c.drawCircle(head.translate(0.05, dx), 0.015, Paint()..color = Palette.ink);
      }
    }
    c.restore();
  }

  /// A gummy bear: a translucent jelly body with ears, hopping along its
  /// route, inside a ring that shows how far it reaches.
  void _gummy(Canvas c, Jellyfish j, double t) {
    const reach = GameController.jellyReach;
    const hues = [Color(0xFFFF3B5C), Color(0xFF55D66B), Color(0xFFFF9F2E), Color(0xFFFFE04A)];
    final hue = hues[(j.home.dx * 7 + j.home.dy * 13).abs().floor() % hues.length];
    final glow = 0.45 + 0.55 * j.glow;
    final hop = (sin(t * 6 + j.home.dx) * 0.5 + 0.5) * 0.05;
    final p = j.pos.translate(0, -hop);
    c.drawCircle(
      j.pos,
      reach,
      Paint()
        ..shader = ui.Gradient.radial(j.pos, reach, [
          hue.withValues(alpha: 0.1 + 0.2 * glow),
          hue.withValues(alpha: 0),
        ], const [0.5, 1]),
    );
    c.drawCircle(j.pos, reach, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.03..color = hue.withValues(alpha: 0.25 + 0.35 * glow));
    c.drawOval(Rect.fromCenter(center: j.pos.translate(0, 0.2), width: 0.4, height: 0.12),
        Paint()..color = Colors.black.withValues(alpha: 0.25));
    void blob(Offset at, double r) {
      c.drawCircle(at, r + 0.04, Paint()..color = Palette.ink);
    }

    final parts = [
      (p.translate(0, 0.07), 0.15),
      (p.translate(-0.15, 0.1), 0.07),
      (p.translate(0.15, 0.1), 0.07),
      (p.translate(-0.09, 0.2), 0.07),
      (p.translate(0.09, 0.2), 0.07),
      (p.translate(0, -0.13), 0.12),
      (p.translate(-0.1, -0.24), 0.045),
      (p.translate(0.1, -0.24), 0.045),
    ];
    for (final (at, r) in parts) {
      blob(at, r);
    }
    for (final (at, r) in parts) {
      c.drawCircle(at, r, Paint()..color = hue);
    }
    c.drawCircle(p.translate(-0.05, -0.18), 0.04, Paint()..color = Colors.white.withValues(alpha: 0.7));
    c.drawCircle(p.translate(-0.05, 0.03), 0.045, Paint()..color = Colors.white.withValues(alpha: 0.35));
    final eye = Paint()..color = Palette.ink;
    c.drawCircle(p.translate(-0.04, -0.14), 0.017, eye);
    c.drawCircle(p.translate(0.04, -0.14), 0.017, eye);
    c.drawArc(Rect.fromCenter(center: p.translate(0, -0.1), width: 0.07, height: 0.05), 0.2, pi - 0.4, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 0.015..color = Palette.ink);
  }

  // ---- shifting maze ----------------------------------------------------

  /// A door in a passage. Shut, it is drawn exactly like the maze's own walls,
  /// so nothing tells the two apart; it grows in and fades out rather than
  /// popping, and just before it shuts a ghost of the wall flickers.
  void _door(Canvas c, ShiftDoor d, double t) {
    if (game.doorsRevealed) _doorVision(c, d, t);
    var a = d.shown;
    if (d.state == 1) a = max(a, 0.15 + 0.25 * (0.5 + 0.5 * sin(t * 12)));
    if (a <= 0.01) return;
    final path = game.maze.edgePath(d.edge);
    Paint stroke(Color color, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = w
      ..color = color.withValues(alpha: color.a * a);
    c.save();
    c.translate(0.07, 0.12);
    c.drawPath(path, stroke(Colors.black.withValues(alpha: 0.35), 0.48));
    c.restore();
    c.drawPath(path, stroke(Palette.ink, 0.45));
    c.drawPath(path, stroke(theme.wallBase, 0.37));
    c.drawPath(path, stroke(theme.wallMain, 0.29));
    c.save();
    c.translate(-0.02, -0.05);
    c.drawPath(path, stroke(theme.wallHi.withValues(alpha: 0.8), 0.08));
    c.restore();
    // The joints of the stonework, as along the maze's own walls.
    final joint = stroke(Palette.ink.withValues(alpha: 0.45), 0.03);
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 0.5) {
        final tan = metric.getTangentForOffset(at);
        if (tan == null) continue;
        final n = Offset(-tan.vector.dy, tan.vector.dx);
        c.drawLine(tan.position + n * 0.11, tan.position - n * 0.11, joint);
      }
    }
  }

  /// Vision: the outline of a moving wall and the seconds until it changes
  /// (green: an open way that will shut; amber: a wall that will open).
  void _doorVision(Canvas c, ShiftDoor d, double t) {
    final shut = d.state == 2;
    final tint = shut ? const Color(0xFFFFB300) : const Color(0xFF55E6C1);
    final path = game.maze.edgePath(d.edge);
    final pulse = 0.5 + 0.5 * sin(t * 5 + d.edge);
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.5
        ..color = tint.withValues(alpha: 0.12 + 0.1 * pulse),
    );
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 0.05
        ..color = tint.withValues(alpha: 0.85),
    );
    // The countdown, only near the ball (a number on every wall is too much).
    if ((d.center - game.pos).distance > 5.5) return;
    final seconds = max(0, d.timer.ceil());
    final text = TextPainter(
      text: TextSpan(
        text: '$seconds',
        style: TextStyle(
          color: tint,
          fontSize: 0.34,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 0.08, offset: Offset(0.02, 0.03))],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(c, d.center - Offset(text.width / 2, text.height / 2));
  }

  // ---- volcano ----------------------------------------------------------

  /// The outline of a river of lava: a rounded stretch of corridor with a
  /// wobbling edge.
  Path _lavaShape(LavaFlow l, double t, {double grow = 1}) {
    const n = 28;
    final angle = l.along.direction;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = i * kTwoPi / n;
      final ca = cos(a), sa = sin(a);
      // A squarish ellipse: long along the corridor, narrower across it.
      final x = ca.sign * pow(ca.abs(), 0.6) * 0.62;
      final y = sa.sign * pow(sa.abs(), 0.6) * 0.38;
      final wob = 1 + 0.045 * sin(t * 2.2 + i * 1.7 + l.phase);
      final q = Offset(x * wob * grow, y * wob * grow);
      final r = Offset(q.dx * cos(angle) - q.dy * sin(angle), q.dx * sin(angle) + q.dy * cos(angle));
      final at = l.center + r;
      i == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    return path..close();
  }

  /// Lava crusts over, glows through its cracks just before it floods, and
  /// then runs molten.
  void _lava(Canvas c, LavaFlow l, double t) {
    final phase = game.lavaPhase(l);
    final since = game.lavaTime(l) - game.config.lavaMolten;
    final cooling = phase == 0 && game.bonusLeft <= 0 && since < 0.7;
    final rnd = Random((l.center.dx * 977 + l.center.dy * 131).round());
    final shape = _lavaShape(l, t);
    final angle = l.along.direction;

    // The crust: dark plates with cracks that glow with the heat below.
    void crust(double heat) {
      c.drawPath(shape, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.12..strokeJoin = StrokeJoin.round..color = Palette.ink);
      c.drawPath(shape, Paint()..color = const Color(0xFF2B1B18));
      c.save();
      c.clipPath(shape);
      final crack = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 0.025 + 0.035 * heat
        ..color = Color.lerp(const Color(0xFFC2410C), const Color(0xFFFFC94A), heat)!
            .withValues(alpha: 0.5 + 0.5 * heat);
      for (var i = 0; i < 9; i++) {
        final a = rnd.nextDouble() * kTwoPi;
        final from = l.center + polar(0.05 + rnd.nextDouble() * 0.15, a);
        final mid = from + polar(0.2 + rnd.nextDouble() * 0.12, a + (rnd.nextDouble() - 0.5));
        final to = mid + polar(0.18 + rnd.nextDouble() * 0.12, a + (rnd.nextDouble() - 0.5) * 1.4);
        c.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..lineTo(mid.dx, mid.dy)
            ..lineTo(to.dx, to.dy),
          crack,
        );
      }
      c.restore();
    }

    if (phase == 2) {
      c.drawCircle(
        l.center,
        1.1,
        Paint()
          ..shader = ui.Gradient.radial(l.center, 1.1, [
            const Color(0xFFFF6A1A).withValues(alpha: 0.4),
            const Color(0xFFFF6A1A).withValues(alpha: 0),
          ]),
      );
      c.drawPath(shape, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.12..strokeJoin = StrokeJoin.round..color = Palette.ink);
      c.drawPath(
        shape,
        Paint()
          ..shader = ui.Gradient.radial(l.center, 0.62, const [
            Color(0xFFFFE27A),
            Color(0xFFFF8A1F),
            Color(0xFFD13A0E),
          ], const [0, 0.55, 1]),
      );
      c.save();
      c.clipPath(shape);
      // Bright veins slowly flowing along the corridor, and bubbles.
      for (var i = 0; i < 3; i++) {
        final k = (t * 0.35 + i / 3 + l.phase) % 1.0;
        final from = l.center + polar((k - 0.5) * 1.2, angle) + polar((i - 1) * 0.13, angle + pi / 2);
        c.drawLine(
          from,
          from + polar(0.26, angle),
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 0.055
            ..color = const Color(0xFFFFF1B0).withValues(alpha: 0.65 * sin(k * pi)),
        );
      }
      for (var i = 0; i < 4; i++) {
        final k = (t * 0.6 + i * 0.25 + l.phase) % 1.0;
        final at = l.center + polar(0.2 * (i - 1.5), angle) + polar((rnd.nextDouble() - 0.5) * 0.3, angle + pi / 2);
        c.drawCircle(at, 0.03 + 0.05 * k, Paint()..color = const Color(0xFFFFF1B0).withValues(alpha: 0.8 * (1 - k)));
      }
      c.restore();
    } else if (phase == 1) {
      // About to flood: the cracks flare and blink.
      final flare = 0.55 + 0.45 * sin(t * 16);
      c.drawCircle(
        l.center,
        0.9,
        Paint()
          ..shader = ui.Gradient.radial(l.center, 0.9, [
            const Color(0xFFFF6A1A).withValues(alpha: 0.28 * flare),
            const Color(0xFFFF6A1A).withValues(alpha: 0),
          ]),
      );
      crust(0.6 + 0.4 * flare);
    } else {
      crust(0.1 + 0.08 * sin(t * 1.5 + l.phase));
      if (cooling) {
        // Just cooled: the molten glow fades away.
        final fade = 1 - since / 0.7;
        c.drawPath(shape, Paint()..color = const Color(0xFFFF8A1F).withValues(alpha: 0.7 * fade));
      }
    }
  }

  /// A steam vent: a crater with wisps of steam, hissing and shaking before
  /// the jet, then a billowing column that shoves everything away.
  void _geyser(Canvas c, Geyser g, double t) {
    final phase = game.geyserPhase(g);
    final k = game.geyserProgress(g);
    final shake = phase == 1 ? Offset(sin(t * 55), cos(t * 47)) * (0.012 * k) : Offset.zero;
    final at = g.pos + shake;

    // The reach of the jet, and the part that scalds.
    if (phase >= 1) {
      c.drawCircle(
        g.pos,
        GameController.geyserReach,
        Paint()..color = Colors.white.withValues(alpha: phase == 2 ? 0.07 : 0.03 * k),
      );
      c.drawCircle(
        g.pos,
        GameController.geyserScald,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.05
          ..color = Colors.redAccent.withValues(alpha: phase == 2 ? 0.9 : 0.25 + 0.4 * k * (0.5 + 0.5 * sin(t * 18))),
      );
    }

    // The crater.
    c.drawOval(Rect.fromCenter(center: at, width: 0.74, height: 0.5), Paint()..color = Palette.ink);
    c.drawOval(Rect.fromCenter(center: at, width: 0.62, height: 0.4), Paint()..color = const Color(0xFF4A3A36));
    c.drawOval(
      Rect.fromCenter(center: at.translate(0, 0.02), width: 0.4, height: 0.24),
      Paint()
        ..color = Color.lerp(const Color(0xFF14090A), const Color(0xFFFF7A2E), phase == 0 ? 0.0 : phase == 1 ? k : 1)!,
    );

    // Steam: lazy wisps while quiet, thick puffs while hissing, a column in
    // the eruption.
    final puffs = phase == 2 ? 11 : phase == 1 ? 6 : 3;
    for (var i = 0; i < puffs; i++) {
      final life = (t * (phase == 2 ? 1.6 : 0.5) + i / puffs + g.phase) % 1.0;
      final spread = phase == 2 ? 0.4 : 0.14;
      final dx = sin(i * 2.4 + g.phase) * spread * life;
      final rise = life * (phase == 2 ? 1.1 + 0.4 * sin(k * pi) : 0.45);
      final r = (phase == 2 ? 0.16 : 0.08) + life * (phase == 2 ? 0.34 : 0.14);
      final alpha = (phase == 2 ? 0.7 : phase == 1 ? 0.4 : 0.22) * sin(life * pi);
      c.drawCircle(at.translate(dx, -rise), r, Paint()..color = Colors.white.withValues(alpha: alpha));
    }
    if (phase == 2) {
      // Rings of force running out from the vent.
      for (var i = 0; i < 2; i++) {
        final w = (t * 1.5 + i * 0.5) % 1.0;
        c.drawCircle(
          g.pos,
          GameController.geyserReach * w,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.04
            ..color = Colors.white.withValues(alpha: 0.35 * (1 - w)),
        );
      }
    }
  }

  /// Thin crust: a dark plate, cracked, with the glow of lava below. It
  /// splits wider the longer the ball stands on it, then falls in.
  void _crust(Canvas c, Crust k, double t) {
    final level = k.level.clamp(0.0, 1.0);
    final rnd = Random((k.pos.dx * 733 + k.pos.dy * 199).round());
    final shake = k.stage >= 2 ? Offset(sin(t * 60), cos(t * 53)) * 0.012 * level : Offset.zero;
    final center = k.pos + shake;
    final plate = Path();
    const n = 11;
    for (var i = 0; i < n; i++) {
      final q = center + polar(0.4 + rnd.nextDouble() * 0.06, i * kTwoPi / n);
      i == 0 ? plate.moveTo(q.dx, q.dy) : plate.lineTo(q.dx, q.dy);
    }
    plate.close();
    final heat = 0.35 + 0.15 * sin(t * 2 + k.pos.dx) + level * 0.5;
    c.drawCircle(
      center,
      0.7,
      Paint()
        ..shader = ui.Gradient.radial(center, 0.7, [
          const Color(0xFFFF6A1A).withValues(alpha: 0.18 + 0.3 * level),
          const Color(0xFFFF6A1A).withValues(alpha: 0),
        ]),
    );
    c.drawPath(plate, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.08..strokeJoin = StrokeJoin.round..color = Palette.ink);
    c.drawPath(plate, Paint()..color = const Color(0xFF33231F));
    if (level > 0.4) {
      // Pieces already fallen away, showing the lava.
      final hole = Path();
      for (var i = 0; i < 8; i++) {
        final q = center + polar((0.08 + 0.2 * (level - 0.4)) * (0.6 + 0.4 * rnd.nextDouble()), i * kTwoPi / 8);
        i == 0 ? hole.moveTo(q.dx, q.dy) : hole.lineTo(q.dx, q.dy);
      }
      c.drawPath(hole..close(), Paint()..color = const Color(0xFFFF8A1F).withValues(alpha: min(1, (level - 0.4) * 3)));
    }
    final crack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 0.025 + 0.035 * level
      ..color = Color.lerp(const Color(0xFFD9480F), const Color(0xFFFFC94A), heat.clamp(0.0, 1.0))!;
    final lines = 4 + (level * 6).floor();
    for (var i = 0; i < lines; i++) {
      final a = i * kTwoPi / lines + rnd.nextDouble() * 0.5;
      final mid = center + polar(0.14 + 0.06 * rnd.nextDouble(), a + (rnd.nextDouble() - 0.5) * 0.7);
      final end = center + polar(0.32 + 0.06 * rnd.nextDouble(), a);
      c.drawPath(
        Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(mid.dx, mid.dy)
          ..lineTo(end.dx, end.dy),
        crack,
      );
    }
  }

  /// A volcanic bomb: a target ring on the floor and a growing shadow while
  /// it falls, then a smouldering rock in a pool of flames that dies down.
  void _bomb(Canvas c, Hazard h, double t, double fadeOut) {
    if (!h.armed) {
      final k = (h.age / h.armAt).clamp(0.0, 1.0);
      final pulse = 0.5 + 0.5 * sin(t * 14);
      c.drawCircle(h.pos, h.radius, Paint()..color = const Color(0xFFFF6A1A).withValues(alpha: 0.12 + 0.2 * k * pulse));
      c.drawCircle(
        h.pos,
        h.radius * (1.0 - 0.5 * k),
        Paint()
          ..color = const Color(0xFFFF8A3A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.06,
      );
      // The shadow of the bomb coming down.
      c.drawCircle(h.pos, 0.1 + 0.3 * k, Paint()..color = Colors.black.withValues(alpha: 0.45 * k));
      return;
    }
    // The fire fills half the width of a corridor.
    c.save();
    c.translate(h.pos.dx, h.pos.dy);
    c.scale(0.4 / 0.95);
    c.drawCircle(
      Offset.zero,
      0.85,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 0.85, [
          const Color(0xFFFF7A2E).withValues(alpha: 0.5 * fadeOut),
          const Color(0xFFFF7A2E).withValues(alpha: 0),
        ]),
    );
    c.drawOval(
      Rect.fromCenter(center: const Offset(0, 0.05), width: 0.95, height: 0.7),
      Paint()..color = const Color(0xFF1A0D0A).withValues(alpha: 0.85 * fadeOut),
    );
    // Flames licking up around the rock.
    for (var i = 0; i < 6; i++) {
      final a = i * kTwoPi / 6 + 0.3;
      final base = Offset.zero + polar(0.26, a);
      final flick = 0.7 + 0.3 * sin(t * 11 + i * 2);
      final tall = (0.3 + 0.14 * sin(i * 3.1)) * flick;
      final flame = Path()
        ..moveTo(base.dx - 0.09, base.dy)
        ..quadraticBezierTo(base.dx - 0.07, base.dy - tall * 0.6, base.dx, base.dy - tall)
        ..quadraticBezierTo(base.dx + 0.07, base.dy - tall * 0.6, base.dx + 0.09, base.dy)
        ..close();
      c.drawPath(flame, Paint()..color = const Color(0xFFFF6A1A).withValues(alpha: fadeOut));
      c.drawPath(
        flame.transform((Matrix4.identity()
              ..translateByDouble(base.dx, base.dy, 0, 1)
              ..scaleByDouble(0.5, 0.55, 1, 1)
              ..translateByDouble(-base.dx, -base.dy, 0, 1))
            .storage),
        Paint()..color = const Color(0xFFFFD04A).withValues(alpha: fadeOut),
      );
    }
    c.drawCircle(Offset.zero, 0.2, Paint()..color = Palette.ink.withValues(alpha: fadeOut));
    c.drawCircle(Offset.zero, 0.16, Paint()..color = const Color(0xFF4A322C).withValues(alpha: fadeOut));
    c.drawCircle(const Offset(-0.04, -0.04), 0.06, Paint()..color = const Color(0xFFFF8A3A).withValues(alpha: fadeOut));
    c.restore();
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
    if (game.config.world == WorldKind.graveyard) {
      _grave(c, h, t, fadeOut);
      return;
    }
    if (game.config.world == WorldKind.volcano) {
      _bomb(c, h, t, fadeOut);
      return;
    }
    // Spikes pop out of the ground, filling half the width of a corridor.
    c.save();
    c.translate(h.pos.dx, h.pos.dy);
    c.scale(0.4 / 0.68);
    const o = Offset.zero;
    final k = (h.age / h.armAt).clamp(0.0, 1.0);
    c.drawCircle(o, 0.34 * k, Paint()..color = const Color(0xFF140C06).withValues(alpha: fadeOut));
    if (h.armed) {
      final spike = Paint()..color = const Color(0xFFD5DCE0).withValues(alpha: fadeOut);
      for (var i = 0; i < 7; i++) {
        final a = i * 2 * pi / 7;
        final base = o + polar(0.17, a);
        c.drawPath(
          Path()
            ..moveTo(base.dx + 0.05 * cos(a + pi / 2), base.dy + 0.05 * sin(a + pi / 2))
            ..lineTo(base.dx - 0.05 * cos(a + pi / 2), base.dy - 0.05 * sin(a + pi / 2))
            ..lineTo(base.dx + 0.05 * cos(a), base.dy + 0.05 * sin(a) - 0.2)
            ..close(),
          spike,
        );
      }
      c.drawCircle(o.translate(0, -0.2), 0.06, spike);
    } else {
      c.drawCircle(
        o,
        0.34,
        Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.04,
      );
    }
    c.restore();
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
    paintBall(c, p, r, game.config.ball, game.ballRot, game.chameleonShown);
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
    if (game.spins) canvas.rotate(game.spinAngle);
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
