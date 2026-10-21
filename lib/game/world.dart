import '../l10n/strings.dart';
import 'ball.dart';

enum WorldKind { forest, mud, mountains, underground, city }

/// A chosen world and one of five levels. The level sets everything that
/// makes the game harder: maze size, number of buttons (and gates), number of
/// wolves / drones, number of traps and how fast they come, how far the
/// underground light reaches.
class GameConfig {
  const GameConfig(this.world, this.level, {this.ball = BallKind.wood});

  static const int minLevel = 1;
  static const int maxLevel = 5;

  final WorldKind world;
  final int level;

  /// The material of the ball.
  final BallKind ball;

  T _pick<T>(List<T> table) => table[level.clamp(minLevel, maxLevel) - 1];

  /// Name of the maze size, shown instead of a number.
  String get sizeName => tr('size.${level.clamp(minLevel, maxLevel)}');

  /// Buttons, and the gates they open.
  int get buttonCount => _pick(const [3, 4, 6, 8, 10]);

  /// Rings of the maze, counting the centre disc.
  int get rings => _pick(const [5, 6, 8, 9, 11]);

  /// Spikes / boulders per spawn.
  int get trapCount => _pick(const [1, 1, 2, 2, 3]);

  /// Seconds between trap spawns.
  double get trapInterval => _pick(const [2.8, 2.4, 2.1, 1.8, 1.6]);

  /// Bonuses lying on the map: as many as there are traps.
  int get bonusCount => trapCount;

  /// Mud: seconds to sink completely when stuck in a bog.
  double get bogSeconds => _pick(const [4.0, 3.4, 2.9, 2.5, 2.1]);

  /// Mud: bogs lying right on the route to the centre.
  int get routeBogs => _pick(const [1, 2, 2, 3, 4]);

  /// Mountains: warning before a boulder lands where the ball is heading.
  double get aimedWarn => _pick(const [1.5, 1.4, 1.3, 1.15, 1.0]);

  /// Mountains: gusts of wind only on the two biggest sizes.
  bool get windEnabled => level >= 4;

  /// Acceleration of a gust, in units per second squared.
  double get windStrength => _pick(const [0.0, 0.0, 0.0, 5.5, 7.5]);

  /// Wolves or drones.
  int get chaserCount => _pick(const [1, 1, 2, 2, 3]);

  /// Chaser speed in maze units per second.
  double get chaserSpeed => 1.1 + 0.2 * (level - minLevel);

  /// Underground: how far the ball lights the way.
  double get lightRadius => _pick(const [3.6, 3.2, 2.9, 2.6, 2.3]);
}
