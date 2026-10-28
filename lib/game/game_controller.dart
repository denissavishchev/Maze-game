import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/painting.dart' show Offset;
import '../audio/haptics.dart';
import '../audio/sfx.dart';
import '../l10n/strings.dart';
import '../monetization/vip.dart';
import 'ball.dart';
import 'maze.dart';
import 'polar_maze.dart';
import 'rect_maze.dart';
import 'records.dart';
import 'world.dart';

enum GameStatus { playing, won, lost }

/// Something that hunts the player: a wolf follows the corridors (and sleeps
/// until it hears a loud bump), a drone wanders the corridors at random and
/// watches a cone in front of it.
class Creature {
  Creature(this.pos, {this.cell = 0, this.asleep = false, this.phase = 0});

  Offset pos;
  double angle = 0;
  double age = 0;
  double repath = 0;
  int cell;
  int prevCell = -1;
  final List<Offset> route = [];

  // Wolf.
  bool asleep;
  double awakeTimer = 0;
  double grace = 0;

  /// While a bonus is active the creature sleeps and nothing can wake it.
  double lockLeft = 0;

  /// How long it has been hearing the ball (wakes it past a threshold).
  double hearing = 0;

  /// Wolf: how long it has stood without a moving target.
  double calm = 0;

  // Drone. Sleeps like the wolf; a noise wakes it and sends it to look at the
  // spot, where it scans all around before going back to patrolling.
  final double phase;
  double viewAngle = 0;
  double alert = 0;
  int target = -1;
  double searchLeft = 0;

  bool get searching => target >= 0 || searchLeft > 0;
}

/// A timed danger on the floor. Boulders are only a warning marker until
/// [armAt]; spikes become deadly after a short pop-up.
class Hazard {
  Hazard(this.pos, {required this.armAt, required this.life, this.radius = 0.4});

  final Offset pos;
  final double armAt;
  final double life;
  final double radius;
  double age = 0;

  bool get armed => age >= armAt;
}

/// A laser across a corridor, drawn from wall to wall at [center], with
/// [along] the unit direction of the corridor. It pulses: dark, then a short
/// warning, then the beam, over and over, [phase] seconds out of step with the
/// others.
class Laser {
  const Laser(this.center, this.along, this.phase);

  final Offset center;
  final Offset along;
  final double phase;
}

/// An airlock door across a corridor: open, a warning, then shut for a while.
class Airlock {
  Airlock(this.center, this.along, this.phase)
      : seg = Seg(
          center - Offset(-along.dy, along.dx) * 0.5,
          center + Offset(-along.dy, along.dx) * 0.5,
          -1,
        );

  final Offset center;
  final Offset along;
  final double phase;

  /// The closed door as a wall piece.
  final Seg seg;
}

/// A security camera on the ceiling of a corridor cell. Its view swings back
/// and forth around [base] (radians), [phase] seconds out of step with the
/// others. Kept in its view for a moment, the ball is caught.
class SecurityCamera {
  SecurityCamera(this.pos, this.base, this.phase);

  final Offset pos;
  final double base;
  final double phase;

  /// How long the ball has been in view (0 when it is not).
  double alert = 0;
}

/// Ocean: a jellyfish drifting slowly back and forth along a fixed stretch of
/// corridor. It does not chase; it only stings what it meets, and glows
/// brighter just before it turns.
class Jellyfish {
  Jellyfish(this.home) : pos = home;

  final Offset home;
  Offset pos;

  /// The stretch it patrols, as points; [at] is the one it is heading for.
  final List<Offset> path = [];
  int at = 0;
  int dir = 1;

  /// Seconds left of the pause at either end of the patrol.
  double pause = 0;

  /// 0 calm, up to 1 just before it turns.
  double glow = 0;
}

/// Glass: a spot of floor that crumbles while the ball stands on it. [level]
/// runs from 0 (whole) to 1 (gone); [stage] is the cracking seen in 4 steps.
class Crumble {
  Crumble(this.pos);

  final Offset pos;
  double level = 0;

  int get stage => min(4, (level * 4).floor());
}

/// Glass: a laser that cuts the whole maze along one row, column or chord,
/// first as a warning, then as a burning beam. [halfWidth] is how far from the
/// line it reaches.
class GlassBeam {
  GlassBeam(this.a, this.b, this.halfWidth);

  static const double warning = 1.3;
  static const double burn = 0.5;

  final Offset a;
  final Offset b;
  final double halfWidth;
  double age = 0;

  bool get burning => age >= warning;
}

/// Volcano: a stretch of corridor that floods with lava now and then. Crusted
/// over it is harmless; molten, it is deadly. [along] is the unit direction of
/// the corridor and [phase] seconds out of step with the others.
class LavaFlow {
  const LavaFlow(this.center, this.along, this.phase);

  final Offset center;
  final Offset along;
  final double phase;
}

/// Volcano: a steam vent that hisses, then erupts. The jet shoves the ball
/// away, and scalds it at the very middle.
class Geyser {
  const Geyser(this.pos, this.phase);

  final Offset pos;
  final double phase;
}

/// Volcano: a patch of thin crust over lava. [level] runs from 0 (whole) to 1
/// (broken through) while the ball stands on it.
class Crust {
  Crust(this.pos);

  final Offset pos;
  double level = 0;

  int get stage => min(3, (level * 4).floor());
}

/// Factory: a conveyor belt across a stretch of corridor. It carries the ball
/// along the corridor one way, then the other, [phase] seconds out of step.
class Belt {
  const Belt(this.center, this.along, this.phase);

  final Offset center;
  final Offset along;
  final double phase;
}

/// Factory: a press that slams down across the corridor: raised, a warning,
/// then down for an instant.
class Press {
  const Press(this.center, this.along, this.phase);

  final Offset center;
  final Offset along;
  final double phase;
}

/// Factory: an electromagnet that switches on and off, pulling iron towards it.
class Magnet {
  const Magnet(this.pos, this.phase);

  final Offset pos;
  final double phase;
}

/// Factory: a wrecking ball swinging across a stretch of corridor on a rail,
/// [phase] seconds out of step. It sweeps the middle of the corridor and is
/// out of the way only at the two ends of its swing.
class Pendulum {
  const Pendulum(this.center, this.along, this.phase);

  final Offset center;
  final Offset along;
  final double phase;
}

/// Factory: a turntable that spins the floor under the ball one way, then the
/// other, flinging it round its middle.
class Turntable {
  const Turntable(this.pos, this.phase);

  final Offset pos;
  final double phase;
}

/// Candy: a patch of caramel (always sticky) or chocolate ([melts]: sticky only
/// while melted).
class Goo {
  const Goo(this.pos, this.radius, this.phase, this.melts);

  final Offset pos;
  final double radius;
  final double phase;
  final bool melts;
}

/// Candy: a gummy worm that wriggles up out of the floor across a stretch of
/// corridor, blocks it for a while and slips away again. [phase] seconds out of
/// step with the others.
class Worm {
  Worm(this.center, this.along, this.phase)
      : seg = Seg(
          center - Offset(-along.dy, along.dx) * 0.5,
          center + Offset(-along.dy, along.dx) * 0.5,
          -1,
        );

  final Offset center;
  final Offset along;
  final double phase;

  /// The worm's body as a wall piece, while it is out.
  final Seg seg;
}

/// Shifting maze: a passage that closes now and then and opens again. It only
/// ever closes when the ball can still finish the maze without it.
class ShiftDoor {
  ShiftDoor(this.edge, this.cells, this.segs, this.center, this.initialState, this.initial)
      : state = initialState,
        timer = initial,
        shown = initialState == 2 ? 1 : 0;

  final int edge;
  final (int, int) cells;
  final List<Seg> segs;
  final Offset center;

  /// How it starts (the extra passages start shut, the maze's own open) and
  /// the seconds before it first changes.
  final int initialState;
  final double initial;

  /// 0 open, 1 about to shut, 2 shut.
  int state;
  double timer;

  /// How much of the wall is drawn, 0 to 1: it grows in and fades out rather
  /// than popping.
  double shown;
}

class MudPatch {
  const MudPatch(this.pos, this.radius);

  final Offset pos;
  final double radius;
}

/// A short burst drawn on the floor.
class Burst {
  Burst(this.pos, this.kind);

  final Offset pos;
  final int kind; // 0 button, 1 hit, 2 gate, 3 noise
  double age = 0;
}

class GameController extends ChangeNotifier {
  /// With [endless] the game never ends by winning: reaching the centre moves
  /// on to the next world (see [endlessConfig]) until the player loses.
  GameController(this.config,
      {this.hazardsEnabled = true,
      this.endless = false,
      this.ballPool,
      int? seed})
      : _rnd = seed == null ? Random() : Random(seed) {
    if (endless) config = endlessConfig(0, _pickBall(), world: _pickWorld());
    newMaze();
  }

  /// Endless mode: the level for [stage] in [world] (the worlds in turn when
  /// none is given). The first five levels have no bonuses, the next five one
  /// bonus each, and so on.
  static GameConfig endlessConfig(int stage, BallKind ball, {WorldKind? world}) =>
      GameConfig(
        world ?? WorldKind.values[stage % WorldKind.values.length],
        GameConfig.minLevel,
        ball: ball,
        bonuses: (stage ~/ levelsPerBonusRound).isOdd ? 1 : 0,
      );

  /// Endless mode: the balls that may come up (all of them when null).
  final List<BallKind>? ballPool;

  /// Endless mode: a random ball, never the one just played.
  BallKind _pickBall() {
    final pool = ballPool ?? BallKind.values;
    final others = [
      for (final b in pool)
        if (b != config.ball) b,
    ];
    if (others.isEmpty) return pool.first;
    return others[_rnd.nextInt(others.length)];
  }

  /// Endless mode: this many levels without bonuses, then this many with one
  /// each, and so on.
  static const int levelsPerBonusRound = 5;

  /// The last worlds played in endless mode; the next one is never among them.
  static const int worldsNotRepeated = 3;
  final List<WorldKind> _recent = [];

  /// A random world, but none of the last [worldsNotRepeated] played.
  WorldKind _pickWorld() {
    final options = [
      for (final w in WorldKind.values)
        if (!_recent.contains(w)) w,
    ];
    final world = options[_rnd.nextInt(options.length)];
    _recent.add(world);
    if (_recent.length > worldsNotRepeated) _recent.removeAt(0);
    return world;
  }

  /// Endless mode: the rectangular maze is as many cells across and down as
  /// fit on the screen (see [fitGrid]).
  static const List<int> endlessColsChoices = [6, 7, 8];
  static const int minEndlessRows = 8;
  static const int maxEndlessRows = 20;

  /// Endless mode: how long the screen scrolls to the next maze.
  static const double scrollSeconds = 0.9;

  static const double baseBallRadius = 0.26;
  static const double _accel = 16;
  static const double _maxSpeed = 5.5;

  /// A bump into a wall at least this fast is heard by sleepers nearby.
  static const double loudImpact = 3.8;
  static const double noiseRadius = 3.0;

  /// Noise from movement: nothing below this speed (sneaking), full at the top.
  static const double quietSpeed = 0.6;
  static const double loudSpeed = 4.5;

  /// How far the ball is heard, from a whisper to a full roll.
  static const double minHearing = 1.0;
  static const double maxHearing = 6.5;

  /// The ball must be heard this long (seconds) to wake a sleeper.
  static const double wakeAfter = 0.5;

  /// A wolf gives up when the ball has not moved for this long...
  static const double stillBeforeBored = 3.0;

  /// ...and lies down this long afterwards.
  static const double boredBeforeSleep = 1.5;

  /// A ghost hangs motionless while the ball stands still, and fades into its
  /// grave when that lasts this long.
  static const double ghostSleepAfter = 5.0;

  /// How close the ball must come to a cell to uncover it on the minimap.
  static const double exploreRadius = 1.9;

  /// A ball this close to a wall (beyond touching it) counts as up against it.
  static const double touchMargin = 0.03;

  /// Traps never appear closer to the ball than this.
  static const double minSpikeDistance = 3.5;
  static const double minBoulderDistance = 2.6;

  /// The noise level above which the ball is reminding you it is loud.
  static const double loudNoise = 0.6;

  /// The first tilt beyond this starts the game (clock, creatures, traps).
  static const double startTilt = 0.15;

  /// Bumps slower than this make no sound (rolling along a wall); full volume
  /// at about [impactSoundMax].
  static const double impactSoundMin = 0.9;
  static const double impactSoundMax = 5.0;

  /// A landed boulder stays this long as a solid block, and this wide.
  static const double rubbleSeconds = 6;
  static const double rubbleRadius = 0.42;

