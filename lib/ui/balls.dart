import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../l10n/strings.dart';

/// Names and plain-language pros and cons of each material.
class BallInfo {
  const BallInfo(this.name, this.pros, this.cons);

  final String name;
  final List<String> pros;
  final List<String> cons;
}

BallInfo infoOf(BallKind kind) => BallInfo(
      tr('ball.${kind.name}.name'),
      trList('ball.${kind.name}.pros'),
      trList('ball.${kind.name}.cons'),
    );

// ---- Surface markings ----------------------------------------------------
//
// Every material has markings stored as points on the unit sphere. Turning the
// ball's rotation matrix moves them across its face, so a rolling ball really
// looks like it is rolling.

class _Line {
  const _Line(this.points, this.color, this.width);

  final List<List<double>> points;
  final Color color;

  /// Stroke width as a fraction of the ball radius.
  final double width;
}

class _Dot {
  const _Dot(this.at, this.color, this.size);

  final List<double> at;
  final Color color;
  final double size;
}

class _Marks {
  const _Marks(this.lines, this.dots);

  final List<_Line> lines;
  final List<_Dot> dots;
}

List<double> _unit(double x, double y, double z) {
  final l = sqrt(x * x + y * y + z * z);
  return [x / l, y / l, z / l];
}

/// A circle on the sphere: all points [angle] radians away from [axis].
List<List<double>> _ring(List<double> axis, double angle, {int n = 48}) {
  // Any two vectors perpendicular to the axis and to each other.
  final helper = axis[0].abs() < 0.9 ? [1.0, 0.0, 0.0] : [0.0, 1.0, 0.0];
  var u = [
    axis[1] * helper[2] - axis[2] * helper[1],
    axis[2] * helper[0] - axis[0] * helper[2],
    axis[0] * helper[1] - axis[1] * helper[0],
  ];
  u = _unit(u[0], u[1], u[2]);
  final v = [
    axis[1] * u[2] - axis[2] * u[1],
    axis[2] * u[0] - axis[0] * u[2],
    axis[0] * u[1] - axis[1] * u[0],
  ];
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = i * 2 * pi / n;
        final sa = sin(angle), ca = cos(angle);
        return [
          axis[0] * ca + (u[0] * cos(t) + v[0] * sin(t)) * sa,
          axis[1] * ca + (u[1] * cos(t) + v[1] * sin(t)) * sa,
          axis[2] * ca + (u[2] * cos(t) + v[2] * sin(t)) * sa,
        ];
      }(),
  ];
}

final Map<BallKind, _Marks> _marksCache = {};

_Marks _marksOf(BallKind kind) => _marksCache.putIfAbsent(kind, () {
      final rnd = Random(kind.index + 11);
      switch (kind) {
        case BallKind.wood:
          final axis = _unit(0.3, 1, 0.2);
          return _Marks([
            for (final a in [0.55, 0.9, 1.25, 1.6, 1.95, 2.3])
              _Line(_ring(axis, a), const Color(0xFF5E3A1A).withValues(alpha: 0.6), 0.07),
          ], const []);
        case BallKind.steel:
          return _Marks([
            _Line(_ring(_unit(0, 1, 0), pi / 2),
                const Color(0xFFF2F6FA).withValues(alpha: 0.55), 0.05),
            _Line(_ring(_unit(1, 0, 0), pi / 2),
                const Color(0xFF2C343D).withValues(alpha: 0.45), 0.05),
          ], [
            _Dot(_unit(0, 1, 0), const Color(0xFF2C343D), 0.1),
            _Dot(_unit(0, -1, 0), const Color(0xFF2C343D), 0.1),
          ]);
        case BallKind.rubber:
          return _Marks([
            _Line(_ring(_unit(0.2, 1, 0.1), pi / 2),
                const Color(0xFFFFE3DC).withValues(alpha: 0.55), 0.26),
            _Line(_ring(_unit(0.2, 1, 0.1), 0.9),
                const Color(0xFF6A0F0F).withValues(alpha: 0.5), 0.07),
            _Line(_ring(_unit(0.2, 1, 0.1), pi - 0.9),
                const Color(0xFF6A0F0F).withValues(alpha: 0.5), 0.07),
          ], const []);
        case BallKind.glass:
          return _Marks([
            _Line(_ring(_unit(1, 0.3, 0), pi / 2),
                Colors.white.withValues(alpha: 0.4), 0.04),
            _Line(_ring(_unit(0, 0.4, 1), pi / 2),
                Colors.white.withValues(alpha: 0.3), 0.04),
          ], [
            for (var i = 0; i < 7; i++)
              _Dot(
                _unit(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1,
                    rnd.nextDouble() * 2 - 1),
                Colors.white.withValues(alpha: 0.7),
                0.06 + rnd.nextDouble() * 0.05,
              ),
          ]);
        case BallKind.stone:
          final crack = [
            for (var i = 0; i <= 14; i++)
              _unit(
                cos(i * 0.09) + (rnd.nextDouble() - 0.5) * 0.06,
                sin(i * 0.09) + (rnd.nextDouble() - 0.5) * 0.06,
                0.25 + (rnd.nextDouble() - 0.5) * 0.06,
              ),
          ];
          return _Marks([
            _Line(crack, Colors.black.withValues(alpha: 0.45), 0.05),
          ], [
            for (var i = 0; i < 34; i++)
              _Dot(
                _unit(rnd.nextDouble() * 2 - 1, rnd.nextDouble() * 2 - 1,
                    rnd.nextDouble() * 2 - 1),
                (i.isEven ? Colors.black : Colors.white).withValues(alpha: 0.3),
                0.04 + rnd.nextDouble() * 0.06,
              ),
          ]);
      }
    });

