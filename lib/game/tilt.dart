import 'dart:math';
import 'dart:ui' show Offset;

/// A direction of gravity in the phone's own frame, as a unit vector.
class Gravity {
  const Gravity._(this.x, this.y, this.z);

  /// From an accelerometer reading (any length; zero is not valid).
  factory Gravity.fromAccel(double x, double y, double z) {
    final l = sqrt(x * x + y * y + z * z);
    return Gravity._(x / l, y / l, z / l);
  }

  final double x, y, z;

  /// A step of [t] (0..1) from this direction towards [o].
  Gravity lerp(Gravity o, double t) =>
      Gravity.fromAccel(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);
}

/// How far the phone is tilted from a reference pose, as a vector in screen
/// axes (+x right, +y down) with a length of at most 1.
///
/// Uses the *rotation* between two gravity directions rather than raw
/// acceleration values. A phone held at an angle therefore feels the same as
/// one lying flat: forward and back tilts keep their full sensitivity, and
/// nothing saturates the way raw sensor readings do on a steep pose.
Offset tiltBetween(Gravity base, Gravity now, {double fullAngle = 0.42}) {
  // The axis of the rotation taking the reference to now, in the phone's frame.
  final rx = base.y * now.z - base.z * now.y;
  final ry = base.z * now.x - base.x * now.z;
  final full = sin(fullAngle);
  var t = Offset(-ry / full, -rx / full);
  if (t.distance > 1) t = t / t.distance;
  return t;
}

/// Turns accelerometer readings into a tilt, keeping the "level" pose in step
/// with how the player really holds the phone:
///  * before the first deliberate tilt, the reference follows the hand, so
///    picking the phone up, or changing grip, never starts the ball rolling;
///  * afterwards it is re-centred very slowly while the hand is steady and the
///    ball rests;
class TiltTracker {
  Gravity? _base;
  Gravity? _now;

  /// Time constants (seconds) for the two kinds of following.
  static const double followBeforeStart = 0.3;
  static const double followWhenSteady = 4.0;

  /// A tilt smaller than this counts as "steady".
  static const double steady = 0.08;

  bool get hasSensor => _now != null;

  /// Feeds one accelerometer reading.
  void feed(double x, double y, double z) {
    final g = Gravity.fromAccel(x, y, z);
    _now = g;
    _base ??= g;
  }

  /// The current tilt, using the reference pose as it is now.
  Offset get tilt =>
      hasSensor ? tiltBetween(_base!, _now!) : Offset.zero;

  /// Call once per frame after the game has looked at [tilt].
  void step(double dt, {required bool started, required double stillTime}) {
    final now = _now, base = _base;
    if (now == null || base == null || dt <= 0) return;
    if (!started) {
      _base = base.lerp(now, min(1.0, dt / followBeforeStart));
    } else if (stillTime > 2 && tilt.distance < steady) {
      _base = base.lerp(now, min(1.0, dt / followWhenSteady));
    }
  }

  /// Makes the present pose the level one (the calibrate button).
  void calibrate() {
    if (_now != null) _base = _now;
  }
}