  /// Gust of wind: warning, then how long it blows.
  static const double windWarning = 1.5;
  static const double windDuration = 2.5;

  /// Spaceship lasers: how long the beam burns and how long it warns first.
  static const double laserBeam = 1.0;
  static const double laserWarning = 0.9;

  /// Spaceship airlocks: a full cycle, how long a door stays open, and how
  /// long it blinks before it shuts (the rest of the cycle it is shut).
  static const double airlockCycle = 6.0;
  static const double airlockOpen = 3.4;
  static const double airlockWarning = 0.9;

  /// Security cameras: how far they see, how wide their view is (half-angle),
  /// how far it swings to either side, and how long the ball must stay in view
  /// before it is caught.
  static const double cameraRange = 3.2;
  static const double cameraHalfAngle = 0.4;
  static const double cameraSweep = 1.0;
  static const double cameraReaction = 0.4;

  /// Spaceship: the new direction of gravity is announced this long before.
  static const double gravityWarning = 1.2;

  /// Uses per bonus pickup and how long one use lasts.
  static const int usesPerBonus = 3;
  static const double bonusDuration = 10;
  static const double lightBoostFactor = 1.9;

  /// What a drone sees: a cone this long and this wide (half-angle, radians).
  static const double droneRange = 2.8;
  static const double droneHalfAngle = 0.5;

  /// A drone must keep the ball in view this long before it catches it.
  static const double droneReaction = 0.45;

  /// Endless mode: size of the maze, set to what the screen has room for.
  int endlessCols = 7;
  int endlessRows = 11;
  int? _nextStartCol;

  /// Endless mode: while the screen scrolls from one maze to the next,
  /// [prevMaze] is the maze being left and [transition] runs from 0 to 1.
  Maze? prevMaze;
  double transition = 1;
  bool get scrolling => transition < 1;

  /// A ball that can break: how close its hardest recent knock came to
  /// breaking it, 0 to 1. Held for a moment, then it drains away.
  double strain = 0;
  double _strainHold = 0;

  void _trackStrain(double dt, double knock) {
    if (knock > strain) {
      strain = min(1.0, knock);
      _strainHold = 2.5;
    } else if ((_strainHold -= dt) <= 0) {
      strain = max(0, strain - dt * 0.25);
    }
  }

  /// The level being played; in endless mode it changes with every stage.
  GameConfig config;

  final bool endless;

  /// Endless mode: how many mazes have been solved in this run.
  int stage = 0;

  /// What the chosen ball is made of, and its radius.
  BallStats get ball => config.ball == BallKind.chameleon
      ? (_chameleonStats ?? statsOf(BallKind.wood))
      : statsOf(config.ball);

  /// The chameleon: every [chameleonSeconds] it takes on the traits of another
  /// ball (never itself, never the one it just was) and a new colour that has
  /// nothing to do with it, so the player can only find out by playing. It
  /// keeps its own size so it can never be wedged in a corridor.
  static const double chameleonSeconds = 10;
  BallKind? _mimic;
  BallStats? _chameleonStats;
  double _mimicTimer = chameleonSeconds;

  /// Hue of the chameleon in degrees: where it is heading, and what is shown
  /// (it fades from one to the other).
  double chameleonHue = 0;
  double chameleonShown = 0;

  /// The ball whose traits are in force: the chosen ball, or for the chameleon
  /// the one it has become.
  BallKind get mimicking =>
      config.ball == BallKind.chameleon ? (_mimic ?? BallKind.wood) : config.ball;

  void _shiftChameleon({bool burst = true}) {
    final others = [
      for (final k in BallKind.values)
        if (k != BallKind.chameleon && k != _mimic) k,
    ];
    _mimic = others[_rnd.nextInt(others.length)];
    _chameleonStats = statsOf(_mimic!).withRadius(1);
    // A new colour, clearly different from the last.
    chameleonHue = (chameleonHue + 70 + _rnd.nextDouble() * 220) % 360;
    if (burst) {
      bursts.add(Burst(pos, 2));
      Haptics.play(Haptic.tick);
    }
  }
  double get ballRadius => baseBallRadius * ball.radius;

  /// Tests switch hazards off so an autopilot cannot be killed.
  final bool hazardsEnabled;

  final Random _rnd;

  late Maze maze;
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  Offset camera = Offset.zero;

  late List<bool> gateOpen;
  late List<bool> buttonUsed;
  late List<double> gateAnim;

  GameStatus status = GameStatus.playing;
  String lostReason = '';
  int recordRank = 0;

  /// The clock starts with the first tilt.
  bool started = false;
  double elapsed = 0;

  List<Creature> creatures = [];
  List<Hazard> hazards = [];
  List<MudPatch> mud = [];

  /// Graveyard: patches of cold fog (they slow the ball, nothing worse).
  List<MudPatch> fog = [];
  List<Burst> bursts = [];

  /// Ocean: jellyfish patrolling the corridors.
  List<Jellyfish> jellies = [];
  static const double jellyReach = 0.62;
  static const double jellyPause = 0.7;

  /// Glass: crumbling floor and the laser beams.
  List<Crumble> cracks = [];
  List<GlassBeam> beams = [];
  double _beamTimer = 3;
  bool _beamNoticed = false;

  /// Glass: slower than this and the floor starts to crumble.
  static const double crumbleSpeed = 0.9;
  static const double crumbleRadius = 0.45;

  /// Volcano: lava rivers, steam geysers and thin crust, and their clock.
  List<LavaFlow> lavas = [];
  List<Geyser> geysers = [];
  List<Crust> crusts = [];
  double _volcanoClock = 0;

  /// Lava warns this long before it floods; it kills within [lavaLength] along
  /// the corridor and [lavaWidth] across it.
  static const double lavaWarning = 0.9;
  static const double lavaLength = 0.5;
  static const double lavaWidth = 0.4;

  /// Geysers: seconds of hissing, seconds of eruption, the radius that
  /// scalds, how far the jet shoves and how hard.
  static const double geyserWarning = 1.0;
  static const double geyserBurst = 1.3;
  static const double geyserScald = 0.5;
  static const double geyserReach = 1.5;
  static const double geyserForce = 26;

  /// Thin crust: how wide a patch is, and the speed below which it cracks.
  static const double crustRadius = 0.45;
  static const double crustSpeed = 0.9;

  /// A volcanic bomb leaves fire this wide, for this long.
  static const double bombFire = 0.42;
  static const double bombFireSeconds = 3.5;

  /// Factory: belts, presses, magnets and their clock.
  List<Belt> belts = [];
  List<Press> presses = [];
  List<Magnet> magnets = [];
  List<Pendulum> pendulums = [];
  List<Turntable> turntables = [];
  double _factoryClock = 0;
  static const double pendulumSwing = 0.42;
  static const double pendulumBob = 0.18;
  static const double turntableReach = 0.6;
  static const double turntableForce = 9;
  static const double beltForce = 9;
  static const double beltWarning = 0.8;
  static const double pressWarning = 0.9;
  static const double pressSlam = 0.45;
  static const double magnetOnSeconds = 2.4;
  static const double magnetWarning = 0.8;
  static const double magnetReach = 2.0;
  static const double magnetForce = 15;

  /// Candy: caramel and chocolate, the clock the chocolate melts on, how
  /// bouncy the walls are on top of the ball's own bounce.
  List<Goo> goos = [];
  List<Worm> worms = [];
  double _candyClock = 0;
  static const double wormWarning = 1.0;
  static const double wormOut = 2.4;
  static const double gooPeriod = 7.0;
  static const double gooMelted = 3.6;
  static const double candyBounce = 0.4;

  /// Shifting maze: the doors, how long one warns before it shuts.
  List<ShiftDoor> doors = [];
  static const double doorWarning = 1.2;

  /// Gate to point the player at after a button was pressed (-1 = none).
  int hintGate = -1;
  double hintLeft = 0;

  /// Bonus pickups on the map (cells fixed per maze) and which are taken.
  List<int> bonusCells = [];
  List<bool> bonusTaken = [];
  int bonusCharges = 0;
  double bonusLeft = 0;

  /// How loud the ball is right now, 0 (silent) to 1: grows with its speed
  /// and with hard bumps into walls. Shown on screen at all times.
  double noiseLevel = 0;
  double _impactNoise = 0;

  /// Seconds the ball has been (almost) standing still.
  double stillTime = 0;

  /// Mud: how far the ball has sunk into a bog, 0 (free) to 1 (drowned).
  double sink = 0;

  /// Mountains: wind. [windWarnLeft] is the warning, [windLeft] the gust.
  Offset windDir = Offset.zero;
  double windWarnLeft = 0;
  double windLeft = 0;
  double _windTimer = 7;

  /// Spaceship: the lasers and airlock doors, and the clock they run on.
  List<Laser> lasers = [];
  List<Airlock> airlocks = [];
  List<SecurityCamera> cameras = [];
  double _spaceClock = 0;

  /// Spaceship: where gravity pulls now, where it will pull next and how long
  /// until it changes. While [gravityWarnLeft] runs, the change is announced.
  Offset gravityDir = const Offset(0, 1);
  Offset gravityNext = const Offset(0, 1);
  double gravityWarnLeft = 0;
  double _gravityTimer = 0;

  /// How the ball is turned: it rolls as it moves.
  Rot ballRot = restingRot();
  int _rollSteps = 0;

  /// Cells the ball has been near; the minimap shows nothing else.
  late List<bool> explored;
  int exploredCount = 0;
  List<Offset> _centers = [];

  /// Tests pin the noise level and the stillness timer to values.
  @visibleForTesting
  double? forcedNoise;
  @visibleForTesting
  double? forcedStill;

  /// Distance at which creatures can hear the ball at the current noise.
  double get hearingRadius =>
      noiseLevel < 0.04 ? 0 : minHearing + (maxHearing - minHearing) * noiseLevel;

  /// 1 normally, up to [lightBoostFactor] while the light bonus is active.
  double lightFactor = 1;

  /// Message shown briefly on screen (e.g. caught by a drone), as a
  /// translation key with its arguments.
  String notice = '';
  Map<String, Object> noticeArgs = const {};
  double noticeLeft = 0;

  /// Whether the ball was up against a wall during the last step.
  bool _touchingWall = false;

  double _spawnTimer = 1.5;
  double _impact = 0;
  double _soundCooldown = 0;
  double _buzzCooldown = 0;
  double _noiseCooldown = 0;
  double _invulnerable = 0;
  bool _disposed = false;

  /// Rewarded second chances spent in this maze, and in this whole endless run.
  int continuesUsed = 0;
  int runContinues = 0;

  /// Endless: a VIP gets this many second chances per run, then the run is over.
  static const int vipRunContinues = 10;

  /// Endless has no limit for a player who watches the ads; a VIP is capped.
  bool get continuesUnlimited => endless && !Vip.instance.on;

  /// Second chances still on offer: more of them in the bigger mazes, and in
  /// endless as many as the player is willing to watch an ad for.
  int get continuesLeft {
    if (!endless) return max(0, config.continueCount - continuesUsed);
    return continuesUnlimited ? 1 << 30 : max(0, vipRunContinues - runContinues);
  }

  /// Where the ball was every half second lately, for [continueAfterLoss].
  final List<Offset> _trail = [];
  double _recentClock = 0;

  /// Seconds after a second chance during which nothing can end the game.
  double _mercy = 0;

  /// After the ball is sent back to the start: where it was, and for how
  /// many more seconds a rewarded ad may put it back there.
  Offset? _sentFrom;
  double backLeft = 0;

  int get pressedCount => buttonUsed.where((u) => u).length;
  bool get won => status == GameStatus.won;
  bool get lost => status == GameStatus.lost;

  /// The shifting maze gets extra passages, so a door can shut without cutting
  /// anything off.
  int get _loopsWanted => config.world == WorldKind.shifting ? config.doorCount : 0;