final Rot _resting = restingRot();

/// Draws a ball of the given material centred on [p] with radius [r]. [rot] is
/// its orientation (see `rollRot`); without it the ball is drawn at rest.
void paintBall(Canvas c, Offset p, double r, BallKind kind, [Rot? rot]) {
  final m = rot ?? _resting;
  final light = p.translate(-r * 0.35, -r * 0.4);

  Paint sphere(List<Color> colors, List<double> stops) =>
      Paint()..shader = ui.Gradient.radial(light, r * 1.7, colors, stops);

  switch (kind) {
    case BallKind.wood:
      c.drawCircle(p, r,
          sphere(const [Color(0xFFE0AE72), Color(0xFF9A6634), Color(0xFF4E2F14)], const [0, 0.55, 1]));
    case BallKind.steel:
      c.drawCircle(p, r,
          sphere(const [Color(0xFFFFFFFF), Color(0xFFA7B1BC), Color(0xFF3E4752)], const [0, 0.5, 1]));
    case BallKind.rubber:
      c.drawCircle(p, r,
          sphere(const [Color(0xFFFFB199), Color(0xFFE53935), Color(0xFF7F1414)], const [0, 0.55, 1]));
    case BallKind.glass:
      c.drawCircle(p, r, Paint()..color = const Color(0xFF9AD8FF).withValues(alpha: 0.35));
      c.drawCircle(
          p,
          r,
          Paint()
            ..shader = ui.Gradient.radial(light, r * 1.6, [
              Colors.white.withValues(alpha: 0.75),
              const Color(0xFF8ED0FF).withValues(alpha: 0.35),
              const Color(0xFF2E7FB8).withValues(alpha: 0.6),
            ], const [0, 0.5, 1]));
    case BallKind.stone:
      c.drawCircle(p, r,
          sphere(const [Color(0xFFC4C4BB), Color(0xFF7D7D75), Color(0xFF3C3C37)], const [0, 0.55, 1]));
  }

  // Markings, turned by the ball's orientation; only the half facing the
  // viewer is drawn, and it thins out towards the edge like a real sphere.
  final marks = _marksOf(kind);
  List<double> turn(List<double> v) => [
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
      ];
  Offset flat(List<double> q) => Offset(p.dx + q[0] * r, p.dy + q[1] * r);

  for (final line in marks.lines) {
    final pts = [for (final v in line.points) turn(v)];
    for (var i = 0; i + 1 < pts.length; i++) {
      final a = pts[i], b = pts[i + 1];
      if (a[2] <= 0.02 || b[2] <= 0.02) continue;
      final depth = (a[2] + b[2]) / 2;
      c.drawLine(
        flat(a),
        flat(b),
        Paint()
          ..color = line.color.withValues(alpha: line.color.a * (0.25 + 0.75 * depth))
          ..strokeWidth = line.width * r * (0.35 + 0.65 * depth)
          ..strokeCap = StrokeCap.round,
      );
    }
  }
  for (final dot in marks.dots) {
    final q = turn(dot.at);
    if (q[2] <= 0.02) continue;
    c.drawCircle(
      flat(q),
      dot.size * r * (0.35 + 0.65 * q[2]),
      Paint()..color = dot.color.withValues(alpha: dot.color.a * (0.25 + 0.75 * q[2])),
    );
  }

  if (kind == BallKind.glass) {
    c.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.09
        ..color = Colors.white.withValues(alpha: 0.7),
    );
  }
  // Specular highlight: the light does not turn with the ball.
  c.drawCircle(
    light,
    r * 0.18,
    Paint()..color = Colors.white.withValues(alpha: kind == BallKind.stone ? 0.35 : 0.8),
  );
}

/// A ball as a widget that rolls on the spot (selection screen).
class BallBubble extends StatefulWidget {
  const BallBubble({super.key, required this.kind, this.size = 44});

  final BallKind kind;
  final double size;

  @override
  State<BallBubble> createState() => _BallBubbleState();
}

class _BallBubbleState extends State<BallBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _roll =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))
        ..repeat();

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: _BubblePainter(widget.kind, _roll)),
      );
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.kind, this.roll) : super(repaint: roll);

  final BallKind kind;
  final Animation<double> roll;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 2;
    canvas.drawCircle(size.center(const Offset(1, 3)), r,
        Paint()..color = Colors.black.withValues(alpha: 0.35));
    // Rolling to the right on the spot, slightly tilted so every marking
    // passes over the face.
    final rot = turnRot(restingRot(), 0.3, 1, 0.15, roll.value * 2 * pi);
    paintBall(canvas, size.center(Offset.zero), r, kind, rot);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => old.kind != kind;
}
