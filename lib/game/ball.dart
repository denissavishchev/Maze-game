import 'dart:math';

/// The material the ball is made of. Each one trades something for something
/// else; the numbers are multipliers on the standard (wooden) ball.
enum BallKind { wood, steel, rubber, glass, stone, slime, paper, bubble, chameleon }

class BallStats {
  const BallStats({
    this.accel = 1,
    this.maxSpeed = 1,
    this.damping = 1,
    this.bounce = 0.25,
    this.radius = 1,
    this.noise = 1,
    this.windResist = 0,
    this.bogResist = 0,
    this.stick = 0,
    this.breaksAt,
    this.floats = false,
    this.magnetic = 0,
  });

  /// How quickly a tilt gets it rolling.
  final double accel;

  /// Top speed.
  final double maxSpeed;

  /// Rolling friction: lower means it keeps rolling longer.
  final double damping;

  /// Springiness against walls (0 = dead stop, 1 = full rebound).
  final double bounce;

  /// Size.
  final double radius;

  /// How loud it is at a given speed.
  final double noise;

  /// Share of a gust of wind it shrugs off (negative: blown harder).
  final double windResist;

  /// Share of a bog's pull and suction it resists (negative: sinks faster).
  final double bogResist;

  /// How strongly it clings to a wall it touches: extra rolling friction per
  /// second while it is up against one.
  final double stick;

  /// A hit at least this hard destroys it (null: unbreakable).
  final double? breaksAt;

  /// Floats above the ground: bogs, fog and crumbling floor leave it alone.
  final bool floats;

  /// How strongly electromagnets pull at it (only iron does).
  final double magnetic;

  /// The same traits in a ball of another size.
  BallStats withRadius(double r) => BallStats(
        accel: accel,
        maxSpeed: maxSpeed,
        damping: damping,
        bounce: bounce,
        radius: r,
        noise: noise,
        windResist: windResist,
        bogResist: bogResist,
        stick: stick,
        breaksAt: breaksAt,
        floats: floats,
        magnetic: magnetic,
      );
}

BallStats statsOf(BallKind kind) => switch (kind) {
      BallKind.wood => const BallStats(),
      // The chameleon has no traits of its own: the game gives it those of
      // another ball for ten seconds at a time (see GameController.ball).
      BallKind.chameleon => const BallStats(),
      BallKind.steel => const BallStats(
          accel: 0.85,
          maxSpeed: 1.15,
          damping: 0.7,
          bounce: 0.1,
          noise: 1.4,
          windResist: 0.25,
          magnetic: 1,
        ),
      BallKind.rubber => const BallStats(
          accel: 1.1,
          bounce: 0.9,
          noise: 0.55,
          windResist: -0.25,
        ),
      BallKind.glass => const BallStats(
          accel: 1.3,
          maxSpeed: 1.1,
          bounce: 0.35,
          radius: 0.8,
          breaksAt: 5.0,
        ),
      BallKind.stone => const BallStats(
          accel: 0.8,
          maxSpeed: 0.85,
          damping: 1.2,
          bounce: 0.05,
          radius: 1.15,
          noise: 0.8,
          windResist: 0.6,
          bogResist: 0.5,
        ),
      BallKind.slime => const BallStats(
          accel: 0.9,
          maxSpeed: 0.9,
          damping: 1.3,
          bounce: 0,
          noise: 0.5,
          windResist: 0.35,
          bogResist: -0.4,
          stick: 2.5,
        ),
      // Light and almost silent, but it stops quickly, a gust carries it off
      // and damp ground ruins it.
      BallKind.paper => const BallStats(
          accel: 1.15,
          maxSpeed: 0.9,
          damping: 1.35,
          bounce: 0.05,
          radius: 0.9,
          noise: 0.3,
          windResist: -0.6,
          bogResist: -0.6,
        ),
      // A soap bubble: a thin skin of air, big and drifting. Nothing on the
      // floor touches it, but a gust carries it far and any real knock pops it.
      BallKind.bubble => const BallStats(
          accel: 1.2,
          maxSpeed: 0.8,
          damping: 0.7,
          bounce: 0.45,
          radius: 1.3,
          noise: 0.12,
          windResist: -0.7,
          bogResist: 1,
          breaksAt: 3.8,
          floats: true,
        ),
    };

// ---- Rolling -------------------------------------------------------------
//
// The ball's orientation is a 3x3 rotation matrix (row-major, 9 numbers) with
// the viewer looking down the z axis. Rolling turns it about the axis
// perpendicular to the direction of travel, so patterns on the surface slide
// along exactly as fast as the ball moves.

typedef Rot = List<double>;

Rot identityRot() => <double>[1, 0, 0, 0, 1, 0, 0, 0, 1];

Rot _mul(Rot a, Rot b) => <double>[
      for (var i = 0; i < 3; i++)
        for (var j = 0; j < 3; j++)
          a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j],
    ];

/// [r] turned by [angle] radians about the axis ([ax], [ay], [az]).
Rot turnRot(Rot r, double ax, double ay, double az, double angle) {
  final len = _len(ax, ay, az);
  if (len < 1e-9 || angle == 0) return r;
  final x = ax / len, y = ay / len, z = az / len;
  final c = cos(angle), s = sin(angle), t = 1 - c;
  return _mul(<double>[
    t * x * x + c, t * x * y - s * z, t * x * z + s * y, //
    t * x * y + s * z, t * y * y + c, t * y * z - s * x, //
    t * x * z - s * y, t * y * z + s * x, t * z * z + c,
  ], r);
}

/// Rolls the ball over the ground by [dx], [dy] (a displacement in maze
/// units) given its radius.
Rot rollRot(Rot r, double dx, double dy, double radius) {
  final dist = _len(dx, dy, 0);
  if (dist < 1e-9) return r;
  // Surface velocity at the top must point along the motion: the axis is the
  // direction of travel turned a quarter turn.
  return turnRot(r, -dy / dist, dx / dist, 0, dist / radius);
}

/// Pulls a rotation matrix back to exactly orthonormal after many small
/// turns, so the ball never slowly shears.
Rot orthonormalize(Rot r) {
  var x = [r[0], r[1], r[2]];
  var y = [r[3], r[4], r[5]];
  double dot(List<double> a, List<double> b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  List<double> norm(List<double> a) {
    final l = _len(a[0], a[1], a[2]);
    return [a[0] / l, a[1] / l, a[2] / l];
  }

  x = norm(x);
  final d = dot(y, x);
  y = norm([y[0] - d * x[0], y[1] - d * x[1], y[2] - d * x[2]]);
  final z = [
    x[1] * y[2] - x[2] * y[1],
    x[2] * y[0] - x[0] * y[2],
    x[0] * y[1] - x[1] * y[0],
  ];
  return <double>[...x, ...y, ...z];
}

/// A pleasant resting pose that shows the markings of every material.
Rot restingRot() => turnRot(turnRot(identityRot(), 1, 0, 0, 0.5), 0, 1, 0, 0.6);

double _len(double a, double b, double c) => sqrt(a * a + b * b + c * c);