  void newMaze() {
    maze = endless
        ? RectMaze.generate(
            cols: endlessCols,
            rows: endlessRows,
            gates: config.buttonCount,
            random: _rnd,
            startCol: _nextStartCol,
            loops: _loopsWanted,
          )
        : PolarMaze.generate(
            rings: config.rings,
            gates: config.buttonCount,
            random: _rnd,
            loops: _loopsWanted,
          );
    _centers = [for (var c = 0; c < maze.cellCount; c++) maze.cellCenter(c)];
    final taken = {maze.start, maze.goal, ...maze.buttonCells};
    bonusCells = ([
      for (var c = 1; c < maze.cellCount; c++)
        if (!taken.contains(c)) c,
    ]..shuffle(_rnd))
        .take(config.bonusCount)
        .toList();
    fog = [];
    if (config.world == WorldKind.graveyard) {
      final special = {maze.start, maze.goal, ...maze.buttonCells};
      final cells = [
        for (var c = 1; c < maze.cellCount; c++)
          if (!special.contains(c)) c,
      ]..shuffle(_rnd);
      for (final c in cells.take(config.fogCount)) {
        fog.add(MudPatch(maze.cellCenter(c), 0.75 + _rnd.nextDouble() * 0.3));
      }
    }
    mud = [];
    if (config.world == WorldKind.mud) {
      final special = {maze.start, maze.goal, ...maze.buttonCells};
      // Bogs stay clear of the walls: the corridor is about 0.55 wide.
      Offset jitter() =>
          Offset(_rnd.nextDouble() - 0.5, _rnd.nextDouble() - 0.5) * 0.06;
      // Bogs scattered around, plus some right on the way to the centre that
      // fill the whole corridor and cannot be avoided.
      final cells = [
        for (var c = 1; c < maze.cellCount; c++)
          if (!special.contains(c)) c,
      ]..shuffle(_rnd);
      for (final c in cells.take(maze.scatterCount)) {
        mud.add(MudPatch(maze.cellCenter(c) + jitter(), 0.18 + _rnd.nextDouble() * 0.06));
      }
      final onRoute = [
        for (final c in maze.solution)
          if (!special.contains(c)) c,
      ]..shuffle(_rnd);
      for (final c in onRoute.take(config.routeBogs)) {
        mud.add(MudPatch(maze.cellCenter(c), 0.27));
      }
    }
    lasers = [];
    airlocks = [];
    cameras = [];
    if (config.world == WorldKind.space) _placeSpaceHazards();
    jellies = [];
    if (config.world == WorldKind.ocean || config.world == WorldKind.candy) {
      _placeJellies();
    }
    belts = [];
    presses = [];
    magnets = [];
    pendulums = [];
    turntables = [];
    goos = [];
    worms = [];
    doors = [];
    if (config.world == WorldKind.factory) _placeFactory();
    if (config.world == WorldKind.candy) {
      _placeWorms();
      _placeGoo();
    }
    if (config.world == WorldKind.shifting) _placeDoors();
    lavas = [];
    geysers = [];
    crusts = [];
    if (config.world == WorldKind.volcano) _placeVolcano();
    continuesUsed = 0;
    restart();
  }

  /// Spaceship: lasers, airlocks and security cameras along the way to the
  /// exit, spread out and away from the start, on the straightest stretches of
  /// corridor.
  void _placeSpaceHazards() {
    final route = maze.solution;
    if (route.length < 5) return;
    final special = {maze.start, maze.goal, ...maze.buttonCells};
    // 0 laser, 1 airlock, 2 security camera.
    final kinds = [
      for (var i = 0; i < config.laserCount; i++) 0,
      for (var i = 0; i < config.airlockCount; i++) 1,
      for (var i = 0; i < config.cameraCount; i++) 2,
    ]..shuffle(_rnd);
    final used = <int>{};
    // How far from a straight stretch of corridor cell i of the route is:
    // 0 when it continues in line, more at a bend.
    double bend(int i) {
      final a = maze.cellCenter(route[i]) - maze.cellCenter(route[i - 1]);
      final b = maze.cellCenter(route[i + 1]) - maze.cellCenter(route[i]);
      return (a.dx * b.dy - a.dy * b.dx).abs() / (a.distance * b.distance);
    }

    for (var k = 0; k < kinds.length; k++) {
      final want = (route.length * (k + 1) / (kinds.length + 1)).round();
      // The straightest free cell close to where it is wanted.
      int? at;
      var best = double.infinity;
      for (var i = want - 6; i <= want + 6; i++) {
        if (i < 2 || i > route.length - 2) continue;
        if (used.contains(route[i]) || special.contains(route[i])) continue;
        final score = bend(i) + 0.03 * (i - want).abs();
        if (score < best) {
          best = score;
          at = i;
        }
      }
      if (at == null) continue;
      final cell = route[at];
      used.add(cell);
      final dir = maze.cellCenter(route[at + 1]) - maze.cellCenter(route[at - 1]);
      final along = dir / dir.distance;
      final center = maze.cellCenter(cell);
      final phase = _rnd.nextDouble() * config.laserPeriod;
      if (kinds[k] == 2) {
        // Looks along the corridor, one way or the other, and sweeps across.
        final look = along.direction + (_rnd.nextBool() ? 0 : pi);
        cameras.add(SecurityCamera(center, look, _rnd.nextDouble() * config.cameraPeriod));
      } else if (kinds[k] == 0) {
        lasers.add(Laser(center, along, phase));
      } else {
        airlocks.add(Airlock(center, along, _rnd.nextDouble() * airlockCycle));
      }
    }
  }

  /// Ocean: jellyfish start in cells well away from the start; their patrol
  /// is worked out on the first step, when the gates are known.
  void _placeJellies() {
    final special = {maze.start, maze.goal, ...maze.buttonCells};
    final start = maze.cellCenter(maze.start);
    final cells = [
      for (var c = 1; c < maze.cellCount; c++)
        if (!special.contains(c) && (maze.cellCenter(c) - start).distance > 3) c,
    ]..shuffle(_rnd);
    for (final c in cells.take(config.jellyCount)) {
      jellies.add(Jellyfish(maze.cellCenter(c)));
    }
  }

  /// Straight stretches of the route, spread along it and clear of the start,
  /// the buttons and the cells in [used] (which grows): where a laser-like
  /// hazard across the corridor looks right. Each is a centre and the unit
  /// direction of the corridor.
  List<(Offset, Offset)> _routeSpots(int count, Set<int> used) {
    final route = maze.solution;
    final out = <(Offset, Offset)>[];
    if (route.length < 5) return out;
    final special = {maze.start, maze.goal, ...maze.buttonCells, ...bonusCells};
    double bend(int i) {
      final a = maze.cellCenter(route[i]) - maze.cellCenter(route[i - 1]);
      final b = maze.cellCenter(route[i + 1]) - maze.cellCenter(route[i]);
      return (a.dx * b.dy - a.dy * b.dx).abs() / (a.distance * b.distance);
    }

    for (var k = 0; k < count; k++) {
      final want = (route.length * (k + 1) / (count + 1)).round();
      int? at;
      var best = double.infinity;
      for (var i = want - 6; i <= want + 6; i++) {
        if (i < 2 || i > route.length - 2) continue;
        if (used.contains(route[i]) || special.contains(route[i])) continue;
        final score = bend(i) + 0.03 * (i - want).abs();
        if (score < best) {
          best = score;
          at = i;
        }
      }
      if (at == null) continue;
      used.add(route[at]);
      final dir = maze.cellCenter(route[at + 1]) - maze.cellCenter(route[at - 1]);
      out.add((maze.cellCenter(route[at]), dir / dir.distance));
    }
    return out;
  }

  /// Factory: presses and belts across the route, magnets anywhere else.
  void _placeFactory() {
    final used = <int>{};
    // 0 press, 1 belt, 2 pendulum, 3 turntable.
    final kinds = [
      for (var i = 0; i < config.pressCount; i++) 0,
      for (var i = 0; i < config.beltCount; i++) 1,
      for (var i = 0; i < config.pendulumCount; i++) 2,
      for (var i = 0; i < config.turntableCount; i++) 3,
    ]..shuffle(_rnd);
    final spots = _routeSpots(kinds.length, used);
    for (var k = 0; k < spots.length; k++) {
      final (center, along) = spots[k];
      switch (kinds[k]) {
        case 0:
          presses.add(Press(center, along, _rnd.nextDouble() * config.pressPeriod));
        case 1:
          belts.add(Belt(center, along, _rnd.nextDouble() * config.beltPeriod * 2));
        case 2:
          pendulums.add(Pendulum(center, along, _rnd.nextDouble() * config.pendulumPeriod));
        default:
          turntables.add(Turntable(center, _rnd.nextDouble() * config.beltPeriod * 2));
      }
    }
    final special = {maze.start, maze.goal, ...maze.buttonCells, ...bonusCells, ...used};
    final start = maze.cellCenter(maze.start);
    final cells = [
      for (var c = 1; c < maze.cellCount; c++)
        if (!special.contains(c) && (maze.cellCenter(c) - start).distance > 2.5) c,
    ]..shuffle(_rnd);
    for (final c in cells.take(config.magnetCount)) {
      magnets.add(Magnet(maze.cellCenter(c), _rnd.nextDouble() * config.magnetPeriod));
    }
  }

  /// Candy: gummy worms across straight stretches of the route.
  void _placeWorms() {
    for (final (center, along) in _routeSpots(config.wormCount, {})) {
      worms.add(Worm(center, along, _rnd.nextDouble() * config.wormPeriod));
    }
  }

  /// Candy: caramel and chocolate, half of it right on the route.
  void _placeGoo() {
    final special = {
      maze.start,
      maze.goal,
      ...maze.buttonCells,
      ...bonusCells,
      for (final w in worms) maze.cellAt(w.center),
    };
    final start = maze.cellCenter(maze.start);
    final used = <int>{};
    bool free(int c) =>
        !special.contains(c) &&
        !used.contains(c) &&
        (maze.cellCenter(c) - start).distance > 2.0;
    final onRoute = [for (final c in maze.solution) if (free(c)) c]..shuffle(_rnd);
    final chosen = onRoute.take((config.gooCount + 1) ~/ 2).toList();
    used.addAll(chosen);
    final elsewhere = [
      for (var c = 1; c < maze.cellCount; c++)
        if (free(c)) c,
    ]..shuffle(_rnd);
    chosen.addAll(elsewhere.take(config.gooCount - chosen.length));
    for (var i = 0; i < chosen.length; i++) {
      goos.add(Goo(
        maze.cellCenter(chosen[i]),
        0.42,
        _rnd.nextDouble() * gooPeriod,
        i.isOdd,
      ));
    }
  }

  /// Shifting maze: the extra passages are doors, and so are a few of the
  /// maze's own; they all start open, at different times.
  void _placeDoors() {
    final ends = <int, (int, int)>{};
    for (var c = 0; c < maze.cellCount; c++) {
      for (final (n, e) in maze.neighbours(c)) {
        if (c < n) ends[e] = (c, n);
      }
    }
    final noGates = List<bool>.filled(maze.gateCount, false);
    final loopSet = maze.loops.toSet();
    final keep = {maze.start, maze.goal};
    final tree = [
      for (final e in ends.keys)
        if (!loopSet.contains(e) &&
            maze.passable(e, noGates) &&
            !keep.contains(ends[e]!.$1) &&
            !keep.contains(ends[e]!.$2))
          e,
    ]..shuffle(_rnd);
    final edges = [
      ...maze.loops.take(config.doorCount),
      ...tree.take(max(1, config.doorCount ~/ 2)),
    ];
    for (final e in edges) {
      final (a, b) = ends[e]!;
      // The extra passages start shut, so the maze begins as the plain maze
      // and then keeps opening up and closing again; its own passages start
      // open.
      final shut = loopSet.contains(e);
      doors.add(ShiftDoor(
        e,
        (a, b),
        maze.edgeSegs(e),
        (maze.cellCenter(a) + maze.cellCenter(b)) / 2,
        shut ? 2 : 0,
        shut
            ? 1.0 + _rnd.nextDouble() * config.doorClosedSeconds
            : 2.0 + _rnd.nextDouble() * config.doorOpenSeconds,
      ));
    }
  }

