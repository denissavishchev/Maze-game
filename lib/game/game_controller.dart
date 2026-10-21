import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import '../audio/haptics.dart';
import '../audio/sfx.dart';
import '../l10n/strings.dart';
import 'ball.dart';
import 'polar_maze.dart';
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
  GameController(this.config, {this.hazardsEnabled = true, int? seed})
      : _rnd = seed == null ? Random() : Random(seed) {
    newMaze();
  }

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

  /// How close the ball must come to a cell to uncover it on the minimap.
  static const double exploreRadius = 1.9;

  /// How far the entrance trail reaches beyond the outer wall; the ball
  /// cannot roll off its end.
  static const double _trailLength = PolarMaze.trailLength;

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
  static const double rubbleSeconds = 9;
  static const double rubbleRadius = 0.42;

  /// Gust of wind: warning, then how long it blows.
  static const double windWarning = 1.5;
  static const double windDuration = 2.5;

  /// Uses per bonus pickup and how long one use lasts.
  static const int usesPerBonus = 3;
  static const double bonusDuration = 10;
  static const double lightBoostFactor = 1.9;

  /// What a drone sees: a cone this long and this wide (half-angle, radians).
  static const double droneRange = 2.8;
  static const double droneHalfAngle = 0.5;

  /// A drone must keep the ball in view this long before it catches it.
  static const double droneReaction = 0.45;

  final GameConfig config;

  /// What the chosen ball is made of, and its radius.
  late final BallStats ball = statsOf(config.ball);
  late final double ballRadius = baseBallRadius * ball.radius;

  /// Tests switch hazards off so an autopilot cannot be killed.
  final bool hazardsEnabled;

  final Random _rnd;

  late PolarMaze maze;
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
  List<Burst> bursts = [];

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

  double _spawnTimer = 1.5;
  double _impact = 0;
  double _soundCooldown = 0;
  double _buzzCooldown = 0;
  double _noiseCooldown = 0;
  double _invulnerable = 0;
  bool _disposed = false;

  int get pressedCount => buttonUsed.where((u) => u).length;
  bool get won => status == GameStatus.won;
  bool get lost => status == GameStatus.lost;

  void newMaze() {
    maze = PolarMaze.generate(
      rings: config.rings,
      gates: config.buttonCount,
      random: _rnd,
    );
    _centers = [for (var c = 0; c < maze.cellCount; c++) maze.cellCenter(c)];
    final taken = {maze.start, maze.goal, ...maze.buttonCells};
    bonusCells = ([
      for (var c = 1; c < maze.cellCount; c++)
        if (!taken.contains(c)) c,
    ]..shuffle(_rnd))
        .take(config.bonusCount)
        .toList();
    mud = [];
    if (config.world == WorldKind.mud) {
      final special = {maze.start, maze.goal, ...maze.buttonCells};
      Offset jitter() =>
          Offset(_rnd.nextDouble() - 0.5, _rnd.nextDouble() - 0.5) * 0.3;
      // Bogs scattered around, plus some right on the way to the centre that
      // fill the whole corridor and cannot be avoided.
      final cells = [
        for (var c = 1; c < maze.cellCount; c++)
          if (!special.contains(c)) c,
      ]..shuffle(_rnd);
      for (final c in cells.take(maze.rings)) {
        mud.add(MudPatch(maze.cellCenter(c) + jitter(), 0.38 + _rnd.nextDouble() * 0.12));
      }
      final onRoute = [
        for (final c in maze.solution)
          if (!special.contains(c)) c,
      ]..shuffle(_rnd);
      for (final c in onRoute.take(config.routeBogs)) {
        mud.add(MudPatch(maze.cellCenter(c), 0.5));
      }
    }
    restart();
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
    sink = 0;
    windDir = Offset.zero;
    windWarnLeft = 0;
    windLeft = 0;
    _windTimer = 7;
    bonusTaken = List<bool>.filled(bonusCells.length, false);
    bonusCharges = 0;
    bonusLeft = 0;
    lightFactor = 1;
    _spawnTimer = config.trapInterval;
    _invulnerable = 0;
    creatures = hazardsEnabled ? _spawnCreatures() : [];
    notifyListeners();
  }

  // ---- creatures --------------------------------------------------------

  List<Creature> _spawnCreatures() {
    if (config.world != WorldKind.forest && config.world != WorldKind.city) {
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
    if (!started && tilt.distance > startTilt) started = true;
    if (started) elapsed += dt;

    if (config.world == WorldKind.mountains &&
        config.windEnabled &&
        hazardsEnabled &&
        started) {
      _updateWind(dt);
    }
    final before = pos;
    _physics(dt, tilt);
    _roll(pos - before);
    _impactSound(dt);
    final breaksAt = ball.breaksAt;
    if (breaksAt != null && _impact >= breaksAt && status == GameStatus.playing) {
      _lose('lose.glass');
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
    if (noticeLeft > 0) noticeLeft -= dt;
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

    if (status == GameStatus.playing && pos.distance < 0.55) {
      status = GameStatus.won;
      _saveRecord();
    }
    notifyListeners();
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
    final matters =
        config.world == WorldKind.forest || config.world == WorldKind.city;
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
    for (final m in mud) {
      if ((m.pos - pos).distance < m.radius + 0.1) return m;
    }
    return null;
  }

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
      notice = 'notice.wind';
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
    if (windLeft > 0) {
      vel += windDir * (config.windStrength * (1 - ball.windResist) * dt);
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

    vel *= exp(-(muddy ? 7.0 : 1.7 * ball.damping) * dt);
    final cap = muddy ? 1.8 : _maxSpeed * ball.maxSpeed;
    if (vel.distance > cap) vel = vel / vel.distance * cap;

    final steps = max(1, (vel.distance * dt / 0.07).ceil());
    for (var i = 0; i < steps; i++) {
      pos += vel * (dt / steps);
      _collide();
    }
  }

  void _collide() {
    final reach = ballRadius + PolarMaze.wallHalf;
    for (var iter = 0; iter < 2; iter++) {
      final ring = min(pos.distance.floor(), maze.rings + 1);
      for (var k = max(0, ring - 1); k <= min(maze.rings + 1, ring + 1); k++) {
        for (final s in maze.byRing[k]) {
          if (s.gate >= 0 && gateOpen[s.gate]) continue;
          final ab = s.b - s.a;
          final t = (((pos - s.a).dx * ab.dx + (pos - s.a).dy * ab.dy) /
                  (ab.dx * ab.dx + ab.dy * ab.dy))
              .clamp(0.0, 1.0);
          final q = s.a + ab * t;
          final d = pos - q;
          final dist = d.distance;
          if (dist >= reach) continue;
          final n = dist < 1e-6 ? Offset(-ab.dy, ab.dx) / ab.distance : d / dist;
          pos = q + n * reach;
          final vn = vel.dx * n.dx + vel.dy * n.dy;
          if (vn < 0) {
            vel -= n * (vn * (1 + ball.bounce));
            _impact = max(_impact, -vn);
          }
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
    final limit = maze.radius + _trailLength - ballRadius;
    if (pos.distance > limit) {
      final n = pos / pos.distance;
      pos = n * limit;
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
        hazards.clear();
      case WorldKind.underground:
        break;
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

  void _lose(String reason) {
    if (status != GameStatus.playing) return;
    status = GameStatus.lost;
    lostReason = reason;
    bursts.add(Burst(pos, 1));
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
      if (config.world == WorldKind.forest) {
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
    if (config.world != WorldKind.forest && config.world != WorldKind.city) {
      return;
    }
    bursts.add(Burst(at, 3));
    for (final c in creatures) {
      if (c.lockLeft > 0 || (c.pos - at).distance > noiseRadius) continue;
      if (config.world == WorldKind.forest) {
        if (c.asleep) _wake(c);
      } else {
        _alertDrone(c, at);
      }
    }
  }

  void _wake(Creature w) {
    if (w.asleep) Sfx.play(Sound.wolfWake, volume: _earshot(w.pos));
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
    if (config.world == WorldKind.forest || config.world == WorldKind.city) {
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
      case WorldKind.underground:
      case WorldKind.mud:
      case WorldKind.mountains:
        break;
    }

    // Timed dangers.
    for (final h in hazards) {
      final wasArmed = h.armed;
      h.age += dt;
      if (config.world == WorldKind.mountains) {
        // The boulder crashes down the moment it becomes armed.
        if (!wasArmed && h.armed) {
          bursts.add(Burst(h.pos, 1));
          if ((h.pos - pos).distance < h.radius + 0.1) _lose('lose.rock');
        }
      } else if (h.armed && (h.pos - pos).distance < h.radius) {
        _lose('lose.trap');
      }
    }
    hazards.removeWhere((h) => h.age > h.life);

    if (config.world == WorldKind.mud || config.world == WorldKind.mountains) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnTimer = config.trapInterval *
            (config.world == WorldKind.mountains ? 1.2 : 1.0);
        for (var i = 0; i < config.trapCount; i++) {
          _spawnHazard(i);
        }
      }
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
    final steps = max(1, ((b - a).distance / 0.5).ceil());
    final rings = <int>{};
    for (var i = 0; i <= steps; i++) {
      final p = Offset.lerp(a, b, i / steps)!;
      rings.add(min(p.distance.floor(), maze.rings + 1));
    }
    for (final k in rings) {
      for (final s in maze.byRing[k]) {
        if (s.gate >= 0 && gateOpen[s.gate]) continue;
        if (_cross(a, b, s.a, s.b)) return false;
      }
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
    if (config.world == WorldKind.mountains) {
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
      if (cand.distance > maze.radius) {
        cand = cand / cand.distance * maze.radius;
      }
      if ((cand - pos).distance >= minBoulderDistance) target = cand;
    }
    lead = minBoulderDistance;
    target ??= pos + polar(lead, base + pi); // cornered: drop it behind
    hazards.add(Hazard(
      target,
      armAt: warn,
      life: warn + rubbleSeconds,
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
        hazards.add(Hazard(p, armAt: 0.5, life: 6));
        return;
      }
    }
    // No usable route ahead: a trap somewhere else, still far from the ball.
    for (var tries = 0; tries < 30; tries++) {
      final c = 1 + _rnd.nextInt(maze.cellCount - 1);
      if (special.contains(c)) continue;
      final p = maze.cellCenter(c);
      if ((p - pos).distance < minSpikeDistance + 0.5) continue;
      hazards.add(Hazard(p, armAt: 0.5, life: 6));
      return;
    }
  }

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
