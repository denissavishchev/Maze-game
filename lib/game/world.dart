import '../l10n/strings.dart';
import 'ball.dart';

enum WorldKind { forest, mud, mountains, underground, city, space, graveyard, glass, ocean, volcano, factory, candy, shifting }

/// A chosen world and one of five levels. The level sets everything that
/// makes the game harder: maze size, number of buttons (and gates), number of
/// wolves / drones, number of traps and how fast they come, how far the
/// underground light reaches.
class GameConfig {
  const GameConfig(this.world, this.level,
      {this.ball = BallKind.wood, this.bonuses});

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

  /// Endless mode decides itself how many bonuses a level holds.
  final int? bonuses;

  /// Bonuses lying on the map: as many as there are traps.
  int get bonusCount => bonuses ?? trapCount;

  /// Mud: seconds to sink completely when stuck in a bog.
  double get bogSeconds => _pick(const [4.0, 3.4, 2.9, 2.5, 2.1]);

  /// Mud: bogs lying right on the route to the centre.
  int get routeBogs => _pick(const [1, 2, 2, 3, 4]);

  /// Mountains: warning before a boulder lands where the ball is heading.
  double get aimedWarn => _pick(const [1.5, 1.4, 1.3, 1.15, 1.0]);

  /// Mountains: gusts of wind only on the two biggest sizes.
  bool get windEnabled => world == WorldKind.ocean || level >= 4;

  /// Acceleration of a gust, in units per second squared.
  double get windStrength => world == WorldKind.ocean
      ? _pick(const [3.0, 3.5, 4.0, 4.5, 5.0])
      : _pick(const [0.0, 0.0, 0.0, 5.5, 7.5]);

  /// Ocean: jellyfish patrolling the corridors, and how fast they swim.
  int get jellyCount => _pick(const [2, 2, 3, 3, 4]);
  double get jellySpeed => 0.55 + 0.08 * (level - minLevel);

  /// Rewarded second chances per maze after losing: one in the smallest
  /// maze, five in the biggest.
  int get continueCount => _pick(const [1, 2, 3, 4, 5]);

  /// Wolves or drones.
  int get chaserCount => _pick(const [1, 1, 2, 2, 3]);

  /// Chaser speed in maze units per second.
  double get chaserSpeed => 1.1 + 0.2 * (level - minLevel);

  /// Graveyard: patches of cold fog that slow the ball.
  int get fogCount => _pick(const [3, 4, 5, 6, 7]);

  /// Spaceship: lasers sweeping corridors.
  int get laserCount => _pick(const [2, 2, 3, 3, 4]);

  /// Spaceship: airlock doors that open and close on a timer.
  int get airlockCount => _pick(const [1, 1, 2, 2, 3]);

  /// Spaceship: security cameras that sweep their view back and forth.
  int get cameraCount => _pick(const [2, 2, 4, 4, 6]);

  /// Spaceship: seconds a camera takes to sweep there and back.
  double get cameraPeriod => _pick(const [6.0, 5.5, 5.0, 4.5, 4.0]);

  /// Spaceship: seconds from one laser pulse to the next.
  double get laserPeriod => _pick(const [4.2, 4.0, 3.6, 3.3, 3.0]);

  /// Spaceship: pull of the changing gravity, in units per second squared.
  double get gravityStrength => _pick(const [2.6, 3.0, 3.4, 3.9, 4.4]);

  /// Spaceship: seconds between changes of the gravity's direction.
  double get gravityInterval => _pick(const [7.0, 6.5, 6.0, 5.5, 5.0]);

  /// Glass: seconds standing on one spot before the floor gives way.
  double get crumbleSeconds => _pick(const [2.75, 2.5, 2.25, 2.0, 1.75]);

  /// Glass: seconds between one laser and the next, and how many at once.
  double get beamInterval => _pick(const [2.5, 2.25, 2.0, 1.75, 1.5]);
  int get beamCount => _pick(const [2, 2, 2, 4, 4]);

  /// Volcano: rivers of lava across the route. A full cycle, and how long of
  /// it the lava is molten (it warns for a short while before that).
  int get lavaCount => _pick(const [2, 2, 3, 4, 5]);
  double get lavaPeriod => _pick(const [6.6, 6.2, 5.8, 5.4, 5.0]);
  double get lavaMolten => _pick(const [1.0, 1.0, 1.1, 1.1, 1.2]);

  /// Volcano: steam geysers, and seconds from one eruption to the next.
  int get geyserCount => _pick(const [2, 2, 3, 3, 4]);
  double get geyserPeriod => _pick(const [6.0, 5.6, 5.2, 4.8, 4.4]);

  /// Volcano: patches of thin crust, and seconds standing still before one
  /// gives way.
  int get crustCount => _pick(const [3, 4, 5, 6, 7]);
  double get crustSeconds => _pick(const [3.2, 2.9, 2.6, 2.3, 2.0]);

  /// Volcano: bombs thrown by the volcano per wave.
  int get bombCount => _pick(const [1, 1, 1, 2, 2]);

  /// Factory: conveyor belts (and seconds before one reverses), presses (and
  /// seconds from one slam to the next) and electromagnets (and their cycle).
  int get beltCount => _pick(const [4, 5, 6, 7, 8]);
  double get beltPeriod => _pick(const [5.0, 4.6, 4.2, 3.8, 3.4]);
  int get pressCount => _pick(const [1, 2, 2, 3, 3]);
  double get pressPeriod => _pick(const [4.4, 4.1, 3.8, 3.5, 3.2]);
  int get magnetCount => _pick(const [1, 1, 2, 2, 3]);
  double get magnetPeriod => _pick(const [5.5, 5.2, 4.8, 4.4, 4.0]);

  /// Factory: wrecking-ball pendulums (and seconds per swing there and back)
  /// and turntables.
  int get pendulumCount => _pick(const [1, 1, 2, 2, 3]);
  double get pendulumPeriod => _pick(const [2.8, 2.6, 2.4, 2.2, 2.0]);
  int get turntableCount => _pick(const [1, 1, 2, 2, 3]);

  /// Candy: patches of caramel and chocolate. The gummy bears are the same
  /// patrollers as the ocean's jellyfish ([jellyCount]).
  int get gooCount => _pick(const [4, 5, 6, 7, 8]);

  /// Candy: gummy worms that wriggle up across the corridor, and seconds
  /// from one appearance to the next.
  int get wormCount => _pick(const [1, 2, 2, 3, 3]);
  double get wormPeriod => _pick(const [7.0, 6.5, 6.0, 5.5, 5.0]);

  /// Shifting maze: doors that close and open again, and how long they stay
  /// open and shut. Never all at once, and never so that the way is cut.
  int get doorCount => _pick(const [10, 14, 18, 22, 26]);
  double get doorOpenSeconds => _pick(const [6.5, 6.0, 5.5, 5.0, 4.5]);
  double get doorClosedSeconds => _pick(const [4.0, 4.5, 5.0, 5.5, 6.0]);

  /// Underground: how far the ball lights the way.
  double get lightRadius => _pick(const [3.6, 3.2, 2.9, 2.6, 2.3]);
}