  /// Volcano: lava floods the straightest stretches along the route, steam
  /// geysers and thin crust sit half on the route and half off it, all clear of
  /// the start, the buttons and each other.
  void _placeVolcano() {
    final route = maze.solution;
    if (route.length < 6) return;
    final special = {maze.start, maze.goal, ...maze.buttonCells, ...bonusCells};
    final start = maze.cellCenter(maze.start);
    final used = <int>{};
    bool free(int c) =>
        !special.contains(c) &&
        !used.contains(c) &&
        (maze.cellCenter(c) - start).distance > 2.5;
    double bend(int i) {
      final a = maze.cellCenter(route[i]) - maze.cellCenter(route[i - 1]);
      final b = maze.cellCenter(route[i + 1]) - maze.cellCenter(route[i]);
      return (a.dx * b.dy - a.dy * b.dx).abs() / (a.distance * b.distance);
    }

    final n = config.lavaCount;
    for (var k = 0; k < n; k++) {
      final want = (route.length * (k + 1) / (n + 1)).round();
      int? at;
      var best = double.infinity;
      for (var i = want - 4; i <= want + 4; i++) {
        if (i < 2 || i > route.length - 3) continue;
        if (!free(route[i]) || used.contains(route[i - 1]) || used.contains(route[i + 1])) continue;
        final score = bend(i) + bend(i - 1) * 0.5 + 0.03 * (i - want).abs();
        if (score < best) {
          best = score;
          at = i;
        }
      }
      if (at == null) continue;
      used..add(route[at])..add(route[at - 1])..add(route[at + 1]);
      final dir = maze.cellCenter(route[at + 1]) - maze.cellCenter(route[at - 1]);
      lavas.add(LavaFlow(
        maze.cellCenter(route[at]),
        dir / dir.distance,
        _rnd.nextDouble() * config.lavaPeriod,
      ));
    }

    final everywhere = [for (var c = 1; c < maze.cellCount; c++) c];
    List<int> pick(int count) {
      final onRoute = [for (final c in route) if (free(c)) c]..shuffle(_rnd);
      final chosen = onRoute.take((count + 1) ~/ 2).toList();
      used.addAll(chosen);
      final elsewhere = [for (final c in everywhere) if (free(c)) c]..shuffle(_rnd);
      final rest = elsewhere.take(count - chosen.length).toList();
      used.addAll(rest);
      return [...chosen, ...rest];
    }

    for (final c in pick(config.geyserCount)) {
      geysers.add(Geyser(maze.cellCenter(c), _rnd.nextDouble() * config.geyserPeriod));
    }
    for (final c in pick(config.crustCount)) {
      crusts.add(Crust(maze.cellCenter(c)));
    }
  }

  /// Same maze, everything back to its starting state.
  void restart() {
    gateOpen = List<bool>.filled(maze.gateCount, false);
    buttonUsed = List<bool>.filled(maze.gateCount, false);
    gateAnim = List<double>.filled(maze.gateCount, 0);
    pos = maze.cellCenter(maze.start);
    vel = Offset.zero;
    camera = pos;
    status = GameStatus.playing;
    lostReason = '';
    recordRank = 0;
    started = false;
    elapsed = 0;
    hazards = [];
    bursts = [];
    prevMaze = null;
    transition = 1;
    hintGate = -1;
    notice = '';
    noticeLeft = 0;
    ballRot = restingRot();
    explored = List<bool>.filled(maze.cellCount, false);
    exploredCount = 0;
    _explore();
    noiseLevel = 0;
    _impactNoise = 0;
    stillTime = 0;
    strain = 0;
    _strainHold = 0;
    sink = 0;
    if (config.ball == BallKind.chameleon) {
      _mimic = null;
      _mimicTimer = chameleonSeconds;
      _shiftChameleon(burst: false);
      chameleonShown = chameleonHue;
    } else {
      _mimic = null;
      _chameleonStats = null;
    }
    windDir = Offset.zero;
    windWarnLeft = 0;
    windLeft = 0;
    _windTimer = 7;
    _spaceClock = 0;
    cracks = [];
    beams = [];
    for (final j in jellies) {
      j.pos = j.home;
      j.path.clear();
      j.pause = 0;
      j.glow = 0;
    }
    _beamTimer = config.beamInterval;
    _beamNoticed = false;
    _volcanoClock = 0;
    _factoryClock = 0;
    _candyClock = 0;
    for (final d in doors) {
      d.state = d.initialState;
      d.timer = d.initial;
      d.shown = d.initialState == 2 ? 1 : 0;
    }
    for (final k in crusts) {
      k.level = 0;
    }
    for (final cam in cameras) {
      cam.alert = 0;
    }
    _resetGravity();
    bonusTaken = List<bool>.filled(bonusCells.length, false);
    bonusCharges = 0;
    bonusLeft = 0;
    lightFactor = 1;
    _spawnTimer = config.trapInterval;
    _invulnerable = 0;
    _mercy = 0;
    _trail.clear();
    _recentClock = 0;
    _sentFrom = null;
    backLeft = 0;
    creatures = hazardsEnabled ? _spawnCreatures() : [];
    notifyListeners();
  }

  // ---- creatures --------------------------------------------------------

  /// Wolves and ghosts: asleep until a noise wakes them, and they lie down
  /// again when the ball stands still.
  bool get _wolfLike =>
      config.world == WorldKind.forest || config.world == WorldKind.graveyard;

  List<Creature> _spawnCreatures() {
    if (config.world != WorldKind.forest &&
        config.world != WorldKind.city &&
        config.world != WorldKind.graveyard) {
      return [];
    }
    final special = {maze.start, maze.goal, ...maze.buttonCells};
    // Spawn well away from the start.
    final cells = [
      for (var c = 1; c < maze.cellCount; c++)
        if (!special.contains(c) && (maze.cellCenter(c) - pos).distance > 6) c,
    ]..shuffle(_rnd);
    return [
      for (final c in cells.take(config.chaserCount))
        Creature(
          maze.cellCenter(c),
          cell: c,
          asleep: true,
          phase: _rnd.nextDouble() * 6,
        ),
    ];
  }

  // ---- simulation -------------------------------------------------------

  /// Advances the game by [dt] seconds. [tilt] is the tilt of the device as a
  /// vector with a length of at most 1 (screen axes: +x right, +y down).
  void update(double dt, Offset tilt) {
    if (status != GameStatus.playing) return;
    dt = min(dt, 1 / 30);
    if (scrolling) {
      _scroll(dt);
      return;
    }
    if (!started && tilt.distance > startTilt) started = true;
    if (started) elapsed += dt;
    if (config.ball == BallKind.chameleon) {
      if (started && (_mimicTimer -= dt) <= 0) {
        _mimicTimer = chameleonSeconds;
        _shiftChameleon();
      }
      var turn = (chameleonHue - chameleonShown) % 360;
      if (turn > 180) turn -= 360;
      chameleonShown = (chameleonShown + turn * min(1.0, dt * 5)) % 360;
    }

    if ((config.world == WorldKind.mountains || config.world == WorldKind.ocean) &&
        config.windEnabled &&
        hazardsEnabled &&
        started) {
      _updateWind(dt);
    }
    if (config.world == WorldKind.space && hazardsEnabled && started) {
      _updateGravity(dt);
    }
    final before = pos;
    _physics(dt, tilt);
    _roll(pos - before);
    _impactSound(dt);
    final breaksAt = ball.breaksAt;
    if (breaksAt != null) _trackStrain(dt, _impact / breaksAt);
    if (breaksAt != null && _impact >= breaksAt && status == GameStatus.playing) {
      _lose(mimicking == BallKind.bubble ? 'lose.bubble' : 'lose.glass');
    }
    _explore();
    _updateNoise(dt);
    _noiseBuzz(dt);
    _noiseCooldown -= dt;
    if (_impact >= loudImpact && _noiseCooldown <= 0) {
      _noiseCooldown = 0.4;
      noise(pos);
    }
    if (_invulnerable > 0) _invulnerable -= dt;
    if (_mercy > 0) _mercy -= dt;
    if (backLeft > 0) backLeft = max(0, backLeft - dt);
    if (noticeLeft > 0) noticeLeft -= dt;
    if (status == GameStatus.playing && started && (_recentClock += dt) >= 0.5) {
      _recentClock = 0;
      _trail.add(pos);
      if (_trail.length > 8) _trail.removeAt(0);
    }
    _buttons();
    _bonuses(dt);
    for (var i = 0; i < gateAnim.length; i++) {
      if (gateOpen[i] && gateAnim[i] < 1) gateAnim[i] = min(1, gateAnim[i] + dt / 0.7);
    }
    // Dangers wake up with the first tilt, not while the player is reading.
    if (hazardsEnabled && started) _hazards(dt);
    for (final b in bursts) {
      b.age += dt;
    }
    bursts.removeWhere((b) => b.age > 0.9);
    if (hintLeft > 0) {
      hintLeft -= dt;
      if (hintLeft <= 0) hintGate = -1;
    }
    camera = Offset.lerp(camera, pos, min(1, dt * 6))!;

    if (status == GameStatus.playing && maze.atGoal(pos)) {
      if (endless) {
        _nextStage();
      } else {
        status = GameStatus.won;
        _saveRecord();
      }
    }
    notifyListeners();
  }

  /// Endless mode: the centre was reached, so the next world begins. The clock
  /// keeps running across stages.
  void _nextStage() {
    final carried = elapsed;
    final left = maze;
    stage++;
    config = endlessConfig(stage, _pickBall(), world: _pickWorld());
    // The next maze starts right below the exit of this one.
    _nextStartCol = left is RectMaze ? left.goalCol : null;
    newMaze();
    _nextStartCol = null;
    elapsed = carried;
    _announceStage();
    prevMaze = left;
    transition = 0;
    pos = Offset(pos.dx, 0);
  }

  /// The ball rolls on into the next maze while the screen scrolls down to it.
  void _scroll(double dt) {
    transition = min(1, transition + dt / scrollSeconds);
    final end = maze.cellCenter(maze.start);
    final e = Curves.easeInOut.transform(transition);
    pos = Offset(end.dx, end.dy * e);
    if (transition >= 1) prevMaze = null;
    notifyListeners();
  }

  /// The grid, as (columns, rows), that fills a [width] x [height] area best:
  /// square cells, edge to edge, as little room left over as possible.
  static (int, int) gridFor(double width, double height) {
    var best = (endlessColsChoices.first, minEndlessRows);
    var bestLeft = double.infinity;
    for (final cols in endlessColsChoices) {
      final cell = width / (cols + RectMaze.padX);
      const pad = RectMaze.padTop + RectMaze.padBottom;
      final rows = ((height - pad * cell) / cell)
          .floor()
          .clamp(minEndlessRows, maxEndlessRows);
      final left = height - (rows + pad) * cell;
      if (left < bestLeft - 1e-6) {
        bestLeft = left;
        best = (cols, rows);
      }
    }
    return best;
  }

  /// Endless mode: use a grid of [cols] x [rows] cells from now on (what the
  /// screen has room for), and build a fresh maze that size if the run has not
  /// started yet.
  void fitGrid(int cols, int rows) {
    if (!endless || (cols == endlessCols && rows == endlessRows)) return;
    endlessCols = cols;
    endlessRows = rows;
    if (!started && stage == 0 && !scrolling) newMaze();
  }

  /// Endless mode: back to the first world with the clock at zero.
  void resetRun() {
    stage = 0;
    runContinues = 0;
    _recent.clear();
    config = endlessConfig(0, _pickBall(), world: _pickWorld());
    newMaze();
    _announceStage();
  }

  void _announceStage() {
    notice = 'notice.level';
    noticeArgs = {'n': stage + 1, 'world': tr('world.${config.world.name}.name')};
    noticeLeft = 2.5;
  }

  /// A bump against a wall makes a sound of the ball's material, louder the
  /// harder the hit. Brief cooldown, so sliding along a wall is not a rattle.
  void _impactSound(double dt) {
    _soundCooldown -= dt;
    if (_impact < impactSoundMin || _soundCooldown > 0) return;
    _soundCooldown = 0.1;
    final strength =
        ((_impact - impactSoundMin) / (impactSoundMax - impactSoundMin)).clamp(0.0, 1.0);
    Sfx.play(
      switch (config.ball) {
        BallKind.wood => Sound.impactWood,
        BallKind.steel => Sound.impactSteel,
        BallKind.rubber => Sound.impactRubber,
        BallKind.glass => Sound.impactGlass,
        BallKind.stone => Sound.impactStone,
        BallKind.slime => Sound.impactSlime,
        BallKind.paper => Sound.impactPaper,
        BallKind.bubble => Sound.impactBubble,
        // The same for every shape it takes, so the sound gives nothing away.
        BallKind.chameleon => Sound.impactWood,
      },
      volume: 0.15 + 0.85 * strength,
    );
    // Felt as well as heard: a faint tick for soft bumps, a firmer one for
    // hard hits (never the strong buzz).
    Haptics.play(strength > 0.55 ? Haptic.bump : Haptic.tick);
  }

  /// While the ball is loud, where noise matters (wolves and drones listen),
  /// a faint tick every so often reminds you with your hand, not only the bar.
  void _noiseBuzz(double dt) {
    _buzzCooldown -= dt;
    final matters = _wolfLike || config.world == WorldKind.city;
    if (!matters || noiseLevel < loudNoise || _buzzCooldown > 0) return;
    _buzzCooldown = 0.35;
    Haptics.play(Haptic.tick);
  }

  /// Louder when the creature is close to the ball.
  double _earshot(Offset at) => (1.1 - (at - pos).distance / 12).clamp(0.25, 1.0);

  /// Turns the ball by the distance it really moved (a ball pressed against
  /// a wall does not spin).
  void _roll(Offset moved) {
    ballRot = rollRot(ballRot, moved.dx, moved.dy, ballRadius);
    if (++_rollSteps % 120 == 0) ballRot = orthonormalize(ballRot);
  }

  /// Reveals the cells around the ball on the minimap.
  void _explore() {
    for (var c = 0; c < _centers.length; c++) {
      if (!explored[c] && (_centers[c] - pos).distance < exploreRadius) {
        explored[c] = true;
        exploredCount++;
      }
    }
  }

  MudPatch? _patchAt() {
    if (ball.floats) return null;
    for (final m in mud) {
      if ((m.pos - pos).distance < m.radius + 0.1) return m;
    }
    return null;
  }

  // ---- spaceship --------------------------------------------------------

  /// Gravity pulls at the ball while the run is on, unless the stabilizer is.
  bool get gravityActive =>
      config.world == WorldKind.space &&
      hazardsEnabled &&
      started &&
      bonusLeft <= 0;

  void _resetGravity() {
    // Only the spaceship draws random numbers here, so other worlds keep
    // their seeded layouts.
    gravityDir = config.world == WorldKind.space ? _randomAxis(null) : const Offset(0, 1);
    gravityNext = gravityDir;
    gravityWarnLeft = 0;
    _gravityTimer = config.gravityInterval;
  }

  /// One of the four straight directions, never [not].
  Offset _randomAxis(Offset? not) {
    const axes = [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)];
    final options = [
      for (final a in axes)
        if (a != not) a,
    ];
    return options[_rnd.nextInt(options.length)];
  }

  void _updateGravity(double dt) {
    if (gravityWarnLeft > 0) {
      gravityWarnLeft -= dt;
      if (gravityWarnLeft <= 0) {
        gravityDir = gravityNext;
        _gravityTimer = config.gravityInterval;
      }
      return;
    }
    _gravityTimer -= dt;
    if (_gravityTimer <= 0) {
      gravityNext = _randomAxis(gravityDir);
      gravityWarnLeft = gravityWarning;
      notice = 'notice.gravity';
      noticeArgs = const {};
      noticeLeft = gravityWarning;
    }
  }

  /// Where a laser is in its cycle: 0 dark, 1 warning, 2 burning.
  int laserPhase(Laser l) {
    final period = config.laserPeriod;
    final t = (_spaceClock + l.phase) % period;
    if (t >= period - laserBeam) return 2;
    if (t >= period - laserBeam - laserWarning) return 1;
    return 0;
  }

  bool laserOn(Laser l) => laserPhase(l) == 2;

  /// Whether the ball is in the way of a laser's beam, wall to wall.
  bool _inBeam(Laser l) {
    final d = pos - l.center;
    final along = d.dx * l.along.dx + d.dy * l.along.dy;
    final across = d.dx * -l.along.dy + d.dy * l.along.dx;
    return along.abs() < 0.1 + ballRadius * 0.6 && across.abs() < 0.6;
  }

  /// Which way the camera looks now, in radians.
  double cameraAngle(SecurityCamera c) =>
      c.base + cameraSweep * sin(2 * pi * (_spaceClock + c.phase) / config.cameraPeriod);

  /// Whether the ball is in the camera's view: near enough, inside the cone
  /// and with no wall in between.
  bool cameraSees(SecurityCamera c) {
    final v = pos - c.pos;
    if (v.distance > cameraRange) return false;
    var diff = (v.direction - cameraAngle(c)) % kTwoPi;
    if (diff > pi) diff -= kTwoPi;
    if (diff.abs() > cameraHalfAngle) return false;
    return _lineClear(c.pos, pos);
  }

  /// How far a ray from [from] along [angle] gets before a wall stops it
  /// (at most [range]); the view cones are drawn with this.
  double sightDistance(Offset from, double angle, double range) {
    final end = from + polar(range, angle);
    var best = range;
    for (final s in maze.segmentsAlong(from, end)) {
      if (s.gate >= 0 && gateOpen[s.gate]) continue;
      final r = end - from;
      final q = s.b - s.a;
      final denom = r.dx * q.dy - r.dy * q.dx;
      if (denom.abs() < 1e-9) continue;
      final w = s.a - from;
      final t = (w.dx * q.dy - w.dy * q.dx) / denom;
      final u = (w.dx * r.dy - w.dy * r.dx) / denom;
      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) best = min(best, t * range);
    }
    return best;
  }

  /// Where an airlock is in its cycle: 0 open, 1 about to shut, 2 shut.
  int airlockPhase(Airlock a) {
    final t = (_spaceClock + a.phase) % airlockCycle;
    if (t < airlockOpen) return 0;
    if (t < airlockOpen + airlockWarning) return 1;
    return 2;
  }

  bool airlockClosed(Airlock a) => airlockPhase(a) == 2;

  void _updateWind(double dt) {
    if (windLeft > 0) {
      windLeft -= dt;
      if (windLeft <= 0) _windTimer = 6 + _rnd.nextDouble() * 4;
      return;
    }
    if (windWarnLeft > 0) {
      windWarnLeft -= dt;
      if (windWarnLeft <= 0) windLeft = windDuration;
      return;
    }
    _windTimer -= dt;
    if (_windTimer <= 0) {
      final a = _rnd.nextInt(8) * pi / 4;
      windDir = Offset(cos(a), sin(a));
      windWarnLeft = windWarning;
      notice = config.world == WorldKind.ocean ? 'notice.current' : 'notice.wind';
      noticeArgs = const {};
      noticeLeft = windWarning;
    }
  }

  void _physics(double dt, Offset tilt) {
    _impact = 0;
    final patch = _patchAt();
    final muddy = patch != null;
    // A gentler response at small tilts, so a slow sneak is possible.
    final tiltPower = tilt.distance;
    final eased = tiltPower < 1e-6 ? Offset.zero : tilt * pow(tiltPower, 0.6).toDouble();
    vel += eased * (_accel * ball.accel * dt);
    if (windLeft > 0 && !(config.world == WorldKind.ocean && bonusLeft > 0)) {
      vel += windDir * (config.windStrength * (1 - ball.windResist) * dt);
    }
    if (gravityActive) vel += gravityDir * (config.gravityStrength * dt);
    if (config.world == WorldKind.volcano && hazardsEnabled && started) {
      vel += _steamPush() * dt;
    }
    if (config.world == WorldKind.factory && hazardsEnabled && started) {
      vel += _factoryPull() * dt;
    }

    if (config.world == WorldKind.mud) {
      final boggy = patch != null && bonusLeft <= 0;
      if (boggy) {
        // The bog pulls the ball to its middle; stuck there, it sinks.
        vel += (patch.pos - pos) * (7 * (1 - ball.bogResist) * dt);
        sink += dt /
            config.bogSeconds *
            (1 - ball.bogResist * 0.6) *
            (vel.distance < 1.1 ? 1.0 : 0.35);
      } else {
        sink = max(0, sink - dt * 0.8);
      }
      if (sink >= 1) _lose('lose.bog');
    }

    // Cold fog drags at the ball, though it never stops it.
    final cold = !ball.floats && fog.any((f) => (f.pos - pos).distance < f.radius);
    final sticky = !ball.floats && goos.any(_underGoo);
    vel *= exp(-(muddy ? 7.0 : sticky ? 6.5 : cold ? 4.2 : 1.7 * ball.damping) * dt);
    final cap = muddy
        ? 1.8
        : sticky
            ? 1.3
            : _maxSpeed * ball.maxSpeed * (cold ? 0.5 : 1.0);
    if (vel.distance > cap) vel = vel / vel.distance * cap;

    final steps = max(1, (vel.distance * dt / 0.07).ceil());
    _touchingWall = false;
    for (var i = 0; i < steps; i++) {
      pos += vel * (dt / steps);
      _collide();
    }
    // A sticky ball clings to the wall it is up against.
    if (_touchingWall && ball.stick > 0) vel *= exp(-ball.stick * dt);
  }

  /// The walls around the ball, with the airlock doors that are shut.
  Iterable<Seg> _wallsNear() {
    final walls = maze.segmentsNear(pos);
    if (airlocks.isEmpty && doors.isEmpty && worms.isEmpty) return walls;
    return [
      ...walls,
      for (final a in airlocks)
        if (airlockClosed(a)) a.seg,
      for (final w in worms)
        if (wormPhase(w) == 2) w.seg,
      for (final d in doors)
        if (d.state == 2) ...d.segs,
    ];
  }

  void _collide() {
    final reach = ballRadius + PolarMaze.wallHalf;
    for (var iter = 0; iter < 2; iter++) {
      for (final s in _wallsNear()) {
        if (s.gate >= 0 && gateOpen[s.gate]) continue;
        final ab = s.b - s.a;
        final t = (((pos - s.a).dx * ab.dx + (pos - s.a).dy * ab.dy) /
                (ab.dx * ab.dx + ab.dy * ab.dy))
            .clamp(0.0, 1.0);
        final q = s.a + ab * t;
        final d = pos - q;
        final dist = d.distance;
        if (dist < reach + touchMargin) _touchingWall = true;
        if (dist >= reach) continue;
        final n = dist < 1e-6 ? Offset(-ab.dy, ab.dx) / ab.distance : d / dist;
        pos = q + n * reach;
        final vn = vel.dx * n.dx + vel.dy * n.dy;
        if (vn < 0) {
          final bounce = ball.bounce + (config.world == WorldKind.candy ? candyBounce : 0);
          vel -= n * (vn * (1 + bounce));
          _impact = max(_impact, -vn);
        }
      }
    }
    // Landed boulders are solid until they crumble away.
    if (config.world == WorldKind.mountains) {
      final reachRock = rubbleRadius + ballRadius;
      for (final h in hazards) {
        if (!h.armed) continue;
        final d = pos - h.pos;
        final dist = d.distance;
        if (dist >= reachRock) continue;
        final n = dist < 1e-6 ? const Offset(1, 0) : d / dist;
        pos = h.pos + n * reachRock;
        final vn = vel.dx * n.dx + vel.dy * n.dy;
        if (vn < 0) {
          vel -= n * (vn * (1 + ball.bounce));
          _impact = max(_impact, -vn);
        }
      }
    }
    // Soft limit around the maze so the ball cannot wander off outside.
    final out = maze.constrain(pos, ballRadius);
    if (out != null) {
      final (inside, n) = out;
      pos = inside;
      final vn = vel.dx * n.dx + vel.dy * n.dy;
      if (vn > 0) vel -= n * vn;
    }
  }

  void _bonuses(double dt) {
    for (var i = 0; i < bonusCells.length; i++) {
      if (bonusTaken[i]) continue;
      if ((maze.cellCenter(bonusCells[i]) - pos).distance < 0.5) {
        bonusTaken[i] = true;
        bonusCharges += usesPerBonus;
        bursts.add(Burst(maze.cellCenter(bonusCells[i]), 2));
        notice = 'notice.bonus';
        noticeArgs = {'n': usesPerBonus, 'name': bonusName(config.world)};
        noticeLeft = 2.2;
      }
    }
    if (bonusLeft > 0) bonusLeft = max(0, bonusLeft - dt);
    final target =
        config.world == WorldKind.underground && bonusLeft > 0 ? lightBoostFactor : 1.0;
    lightFactor += (target - lightFactor) * min(1.0, dt * 3);
  }

  /// Spends one use of the collected bonus: wolves / drones fall asleep,
  /// traps / boulders are switched off, or the underground light grows.
  void useBonus() {
    if (status != GameStatus.playing || bonusCharges <= 0 || bonusLeft > 0) {
      return;
    }
    bonusCharges--;
    bonusLeft = bonusDuration;
    bursts.add(Burst(pos, 0));
    switch (config.world) {
      case WorldKind.forest:
      case WorldKind.city:
        for (final c in creatures) {
          c.asleep = true;
          c.lockLeft = bonusDuration;
          c.route.clear();
          c.target = -1;
          c.searchLeft = 0;
          c.alert = 0;
        }
      case WorldKind.mud:
      case WorldKind.mountains:
      case WorldKind.volcano:
        hazards.clear();
      case WorldKind.graveyard:
        // Holy water: every ghost is awake and driven off for the duration.
        for (final g in creatures) {
          g.asleep = false;
          g.lockLeft = bonusDuration;
          g.grace = 0;
          g.calm = 0;
          g.awakeTimer = 12;
        }
      case WorldKind.underground:
      case WorldKind.space:
      case WorldKind.glass:
      case WorldKind.ocean:
      case WorldKind.factory:
      case WorldKind.candy:
      case WorldKind.shifting:
        break; // the light, the stabilizer and the prism work through [bonusLeft]
    }
    notifyListeners();
  }

  static String bonusKey(WorldKind w) => 'bonus.${w.name}';

  /// The bonus name in the current language.
  static String bonusName(WorldKind w) => tr(bonusKey(w));

  void _buttons() {
    for (var j = 0; j < maze.gateCount; j++) {
      if (buttonUsed[j]) continue;
      final c = maze.cellCenter(maze.buttonCells[j]);
      if ((c - pos).distance < 0.5) {
        buttonUsed[j] = true;
        gateOpen[j] = true;
        bursts.add(Burst(c, 0));
        bursts.add(Burst(maze.gateCenter(j), 2));
        hintGate = j;
        hintLeft = 2.5;
      }
    }
  }

  /// A second chance after losing: the ball is back where it stood about
  /// three seconds before the end (or at the start), the dangers around it
  /// start over and nothing can end the game for a few seconds. As often as
  /// [GameConfig.continueCount] allows per maze; false when it is not possible.
  bool continueAfterLoss() {
    if (status != GameStatus.lost || continuesLeft <= 0) return false;
    continuesUsed++;
    runContinues++;
    status = GameStatus.playing;
    lostReason = '';
    pos = _trail.length >= 6 ? _trail[_trail.length - 6] : maze.cellCenter(maze.start);
    vel = Offset.zero;
    camera = pos;
    sink = 0;
    strain = 0;
    _strainHold = 0;
    stillTime = 0;
    hazards = [];
    cracks = [];
    beams = [];
    creatures = hazardsEnabled ? _spawnCreatures() : [];
    _mercy = 3;
    _invulnerable = 3;
    _trail.clear();
    notifyListeners();
    return true;
  }

  static const double returnOffer = 5;

  void _offerReturn() {
    _sentFrom = pos;
    backLeft = returnOffer;
  }

  /// A rewarded ad puts the ball back where it was before it was sent to the
  /// start, with a few seconds of safety.
  void returnToSpot() {
    final from = _sentFrom;
    if (backLeft <= 0 || from == null || status != GameStatus.playing) return;
    pos = from;
    vel = Offset.zero;
    camera = pos;
    _invulnerable = 3;
    backLeft = 0;
    _sentFrom = null;
    notifyListeners();
  }

  /// A rewarded ad gave one more use of the bonus.
  void grantBonusCharge() {
    bonusCharges++;
    notifyListeners();
  }

  void _lose(String reason) {
    if (status != GameStatus.playing || _mercy > 0) return;
    status = GameStatus.lost;
    lostReason = reason;
    bursts.add(Burst(pos, 1));
    if (endless && stage > 0) _saveEndlessRecord();
  }

  Future<void> _saveEndlessRecord() async {
    final rank = await EndlessRecordStore.add(EndlessRecord(
      mazes: stage,
      millis: (elapsed * 1000).round(),
      playedAt: DateTime.now(),
    ));
    if (_disposed) return;
    recordRank = rank;
    notifyListeners();
  }

  Future<void> _saveRecord() async {
    final entry = RecordEntry(
      world: config.world,
      level: config.level,
      millis: (elapsed * 1000).round(),
      playedAt: DateTime.now(),
    );
    final rank = await RecordStore.add(entry);
    if (_disposed) return;
    recordRank = rank;
    notifyListeners();
  }

  // ---- hazards ----------------------------------------------------------

  bool _passable(int e) => maze.passable(e, gateOpen);

  void _updateNoise(double dt) {
    final speed = vel.distance;
    final fromSpeed = ((speed - quietSpeed) / (loudSpeed - quietSpeed)).clamp(0.0, 1.0);
    _impactNoise = max(0, _impactNoise - dt * 1.8);
    if (_impact > 1.0) _impactNoise = max(_impactNoise, (_impact / 4.0).clamp(0.0, 1.0));
    final target = forcedNoise ??
        (max(fromSpeed, _impactNoise) * ball.noise).clamp(0.0, 1.0);
    // Fast attack, slow release, so the meter is easy to read.
    noiseLevel = target > noiseLevel ? target : max(target, noiseLevel - dt * 1.5);
    stillTime = forcedStill ?? (speed < 0.35 ? stillTime + dt : 0);
  }

  /// Sleeping wolves and drones wake when the ball is loud enough to be heard
  /// where they lie; awake drones turn towards the sound.
  void _listen(double dt) {
    final radius = hearingRadius;
    for (final c in creatures) {
      if (c.lockLeft > 0) {
        c.hearing = 0;
        continue;
      }
      final heard = radius > 0 && (c.pos - pos).distance <= radius;
      c.hearing = heard ? c.hearing + dt * (1 + noiseLevel * 2) : max(0, c.hearing - dt * 2);
      if (c.hearing < wakeAfter) continue;
      if (_wolfLike) {
        if (c.asleep) _wake(c);
      } else if (c.asleep || !c.searching) {
        _alertDrone(c, pos);
        c.hearing = 0;
      }
    }
  }

  /// A loud bump at [at]: sleeping wolves within earshot wake up, and drones
  /// (asleep or not) come to look at the spot.
  void noise(Offset at) {
    if (!_wolfLike && config.world != WorldKind.city) return;
    bursts.add(Burst(at, 3));
    for (final c in creatures) {
      if (c.lockLeft > 0 || (c.pos - at).distance > noiseRadius) continue;
      if (_wolfLike) {
        if (c.asleep) _wake(c);
      } else {
        _alertDrone(c, at);
      }
    }
  }

  void _wake(Creature w) {
    if (w.asleep) {
      final cry = config.world == WorldKind.graveyard ? Sound.ghostWake : Sound.wolfWake;
      Sfx.play(cry, volume: _earshot(w.pos));
    }
    w.asleep = false;
    w.grace = 0.9;
    w.awakeTimer = 12 + _rnd.nextDouble() * 8;
  }

  void _alertDrone(Creature d, Offset at) {
    if (d.asleep) Sfx.play(Sound.droneWake, volume: _earshot(d.pos));
    d.asleep = false;
    d.grace = 0.7;
    d.awakeTimer = 16 + _rnd.nextDouble() * 8;
    d.searchLeft = 0;
    d.route.clear();
    final from = maze.cellAt(d.pos);
    final to = maze.cellAt(at);
    final p = maze.path(from, to, gateOpen);
    d.cell = from;
    if (p == null) {
      d.target = -1;
      d.searchLeft = 3;
    } else {
      d.target = to;
      d.route.addAll(maze.routePoints(p).skip(1));
    }
  }

  void _hazards(double dt) {
    final speed = config.chaserSpeed;
    for (final c in creatures) {
      if (c.lockLeft > 0) c.lockLeft -= dt;
    }
    if (bonusLeft > 0 &&
        (config.world == WorldKind.mud || config.world == WorldKind.mountains)) {
      hazards.clear(); // switched off by the bonus
      return;
    }
    if (_wolfLike || config.world == WorldKind.city) {
      _listen(dt);
    }
    switch (config.world) {
      case WorldKind.forest:
        for (final w in creatures) {
          if (w.asleep) continue;
          if (w.grace > 0) {
            w.grace -= dt;
            continue;
          }
          // The ball froze: the wolf loses interest, then lies down.
          if (stillTime >= stillBeforeBored) {
            w.calm += dt;
            w.route.clear();
            if (w.calm >= boredBeforeSleep) {
              w.asleep = true;
              w.calm = 0;
            }
            continue;
          }
          w.calm = 0;
          _followPath(w, dt, speed);
          if ((w.pos - pos).distance < 0.45) {
            _lose('lose.wolf');
            break;
          }
          // Tired wolves lie down again once the ball is far away.
          w.awakeTimer -= dt;
          if (w.awakeTimer <= 0 && (w.pos - pos).distance > 5) {
            w.asleep = true;
            w.route.clear();
          }
        }
      case WorldKind.city:
        for (final d in creatures) {
          d.age += dt;
          if (d.asleep) {
            d.alert = 0;
            continue;
          }
          // The ball froze: the drone gives up, stops looking and lands.
          if (d.grace <= 0 && stillTime >= stillBeforeBored) {
            d.calm += dt;
            d.route.clear();
            d.target = -1;
            d.searchLeft = 0;
            d.alert = 0;
            d.cell = maze.cellAt(d.pos);
            d.prevCell = -1;
            if (d.calm >= boredBeforeSleep) {
              d.asleep = true;
              d.calm = 0;
            }
            continue;
          }
          d.calm = 0;
          if (d.grace > 0) {
            d.grace -= dt;
          } else if (d.target >= 0) {
            _walk(d, dt, speed * 1.3);
            if (d.route.isEmpty) {
              d.cell = d.target;
              d.prevCell = -1;
              d.target = -1;
              d.searchLeft = 3;
            }
          } else if (d.searchLeft > 0) {
            d.searchLeft -= dt;
          } else {
            _patrol(d, dt, speed * 1.2);
          }
          if (d.searching) {
            // Scan all the way around.
            d.viewAngle += dt * 2.4;
          } else {
            d.viewAngle = d.angle + 0.45 * sin(d.age * 1.4 + d.phase);
          }
          if (_invulnerable > 0) {
            d.alert = 0;
            continue;
          }
          if (droneSees(d)) {
            d.alert += dt;
          } else {
            d.alert = max(0, d.alert - dt * 1.5);
          }
          if (d.alert >= droneReaction || (d.pos - pos).distance < 0.4) {
            caughtByDrone();
            break;
          }
          // Tired drones land and sleep once the ball is far away.
          d.awakeTimer -= dt;
          if (!d.searching &&
              d.awakeTimer <= 0 &&
              (d.pos - pos).distance > 5) {
            d.asleep = true;
            d.route.clear();
          }
        }
      case WorldKind.glass:
        _updateGlass(dt);
      case WorldKind.ocean:
        _updateJellies(dt);
      case WorldKind.candy:
        _candyClock += dt;
        _updateJellies(dt);
      case WorldKind.volcano:
        _updateVolcano(dt);
      case WorldKind.factory:
        _updateFactory(dt);
      case WorldKind.shifting:
        _updateDoors(dt);
      case WorldKind.graveyard:
        for (final g in creatures) {
          if (g.lockLeft > 0) {
            // Holy water: the ghosts shrink away from the ball.
            final away = g.pos - pos;
            final d = away.distance;
            final dir = d < 1e-6 ? const Offset(1, 0) : away / d;
            g.pos = maze.clampInside(g.pos + dir * (speed * 1.8 * dt));
            g.angle = dir.direction;
            continue;
          }
          if (g.asleep) continue;
          if (g.grace > 0) {
            g.grace -= dt;
            continue;
          }
          // The ball froze: the ghost freezes with it, then fades into its grave.
          if (stillTime > 0) {
            if (stillTime >= ghostSleepAfter) g.asleep = true;
            continue;
          }
          // Straight at the ball, through the walls, as fast as the ball rolls.
          final to = pos - g.pos;
          final d = to.distance;
          if (d > 1e-6) {
            g.pos += to / d * min(d, vel.distance * dt);
            g.angle = to.direction;
          }
          if ((g.pos - pos).distance < 0.4) {
            _lose('lose.ghost');
            break;
          }
          // Tired ghosts drift off to sleep once the ball is far away.
          g.awakeTimer -= dt;
          if (g.awakeTimer <= 0 && (g.pos - pos).distance > 5) g.asleep = true;
        }
      case WorldKind.space:
        _spaceClock += dt;
        for (final l in lasers) {
          if (laserOn(l) && _inBeam(l)) {
            _lose('lose.laser');
            break;
          }
        }
        for (final cam in cameras) {
          if (status != GameStatus.playing) break;
          cam.alert = cameraSees(cam)
              ? cam.alert + dt
              : max(0, cam.alert - dt * 1.5);
          if (cam.alert >= cameraReaction) _lose('lose.camera');
        }
      case WorldKind.underground:
      case WorldKind.mud:
      case WorldKind.mountains:
        break;
    }

    // Timed dangers.
    if (config.world == WorldKind.volcano && bonusLeft > 0) hazards.clear();
    for (final h in hazards) {
      final wasArmed = h.armed;
      h.age += dt;
      if (config.world == WorldKind.volcano) {
        // The bomb blasts where it lands, then burns where it fell.
        if (!wasArmed && h.armed) {
          bursts.add(Burst(h.pos, 1));
          if ((h.pos - pos).distance < h.radius) _lose('lose.bomb');
        } else if (h.armed && (h.pos - pos).distance < bombFire) {
          _lose('lose.bomb');
        }
      } else if (config.world == WorldKind.mountains) {
        // The boulder crashes down the moment it becomes armed.
        if (!wasArmed && h.armed) {
          bursts.add(Burst(h.pos, 1));
          if ((h.pos - pos).distance < h.radius + 0.1) _lose('lose.rock');
        }
      } else if (h.armed && (h.pos - pos).distance < h.radius) {
        _lose(config.world == WorldKind.graveyard ? 'lose.grave' : 'lose.trap');
      }
    }
    hazards.removeWhere((h) => h.age > h.life);

    if (config.world == WorldKind.mud ||
        config.world == WorldKind.mountains ||
        config.world == WorldKind.graveyard ||
        config.world == WorldKind.volcano) {
      final bombs = config.world == WorldKind.volcano;
      if (bombs && bonusLeft > 0) return;
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnTimer = config.trapInterval *
            (config.world == WorldKind.mountains ? 1.2 : bombs ? 1.3 : 1.0);
        for (var i = 0; i < (bombs ? config.bombCount : config.trapCount); i++) {
          _spawnHazard(i);
        }
      }
    }
  }

  // ---- factory ----------------------------------------------------------

  /// Which way a belt runs now: 1 along its direction, -1 against it, 0 while
  /// the emergency stop holds.
  int beltDir(Belt b) {
    if (bonusLeft > 0) return 0;
    return ((_factoryClock + b.phase) / config.beltPeriod).floor().isEven ? 1 : -1;
  }

  /// A belt is about to reverse.
  bool beltReversing(Belt b) {
    if (bonusLeft > 0) return false;
    return (_factoryClock + b.phase) % config.beltPeriod > config.beltPeriod - beltWarning;
  }

  /// Which way a turntable spins the floor: 1 clockwise on the screen, -1 the
  /// other way, 0 while the emergency stop holds.
  int turntableDir(Turntable t) {
    if (bonusLeft > 0) return 0;
    return ((_factoryClock + t.phase) / config.beltPeriod).floor().isEven ? 1 : -1;
  }

  /// A turntable is about to reverse.
  bool turntableReversing(Turntable t) {
    if (bonusLeft > 0) return false;
    return (_factoryClock + t.phase) % config.beltPeriod > config.beltPeriod - beltWarning;
  }

  /// How far across the corridor a wrecking ball is, -[pendulumSwing] to
  /// [pendulumSwing]. With the emergency stop it hangs at one end, out of the
  /// way.
  double pendulumAcross(Pendulum p) {
    if (bonusLeft > 0) return pendulumSwing;
    return pendulumSwing * sin(2 * pi * (_factoryClock + p.phase) / config.pendulumPeriod);
  }

  Offset pendulumBobAt(Pendulum p) =>
      p.center + Offset(-p.along.dy, p.along.dx) * pendulumAcross(p);

  /// Where a press is: 2 slamming, 1 coming down, 0 raised.
  int pressPhase(Press p) {
    if (bonusLeft > 0) return 0;
    final period = config.pressPeriod;
    final t = (_factoryClock + p.phase) % period;
    if (t >= period - pressSlam) return 2;
    if (t >= period - pressSlam - pressWarning) return 1;
    return 0;
  }

  /// Where a magnet is: 2 on, 1 about to switch on, 0 off.
  int magnetPhase(Magnet m) {
    if (bonusLeft > 0) return 0;
    final period = config.magnetPeriod;
    final t = (_factoryClock + m.phase) % period;
    if (t < magnetOnSeconds) return 2;
    if (t >= period - magnetWarning) return 1;
    return 0;
  }

  bool _inZone(Offset center, Offset along, double halfAlong, double halfAcross) {
    final d = pos - center;
    final a = d.dx * along.dx + d.dy * along.dy;
    final c = d.dx * -along.dy + d.dy * along.dx;
    return a.abs() < halfAlong && c.abs() < halfAcross;
  }

  /// What the belts carry the ball along with, and the magnets pull it to.
  Offset _factoryPull() {
    var pull = Offset.zero;
    for (final b in belts) {
      final dir = beltDir(b);
      if (dir != 0 && _inZone(b.center, b.along, 0.5, 0.45)) {
        pull += b.along * (beltForce * dir);
      }
    }
    for (final t in turntables) {
      final dir = turntableDir(t);
      final d = pos - t.pos;
      final r = d.distance;
      if (dir != 0 && r < turntableReach && r > 1e-6) {
        pull += Offset(-d.dy, d.dx) / r * (turntableForce * dir);
      }
    }
    if (ball.magnetic > 0) {
      for (final m in magnets) {
        if (magnetPhase(m) != 2) continue;
        final to = m.pos - pos;
        final d = to.distance;
        if (d >= magnetReach || d < 1e-6) continue;
        pull += to / d * (magnetForce * (1 - d / magnetReach) * ball.magnetic);
      }
    }
    return pull;
  }

  void _updateFactory(double dt) {
    _factoryClock += dt;
    for (final p in presses) {
      if (pressPhase(p) == 2 && _inZone(p.center, p.along, 0.3 + ballRadius * 0.3, 0.6)) {
        _lose('lose.press');
        return;
      }
    }
    // A wrecking ball knocks the ball back to the start.
    if (_invulnerable <= 0) {
      for (final p in pendulums) {
        if ((pendulumBobAt(p) - pos).distance < pendulumBob + ballRadius * 0.6) {
          _sendBack('notice.pendulum');
          return;
        }
      }
    }
  }

  // ---- candy ------------------------------------------------------------

  /// Whether a patch is sticky now: caramel always, chocolate while it is
  /// melted, nothing while the mint holds.
  bool gooSticky(Goo g) =>
      bonusLeft <= 0 && (!g.melts || (_candyClock + g.phase) % gooPeriod < gooMelted);

  /// Where a worm is: 2 out across the corridor, 1 stirring under the floor,
  /// 0 gone (always, while the mint lasts).
  int wormPhase(Worm w) {
    if (bonusLeft > 0) return 0;
    final period = config.wormPeriod;
    final t = (_candyClock + w.phase) % period;
    if (t >= period - wormOut) return 2;
    if (t >= period - wormOut - wormWarning) return 1;
    return 0;
  }

  bool _underGoo(Goo g) => (g.pos - pos).distance < g.radius + 0.1 && gooSticky(g);

  // ---- shifting maze ----------------------------------------------------

  /// Whether the maze can still be finished from where the ball stands with
  /// the doors in [closed] shut for good: walk everywhere that can be reached,
  /// press every button found, and see whether the way to the exit is open.
  bool _canFinish(Set<int> closed) {
    final open = List<bool>.of(gateOpen);
    final from = maze.cellAt(pos);
    while (true) {
      final seen = reachable(
          maze, [from], (e) => maze.passable(e, open) && !closed.contains(e));
      if (seen.contains(maze.goal)) return true;
      var more = false;
      for (var j = 0; j < open.length; j++) {
        if (!open[j] && seen.contains(maze.buttonCells[j])) {
          open[j] = true;
          more = true;
        }
      }
      if (!more) return false;
    }
  }

  /// Vision: while the bonus lasts, every shifting wall shows its outline and
  /// counts down to its next change.
  bool get doorsRevealed => config.world == WorldKind.shifting && bonusLeft > 0;

  /// Tests: whether the maze can still be finished with the doors as they are.
  @visibleForTesting
  bool canFinishForTest() =>
      _canFinish({for (final d in doors) if (d.state == 2) d.edge});

  /// A door may shut only when the ball is well clear of it and the maze
  /// stays finishable even if every shut door stayed shut for ever.
  bool _canClose(ShiftDoor d) {
    for (final s in d.segs) {
      final ab = s.b - s.a;
      final t = (((pos - s.a).dx * ab.dx + (pos - s.a).dy * ab.dy) /
              (ab.dx * ab.dx + ab.dy * ab.dy))
          .clamp(0.0, 1.0);
      if ((pos - (s.a + ab * t)).distance < ballRadius + 0.6) return false;
    }
    final closed = {
      for (final o in doors)
        if (o.state == 2) o.edge,
      d.edge,
    };
    return _canFinish(closed);
  }

  void _updateDoors(double dt) {
    for (final d in doors) {
      final to = d.state == 2 ? 1.0 : 0.0;
      d.shown += (to - d.shown).clamp(-dt / 0.35, dt / 0.35);
    }
    for (final d in doors) {
      d.timer -= dt;
      if (d.timer > 0) continue;
      switch (d.state) {
        case 0:
          // Only doors that can really shut give a warning.
          if (_canClose(d)) {
            d.state = 1;
            d.timer = doorWarning;
          } else {
            d.timer = 0.8 + _rnd.nextDouble();
          }
        case 1:
          if (_canClose(d)) {
            d.state = 2;
            d.timer = config.doorClosedSeconds * (0.8 + 0.4 * _rnd.nextDouble());
          } else {
            // The ball came too close, or the way would be cut: it stays open.
            d.state = 0;
            d.timer = 0.8 + _rnd.nextDouble();
          }
        default:
          d.state = 0;
          d.timer = config.doorOpenSeconds * (0.7 + 0.6 * _rnd.nextDouble());
      }
    }
  }

  // ---- volcano ----------------------------------------------------------

  /// Where a lava river is in its cycle: 2 molten, 1 about to flood, 0 crusted
  /// over (always, while the cooling bonus lasts).
  int lavaPhase(LavaFlow l) {
    if (bonusLeft > 0) return 0;
    final t = lavaTime(l);
    if (t < config.lavaMolten) return 2;
    if (t >= config.lavaPeriod - lavaWarning) return 1;
    return 0;
  }

  /// Seconds into the river's cycle: molten at the start, then cooling.
  double lavaTime(LavaFlow l) => (_volcanoClock + l.phase) % config.lavaPeriod;

  /// Where a geyser is: 2 erupting, 1 hissing before it, 0 quiet.
  int geyserPhase(Geyser g) {
    if (bonusLeft > 0) return 0;
    final t = geyserTime(g);
    if (t >= config.geyserPeriod - geyserBurst) return 2;
    if (t >= config.geyserPeriod - geyserBurst - geyserWarning) return 1;
    return 0;
  }

  double geyserTime(Geyser g) => (_volcanoClock + g.phase) % config.geyserPeriod;

  /// How far a geyser is through its hissing or eruption, 0 to 1.
  double geyserProgress(Geyser g) {
    final t = geyserTime(g);
    final burstAt = config.geyserPeriod - geyserBurst;
    return geyserPhase(g) == 2
        ? ((t - burstAt) / geyserBurst).clamp(0.0, 1.0)
        : ((t - (burstAt - geyserWarning)) / geyserWarning).clamp(0.0, 1.0);
  }

  bool _inLava(LavaFlow l) {
    final d = pos - l.center;
    final along = d.dx * l.along.dx + d.dy * l.along.dy;
    final across = d.dx * -l.along.dy + d.dy * l.along.dx;
    return along.abs() < lavaLength && across.abs() < lavaWidth;
  }

  /// The jets of erupting geysers shove the ball away; lighter balls more.
  Offset _steamPush() {
    var push = Offset.zero;
    for (final g in geysers) {
      if (geyserPhase(g) != 2) continue;
      final away = pos - g.pos;
      final d = away.distance;
      if (d >= geyserReach) continue;
      final dir = d < 1e-6 ? const Offset(1, 0) : away / d;
      push += dir * (geyserForce * (1 - d / geyserReach) * (1 - ball.windResist));
    }
    return push;
  }

  void _updateVolcano(double dt) {
    _volcanoClock += dt;
    final shielded = bonusLeft > 0;
    if (!shielded) {
      for (final l in lavas) {
        if (lavaPhase(l) == 2 && _inLava(l)) {
          _lose('lose.lava');
          return;
        }
      }
      for (final g in geysers) {
        if (geyserPhase(g) == 2 && (g.pos - pos).distance < geyserScald) {
          _lose('lose.steam');
          return;
        }
      }
    }
    // Thin crust gives way under a ball that dawdles on it, and mends slowly
    // once the ball moves on.
    final slow = !shielded && !ball.floats && vel.distance < crustSpeed;
    for (final k in crusts) {
      if (slow && (k.pos - pos).distance < crustRadius) {
        k.level += dt / config.crustSeconds;
      } else {
        k.level = max(0, k.level - dt * 0.5);
      }
      if (k.level >= 1) {
        _lose('lose.crust');
        return;
      }
    }
  }

  // ---- glass ------------------------------------------------------------

  void _updateJellies(double dt) {
    // The anchor holds everything still.
    if (bonusLeft > 0) return;
    for (final j in jellies) {
      if (j.path.isEmpty) _planPatrol(j);
      if (j.path.length > 1) _swim(j, dt);
      if (_invulnerable > 0 || status != GameStatus.playing) continue;
      if ((j.pos - pos).distance < jellyReach && _lineClear(j.pos, pos)) {
        caughtByJelly();
        return;
      }
    }
  }

  /// A patrol of 5 to 9 cells from where the jellyfish starts; it swims there
  /// and back again for good.
  void _planPatrol(Jellyfish j) {
    final from = maze.cellAt(j.home);
    final targets = [for (var c = 0; c < maze.cellCount; c++) c]..shuffle(_rnd);
    List<int>? best;
    for (final c in targets) {
      final p = maze.path(from, c, gateOpen);
      if (p == null) continue;
      if (p.length >= 5 && p.length <= 9) {
        best = p;
        break;
      }
      if (best == null || p.length > best.length) best = p.length <= 9 ? p : best;
    }
    if (best == null || best.length < 2) {
      j.path
        ..clear()
        ..add(j.home);
      return;
    }
    j.path
      ..clear()
      ..addAll(maze.routePoints(best));
    j.at = 1;
    j.dir = 1;
  }

  void _swim(Jellyfish j, double dt) {
    if (j.pause > 0) {
      j.pause -= dt;
      j.glow = 1;
      return;
    }
    final goal = j.path[j.at];
    final d = goal - j.pos;
    final step = config.jellySpeed * dt;
    if (d.distance <= step) {
      j.pos = goal;
      final next = j.at + j.dir;
      if (next < 0 || next >= j.path.length) {
        j.dir = -j.dir;
        j.pause = jellyPause;
        j.at += j.dir;
      } else {
        j.at = next;
      }
    } else {
      j.pos += d / d.distance * step;
    }
    // Brighter as the end of the patrol comes near.
    final last = j.dir > 0 ? j.path.last : j.path.first;
    j.glow = (1 - (last - j.pos).distance / 1.2).clamp(0.0, 1.0);
  }

  /// A jellyfish stung the ball: back to the start, gates stay open.
  void caughtByJelly() => _sendBack(
      config.world == WorldKind.candy ? 'notice.gummy' : 'notice.jelly');

  /// Back to the start (the gates stay open), with a message.
  void _sendBack(String key) {
    _offerReturn();
    bursts.add(Burst(pos, 1));
    pos = maze.cellCenter(maze.start);
    vel = Offset.zero;
    _invulnerable = 2.0;
    notice = key;
    noticeArgs = const {};
    noticeLeft = 2.5;
  }

  void _updateGlass(double dt) {
    final shielded = bonusLeft > 0;
    _crumble(dt, shielded);
    _updateBeams(dt, shielded);
  }

  /// The floor gives way under a ball that dawdles: four stages of cracking
  /// and then it falls through. Cracks mend slowly once the ball moves on.
  void _crumble(double dt, bool shielded) {
    final slow = !shielded && !ball.floats && vel.distance < crumbleSpeed;
    Crumble? under;
    for (final k in cracks) {
      if ((k.pos - pos).distance < crumbleRadius) {
        under = k;
        break;
      }
    }
    if (under == null && slow) {
      under = Crumble(pos);
      cracks.add(under);
      if (cracks.length > 24) cracks.removeAt(0);
    }
    for (final k in cracks) {
      if (identical(k, under) && slow) {
        k.level += dt / config.crumbleSeconds;
      } else {
        k.level -= dt * 0.35;
      }
    }
    cracks.removeWhere((k) => k.level <= 0 && !identical(k, under));
    if (under != null && under.level >= 1) _lose('lose.floor');
  }

  void _updateBeams(double dt, bool shielded) {
    for (final b in beams) {
      b.age += dt;
    }
    beams.removeWhere((b) => b.age > GlassBeam.warning + GlassBeam.burn);
    _beamTimer -= dt;
    if (_beamTimer <= 0 && !shielded && beams.length < config.beamCount) {
      _beamTimer = config.beamInterval * (0.7 + 0.6 * _rnd.nextDouble());
      _spawnBeam();
    }
    if (shielded) return;
    for (final b in beams) {
      if (!b.burning) continue;
      final d = b.b - b.a;
      final off = ((pos - b.a).dx * d.dy - (pos - b.a).dy * d.dx).abs() / d.distance;
      if (off < b.halfWidth + ballRadius * 0.3) {
        _lose('lose.laser');
        break;
      }
    }
  }

  /// A laser along a random row or column (rectangular maze), or a random
  /// chord from edge to edge (round maze).
  void _spawnBeam() {
    final m = maze;
    if (m is RectMaze) {
      if (_rnd.nextBool()) {
        final y = _rnd.nextInt(m.rows) + 0.5;
        beams.add(GlassBeam(Offset(-0.6, y), Offset(m.cols + 0.6, y), 0.42));
      } else {
        final x = _rnd.nextInt(m.cols) + 0.5;
        beams.add(GlassBeam(Offset(x, -0.6), Offset(x, m.rows + 0.6), 0.42));
      }
    } else {
      final r = m.radius + 0.4;
      final phi = _rnd.nextDouble() * pi;
      final o = (_rnd.nextDouble() * 2 - 1) * m.radius * 0.7;
      final d = Offset(cos(phi), sin(phi));
      final n = Offset(-d.dy, d.dx);
      final h = sqrt(r * r - o * o);
      beams.add(GlassBeam(n * o - d * h, n * o + d * h, 0.38));
    }
    if (!_beamNoticed) {
      _beamNoticed = true;
      notice = 'notice.beam';
      noticeArgs = const {};
      noticeLeft = 1.5;
    }
  }

  /// True when the ball is inside the drone's view cone with no wall between.
  bool droneSees(Creature d) {
    final v = pos - d.pos;
    final dist = v.distance;
    if (dist > droneRange) return false;
    var diff = (v.direction - d.viewAngle) % kTwoPi;
    if (diff > pi) diff -= kTwoPi;
    if (diff.abs() > droneHalfAngle) return false;
    return _lineClear(d.pos, pos);
  }

  /// Tests: clear the "caught" state so a long simulation can continue.
  @visibleForTesting
  void caughtResetForTest() {
    noticeLeft = 0;
    _invulnerable = 0;
  }

  /// A drone spotted the ball: back to the start, gates stay open.
  void caughtByDrone() {
    _offerReturn();
    bursts.add(Burst(pos, 1));
    pos = maze.cellCenter(maze.start);
    vel = Offset.zero;
    _invulnerable = 2.0;
    notice = 'notice.drone';
    noticeArgs = const {};
    noticeLeft = 2.5;
    for (final d in creatures) {
      d.alert = 0;
    }
  }

  bool _lineClear(Offset a, Offset b) {
    for (final s in maze.segmentsAlong(a, b)) {
      if (s.gate >= 0 && gateOpen[s.gate]) continue;
      if (_cross(a, b, s.a, s.b)) return false;
    }
    return true;
  }

  static bool _cross(Offset p1, Offset p2, Offset p3, Offset p4) {
    double o(Offset a, Offset b, Offset c) =>
        (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
    final d1 = o(p3, p4, p1);
    final d2 = o(p3, p4, p2);
    final d3 = o(p1, p2, p3);
    final d4 = o(p1, p2, p4);
    return d1 * d2 < 0 && d3 * d4 < 0;
  }

  /// Spawns one trap (tests call this directly). [i] is the index within the
  /// current spawn wave.
  @visibleForTesting
  void spawnTrap([int i = 0]) => _spawnHazard(i);

  void _spawnHazard(int i) {
    if (config.world == WorldKind.mountains || config.world == WorldKind.volcano) {
      _spawnBoulder(i);
    } else {
      _spawnSpikes(i);
    }
  }

  /// A boulder lands where the ball is heading, led by its speed, but never
  /// closer than [minBoulderDistance]: it forces you to keep moving without
  /// dropping out of the sky right on top of you.
  void _spawnBoulder(int i) {
    final warn = config.aimedWarn;
    final speed = vel.distance;
    // Preferred direction: where the ball is going; a standing ball gets a
    // random one.
    final base = speed > 0.3 ? vel.direction : _rnd.nextDouble() * kTwoPi;
    var lead = speed > 0.3
        ? max(minBoulderDistance, speed * warn)
        : minBoulderDistance + _rnd.nextDouble() * 1.2;
    // Later boulders of a wave land a little off to the side.
    final spread = i == 0 ? 0.0 : (_rnd.nextDouble() - 0.5) * 1.6;
    Offset? target;
    for (var k = 0; k < 8 && target == null; k++) {
      // Try the preferred direction first, then turn away step by step.
      final turn = k == 0 ? 0.0 : (k.isOdd ? 1 : -1) * ((k + 1) ~/ 2) * pi / 4;
      var cand = pos + polar(lead, base + spread + turn);
      cand = maze.clampInside(cand);
      if ((cand - pos).distance >= minBoulderDistance) target = cand;
    }
    lead = minBoulderDistance;
    target ??= pos + polar(lead, base + pi); // cornered: drop it behind
    // A volcanic bomb always lands in a corridor, in the middle of a cell.
    if (config.world == WorldKind.volcano) {
      target = maze.cellCenter(maze.cellAt(target));
    }
    hazards.add(Hazard(
      target,
      armAt: warn,
      life: warn + (config.world == WorldKind.volcano ? bombFireSeconds : rubbleSeconds),
      radius: 0.85,
    ));
  }

  /// Spikes pop up in the corridor ahead on the route to the next goal (a
  /// button, or the centre), where they block it completely for a while.
  /// They always appear well away from the ball, never beside it.
  void _spawnSpikes(int i) {
    final special = {maze.start, maze.goal, ...maze.buttonCells};
    final next = buttonUsed.indexOf(false);
    final targetCell = next >= 0 ? maze.buttonCells[next] : maze.goal;
    final route = maze.path(maze.cellAt(pos), targetCell, gateOpen);
    if (route != null) {
      for (var k = min(route.length - 1, 5 + i * 2); k >= 3; k--) {
        final c = route[k];
        if (c == targetCell || special.contains(c)) continue;
        final p = maze.cellCenter(c);
        if ((p - pos).distance < minSpikeDistance) continue;
        if (hazards.any((h) => (h.pos - p).distance < 0.6)) continue;
        hazards.add(_newPit(p));
        return;
      }
    }
    // No usable route ahead: a trap somewhere else, still far from the ball.
    for (var tries = 0; tries < 30; tries++) {
      final c = 1 + _rnd.nextInt(maze.cellCount - 1);
      if (special.contains(c)) continue;
      final p = maze.cellCenter(c);
      if ((p - pos).distance < minSpikeDistance + 0.5) continue;
      hazards.add(_newPit(p));
      return;
    }
  }

  /// A spike trap (mud) or a grave that caves in (graveyard): the ground
  /// cracks first, and the graves give a longer warning.
  Hazard _newPit(Offset p) => config.world == WorldKind.graveyard
      ? Hazard(p, armAt: 1.1, life: 5, radius: 0.12)
      : Hazard(p, armAt: 0.5, life: 6);

  /// Wolf: walk the shortest corridor route to the ball.
  void _followPath(Creature w, double dt, double speed) {
    w.repath -= dt;
    if (w.repath <= 0 || w.route.isEmpty) {
      w.repath = 0.3;
      final from = maze.cellAt(w.pos);
      final to = maze.cellAt(pos);
      final p = maze.path(from, to, gateOpen);
      w.route.clear();
      if (p == null) {
        // The ball is cut off from the wolf by a closed gate: the wolf cannot
        // follow, and must never cut across the walls. It waits at the gate.
        return;
      }
      if (p.length > 1) {
        w.route.addAll(maze.routePoints(p).skip(1));
      } else {
        w.route.add(pos);
      }
    }
    _walk(w, dt, speed);
  }

  /// Drone: wander from cell to cell through open passages.
  void _patrol(Creature d, double dt, double speed) {
    if (d.route.isEmpty) {
      final options = [
        for (final (n, e) in maze.neighbours(d.cell))
          if (_passable(e) && n != maze.goal) n,
      ];
      if (options.isEmpty) return;
      var next = options[_rnd.nextInt(options.length)];
      if (options.length > 1 && next == d.prevCell) {
        next = options[_rnd.nextInt(options.length)];
      }
      d.route.addAll(maze.routePoints([d.cell, next]).skip(1));
      d.prevCell = d.cell;
      d.cell = next;
    }
    _walk(d, dt, speed);
  }

  void _walk(Creature c, double dt, double speed) {
    var budget = speed * dt;
    while (budget > 0 && c.route.isNotEmpty) {
      final to = c.route.first - c.pos;
      final dist = to.distance;
      if (dist <= budget) {
        c.pos = c.route.removeAt(0);
        budget -= dist;
      } else {
        c.pos += to / dist * budget;
        c.angle = to.direction;
        budget = 0;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
