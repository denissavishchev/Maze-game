import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every difficulty is solvable by collecting the buttons in order', () {
    for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
      final cfg = GameConfig(WorldKind.forest, level);
      final sw = Stopwatch()..start();
      final m = PolarMaze.generate(
        rings: cfg.rings,
        gates: cfg.buttonCount,
        random: Random(level),
      );
      final open = List<bool>.filled(m.gateCount, false);
      var cur = m.start;
      for (var j = 0; j < m.gateCount; j++) {
        final p = m.path(cur, m.buttonCells[j], open);
        expect(p, isNotNull, reason: 'level $level: button $j unreachable');
        cur = m.buttonCells[j];
        open[j] = true;
      }
      expect(m.path(cur, m.goal, open), isNotNull, reason: 'level $level goal');
      // ignore: avoid_print
      print('level $level: ${m.cellCount} cells, route ${m.solution.length}, '
          '${m.gateCount} gates, ${sw.elapsedMilliseconds} ms');
    }
  });

  test('without any button the goal is out of reach', () {
    final m = PolarMaze.generate(rings: 7, gates: 6, random: Random(3));
    expect(m.path(m.start, m.goal, List<bool>.filled(m.gateCount, false)), isNull);
  });

  test('autopilot steering the ball reaches every button and the centre', () {
    for (final level in [1, 3, 5]) {
      final game = GameController(
        GameConfig(WorldKind.forest, level),
        hazardsEnabled: false,
        seed: level,
      );
      final m = game.maze as PolarMaze;

      void goTo(int targetCell) {
        final route = m.routePoints(
            m.path(m.cellAt(game.pos), targetCell, game.gateOpen)!);
        for (final wp in route) {
          var steps = 0;
          while (!game.won && (wp - game.pos).distance > 0.25) {
            final want = (wp - game.pos) * 3 - game.vel * 0.9;
            final tilt = want.distance > 1 ? want / want.distance : want;
            game.update(1 / 60, tilt);
            expect(++steps, lessThan(1500),
                reason: 'level $level stuck at ${game.pos} heading to $wp');
          }
        }
      }

      for (var j = 0; j < m.gateCount; j++) {
        goTo(m.buttonCells[j]);
        expect(game.buttonUsed[j], isTrue, reason: 'button $j not pressed');
      }
      goTo(m.goal);
      expect(game.won, isTrue, reason: 'level $level');
      game.dispose();
    }
  });

  test('five levels grow in every dimension', () {
    final cfgs = [
      for (var l = GameConfig.minLevel; l <= GameConfig.maxLevel; l++)
        GameConfig(WorldKind.city, l),
    ];
    expect(cfgs.length, 5);
    for (var i = 1; i < cfgs.length; i++) {
      expect(cfgs[i].rings, greaterThan(cfgs[i - 1].rings));
      expect(cfgs[i].buttonCount, greaterThan(cfgs[i - 1].buttonCount));
      expect(cfgs[i].trapCount, greaterThanOrEqualTo(cfgs[i - 1].trapCount));
      expect(cfgs[i].chaserCount, greaterThanOrEqualTo(cfgs[i - 1].chaserCount));
      expect(cfgs[i].lightRadius, lessThan(cfgs[i - 1].lightRadius));
    }
  });

  test('drones sleep, wake for a noise, go to look and then scan around', () {
    final game = GameController(
      const GameConfig(WorldKind.city, 3),
      seed: 21,
    );
    final m = game.maze as PolarMaze;
    game.gateOpen = List<bool>.filled(m.gateCount, true);
    final drone = game.creatures.first;
    expect(drone.asleep, isTrue);

    // Far away: stays asleep.
    game.noise(drone.pos + const Offset(GameController.noiseRadius + 3, 0));
    expect(drone.asleep, isTrue);

    // Noise in a neighbouring cell: wakes up and heads there.
    final here = m.cellAt(drone.pos);
    final (next, _) = m.neighbours(here).firstWhere((n) => n.$1 != m.goal);
    game.noise(m.cellCenter(next));
    expect(drone.asleep, isFalse);
    expect(drone.target, next);

    game.started = true;
    game.forcedStill = 0; // the ball keeps moving, so the drone stays on duty
    game.pos = m.cellCenter(m.start);
    for (var i = 0; i < 600 && drone.target >= 0; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(drone.target, -1, reason: 'reached the noise');
    expect(drone.searchLeft, greaterThan(0), reason: 'now scanning');
    game.dispose();
  });

  test('wolves start asleep and wake only for a loud bump within earshot', () {
    final game = GameController(
      const GameConfig(WorldKind.forest, 4),
      seed: 5,
    );
    final wolf = game.creatures.first;
    expect(wolf.asleep, isTrue);

    game.noise(wolf.pos + const Offset(GameController.noiseRadius + 3, 0));
    expect(wolf.asleep, isTrue, reason: 'too far to hear');

    game.noise(wolf.pos + const Offset(1.5, 0));
    expect(wolf.asleep, isFalse);
    expect(wolf.grace, greaterThan(0));
    game.dispose();
  });

  test('a sleeping wolf next to the ball is harmless', () {
    final game = GameController(
      const GameConfig(WorldKind.forest, 4),
      seed: 8,
    );
    final wolf = game.creatures.first;
    // Put the ball next to a sleeping wolf: nothing happens.
    game.started = true;
    game.pos = wolf.pos + const Offset(1.2, 0);
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(game.lost, isFalse);
    expect(wolf.asleep, isTrue);
    game.dispose();
  });

  test('drones see in a cone and not through walls; being seen means start', () {
    final game = GameController(
      const GameConfig(WorldKind.city, 5),
      seed: 11,
    );
    final m = game.maze as PolarMaze;
    game.gateOpen = List<bool>.filled(m.gateCount, true);
    final drone = game.creatures.first;

    // Two cells joined by an open passage.
    final a = m.solution[0];
    final b = m.solution[1];
    game.pos = m.cellCenter(a);
    drone.pos = m.cellCenter(b);
    drone.viewAngle = (game.pos - drone.pos).direction;
    expect(game.droneSees(drone), isTrue);

    drone.viewAngle += 3.0; // looking the other way
    expect(game.droneSees(drone), isFalse);

    // Two neighbouring cells separated by a closed wall.
    for (var c = 1; c < m.cellCount; c++) {
      for (final (n, e) in m.neighbours(c)) {
        if (n == 0 || m.open[e]) continue;
        game.pos = m.cellCenter(c);
        drone.pos = m.cellCenter(n);
        if ((game.pos - drone.pos).distance > 2.5) continue;
        drone.viewAngle = (game.pos - drone.pos).direction;
        expect(game.droneSees(drone), isFalse, reason: 'wall between $c and $n');
        c = m.cellCount; // done
        break;
      }
    }

    game.gateOpen[0] = true;
    game.pos = m.cellCenter(m.goal + 5);
    game.caughtByDrone();
    expect(game.pos, m.cellCenter(m.start));
    expect(game.gateOpen[0], isTrue, reason: 'opened gates stay open');
    expect(game.noticeLeft, greaterThan(0));
    expect(game.lost, isFalse);
    game.dispose();
  });

  test('buttons are spread out over the maze', () {
    for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
      final cfg = GameConfig(WorldKind.forest, level);
      for (var seed = 0; seed < 15; seed++) {
        final m = PolarMaze.generate(
          rings: cfg.rings,
          gates: cfg.buttonCount,
          random: Random(seed),
        );
        var closest = 99.0;
        for (var i = 0; i < m.gateCount; i++) {
          for (var j = i + 1; j < m.gateCount; j++) {
            closest = min(
              closest,
              (m.cellCenter(m.buttonCells[i]) - m.cellCenter(m.buttonCells[j]))
                  .distance,
            );
          }
        }
        expect(closest, greaterThan(2.0),
            reason: 'level $level seed $seed: two buttons are neighbours');
      }
    }
  });

  test('there are as many bonuses as traps, three uses each', () {
    for (final world in WorldKind.values) {
      for (var level = GameConfig.minLevel; level <= GameConfig.maxLevel; level++) {
        final game = GameController(GameConfig(world, level), seed: level);
        expect(game.bonusCells.length, game.config.trapCount);
        expect(game.bonusCells.toSet().length, game.bonusCells.length);
        game.dispose();
      }
    }
    final game = GameController(const GameConfig(WorldKind.mud, 5), seed: 2);
    game.started = true;
    for (var i = 0; i < game.bonusCells.length; i++) {
      game.pos = game.maze.cellCenter(game.bonusCells[i]);
      game.update(1 / 60, Offset.zero);
    }
    expect(game.bonusCharges, 3 * game.bonusCells.length);
    game.dispose();
  });

  test('forest bonus puts wolves to sleep and noise cannot wake them', () {
    final game = GameController(const GameConfig(WorldKind.forest, 3), seed: 6);
    final wolf = game.creatures.first;
    game.noise(wolf.pos + const Offset(1, 0));
    expect(wolf.asleep, isFalse);

    game.started = true;
    game.bonusCharges = 3;
    game.useBonus();
    expect(game.bonusCharges, 2);
    expect(wolf.asleep, isTrue);
    game.noise(wolf.pos + const Offset(1, 0));
    expect(wolf.asleep, isTrue, reason: 'locked asleep during the bonus');

    // Cannot stack a second use while one is running.
    game.useBonus();
    expect(game.bonusCharges, 2);

    for (var i = 0; i < 700; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(game.bonusLeft, 0);
    game.noise(wolf.pos + const Offset(1, 0));
    expect(wolf.asleep, isFalse, reason: 'normal rules after the bonus');
    game.dispose();
  });

  test('city bonus switches drones off', () {
    final game = GameController(const GameConfig(WorldKind.city, 3), seed: 6);
    final d = game.creatures.first;
    game.noise(d.pos + const Offset(1, 0));
    expect(d.asleep, isFalse);
    game.bonusCharges = 1;
    game.useBonus();
    expect(d.asleep, isTrue);
    expect(d.searching, isFalse);
    game.noise(d.pos);
    expect(d.asleep, isTrue);
    game.dispose();
  });

  test('mud and mountain bonus switches traps off, underground adds light', () {
    for (final world in [WorldKind.mud, WorldKind.mountains]) {
      final game = GameController(GameConfig(world, 5), seed: 3);
      game.started = true;
      game.spawnTrap();
      expect(game.hazards, isNotEmpty, reason: '$world has traps');
      game.bonusCharges = 1;
      game.useBonus();
      expect(game.hazards, isEmpty);
      for (var i = 0; i < 300; i++) {
        game.update(1 / 60, Offset.zero);
        expect(game.hazards, isEmpty, reason: '$world stays off during bonus');
      }
      game.dispose();
    }

    final cave = GameController(const GameConfig(WorldKind.underground, 5), seed: 3);
    cave.started = true;
    expect(cave.lightFactor, 1);
    cave.bonusCharges = 1;
    cave.useBonus();
    for (var i = 0; i < 120; i++) {
      cave.update(1 / 60, Offset.zero);
    }
    expect(cave.lightFactor, greaterThan(1.6));
    for (var i = 0; i < 900; i++) {
      cave.update(1 / 60, Offset.zero);
    }
    expect(cave.lightFactor, lessThan(1.1));
    cave.dispose();
  });

  test('noise follows the speed of the ball: sneaking is silent, rolling is loud', () {
    final game = GameController(const GameConfig(WorldKind.forest, 1), seed: 12);
    final out = polarOutward(game);

    // A gentle tilt gives a slow roll that makes no noise at all.
    var maxSlow = 0.0;
    var maxSpeed = 0.0;
    for (var i = 0; i < 180; i++) {
      game.update(1 / 60, out * 0.15);
      maxSlow = maxSlow < game.noiseLevel ? game.noiseLevel : maxSlow;
      maxSpeed = maxSpeed < game.vel.distance ? game.vel.distance : maxSpeed;
    }
    expect(maxSpeed, lessThan(GameController.quietSpeed), reason: 'a slow sneak');
    expect(maxSlow, 0);
    expect(game.hearingRadius, 0);

    // Full tilt is loud.
    game.restart();
    var maxLoud = 0.0;
    for (var i = 0; i < 90; i++) {
      game.update(1 / 60, out);
      maxLoud = maxLoud < game.noiseLevel ? game.noiseLevel : maxLoud;
    }
    expect(maxLoud, greaterThan(0.7));
    game.dispose();
  });

  test('a sleeping wolf hears a loud ball nearby but not a quiet or far one', () {
    GameController make() => GameController(const GameConfig(WorldKind.forest, 2), seed: 14);

    // Quiet: right beside the wolf, no wake-up.
    var game = make();
    var wolf = game.creatures.first;
    game.started = true;
    game.pos = wolf.pos + const Offset(1, 0);
    game.forcedNoise = 0;
    for (var i = 0; i < 300; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(wolf.asleep, isTrue, reason: 'sneaking past is silent');
    game.dispose();

    // Loud and close: wakes.
    game = make();
    wolf = game.creatures.first;
    game.started = true;
    game.pos = wolf.pos + const Offset(1.5, 0);
    game.forcedNoise = 0.8;
    for (var i = 0; i < 60 && wolf.asleep; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(wolf.asleep, isFalse);
    game.dispose();

    // Loud but out of earshot: stays asleep.
    game = make();
    wolf = game.creatures.first;
    game.started = true;
    game.pos = wolf.pos + Offset(GameController.maxHearing + 2, 0);
    game.forcedNoise = 1;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(wolf.asleep, isTrue);
    game.dispose();
  });

  test('a wolf loses interest when the ball stands still and goes back to sleep', () {
    final game = GameController(const GameConfig(WorldKind.forest, 1), seed: 16);
    final wolf = game.creatures.first;
    game.noise(wolf.pos + const Offset(1, 0));
    expect(wolf.asleep, isFalse);
    game.started = true;
    for (var i = 0; i < 60 * 10 && !game.lost; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(game.lost, isFalse);
    expect(wolf.asleep, isTrue);
    game.dispose();
  });

  test('a drone loses interest when the ball stands still and lands', () {
    final game = GameController(const GameConfig(WorldKind.city, 1), seed: 19);
    final d = game.creatures.first;
    game.noise(d.pos + const Offset(1, 0));
    expect(d.asleep, isFalse);
    game.started = true;
    for (var i = 0; i < 60 * 10 && !game.lost; i++) {
      game.update(1 / 60, Offset.zero);
      expect(game.noticeLeft, 0, reason: 'never caught while the ball is still');
    }
    expect(d.asleep, isTrue);
    expect(d.searching, isFalse);
    game.dispose();
  });

  test('drones wake for a loud ball and go to where it was heard', () {
    final game = GameController(const GameConfig(WorldKind.city, 2), seed: 18);
    final m = game.maze as PolarMaze;
    game.gateOpen = List<bool>.filled(m.gateCount, true);
    final d = game.creatures.first;
    expect(d.asleep, isTrue);
    game.started = true;
    game.pos = d.pos + const Offset(2, 0);
    game.forcedNoise = 0.9;
    for (var i = 0; i < 90 && d.asleep; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(d.asleep, isFalse);
    expect(d.target, m.cellAt(game.pos));
    game.dispose();
  });
  test('mud spikes ambush the route to the next button, far from the ball', () {
    // Find a maze whose first button is a good way off, so a route exists.
    for (var seed = 0; seed < 40; seed++) {
      final game = GameController(const GameConfig(WorldKind.mud, 3), seed: seed);
      final m = game.maze as PolarMaze;
      final route = m.path(m.cellAt(game.pos), m.buttonCells[0], game.gateOpen)!;
      if (route.length < 9) {
        game.dispose();
        continue;
      }
      game.started = true;
      game.spawnTrap();
      expect(game.hazards, hasLength(1));
      final cell = m.cellAt(game.hazards.first.pos);
      expect(route.indexOf(cell), greaterThanOrEqualTo(3), reason: 'well ahead on the route');
      expect(route.last, isNot(cell), reason: 'never on the button itself');
      expect((game.hazards.first.pos - game.pos).distance,
          greaterThanOrEqualTo(GameController.minSpikeDistance));
      game.dispose();
      return;
    }
    fail('no maze with a long enough first route in 40 seeds');
  });

  test('spikes never appear next to the ball, wherever it is', () {
    for (var seed = 0; seed < 6; seed++) {
      final game = GameController(const GameConfig(WorldKind.mud, 5), seed: seed);
      game.started = true;
      final rnd = Random(seed);
      for (var k = 0; k < 120; k++) {
        game.pos = game.maze.cellCenter(rnd.nextInt(game.maze.cellCount));
        game.hazards.clear();
        game.spawnTrap();
        game.spawnTrap(1);
        game.spawnTrap(2);
        for (final h in game.hazards) {
          expect((h.pos - game.pos).distance,
              greaterThanOrEqualTo(GameController.minSpikeDistance),
              reason: 'seed $seed: a spike landed beside the ball');
        }
      }
      game.dispose();
    }
  });

  test('a bog pulls the ball in and drowns it unless it breaks free', () {
    GameController make() => GameController(const GameConfig(WorldKind.mud, 3), seed: 9);

    // Left alone in a bog: sinks and loses.
    var game = make();
    game.started = true;
    final bog = game.mud.last; // one of the bogs lying on the route
    game.pos = bog.pos;
    for (var i = 0; i < 60 * 5 && !game.lost; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(game.lost, isTrue);
    expect(game.lostReason, 'lose.bog');
    game.dispose();

    // The bonus switches the bog off.
    game = make();
    game.started = true;
    game.pos = game.mud.last.pos;
    game.bonusCharges = 1;
    game.useBonus();
    for (var i = 0; i < 60 * 4; i++) {
      game.update(1 / 60, Offset.zero);
    }
    expect(game.lost, isFalse);
    expect(game.sink, 0);
    game.dispose();

    // Rolling out along the corridor frees the ball.
    game = make();
    game.started = true;
    final m = game.maze as PolarMaze;
    final patch = game.mud.last;
    game.pos = patch.pos;
    final route = m.routePoints(m.path(m.cellAt(patch.pos), m.goal, List<bool>.filled(m.gateCount, true))!).skip(1).toList();
    var idx = 0;
    for (var i = 0; i < 60 * 3 && !game.lost && idx < route.length; i++) {
      final want = route[idx] - game.pos;
      if (want.distance < 0.3) idx++;
      game.update(1 / 60, want.distance > 1e-6 ? want / want.distance : Offset.zero);
    }
    expect(game.lost, isFalse, reason: 'rolled out in time');
    expect((game.pos - patch.pos).distance, greaterThan(patch.radius));
    game.dispose();
  });

  test('boulders are led by the ball but never land beside it, and leave rubble', () {
    final game = GameController(const GameConfig(WorldKind.mountains, 3), seed: 4);
    game.started = true;
    game.pos = game.maze.cellCenter(game.maze.solution[game.maze.solution.length ~/ 2]);

    // Standing ball: lands a few cells off, not on it.
    game.vel = Offset.zero;
    game.spawnTrap();
    final still = game.hazards.last;
    final d = (still.pos - game.pos).distance;
    expect(d, greaterThanOrEqualTo(GameController.minBoulderDistance - 0.01));
    expect(d, lessThan(4.5));
    expect(still.armAt, game.config.aimedWarn);
    expect(still.life, still.armAt + GameController.rubbleSeconds);

    // Moving ball: lands ahead along its heading, at least as far as it will
    // have travelled by the time the boulder falls.
    game.hazards.clear();
    game.vel = const Offset(3, 0);
    game.spawnTrap();
    final moving = game.hazards.last;
    final ahead = moving.pos - game.pos;
    expect(ahead.dx, greaterThan(0), reason: 'in the direction of travel');
    expect(ahead.distance,
        greaterThanOrEqualTo(GameController.minBoulderDistance - 0.01));
    game.dispose();
  });

  test('boulders never land beside the ball, wherever it is', () {
    for (var seed = 0; seed < 6; seed++) {
      final game = GameController(const GameConfig(WorldKind.mountains, 5), seed: seed);
      game.started = true;
      final rnd = Random(seed);
      for (var k = 0; k < 150; k++) {
        game.pos = game.maze.cellCenter(rnd.nextInt(game.maze.cellCount));
        game.vel = Offset(rnd.nextDouble() * 8 - 4, rnd.nextDouble() * 8 - 4);
        game.hazards.clear();
        for (var i = 0; i < 3; i++) {
          game.spawnTrap(i);
        }
        for (final h in game.hazards) {
          expect((h.pos - game.pos).distance,
              greaterThanOrEqualTo(GameController.minBoulderDistance - 0.01),
              reason: 'seed $seed: a boulder landed beside the ball');
        }
      }
      game.dispose();
    }
  });

  test('a landed boulder is solid until it crumbles', () {
    final game = GameController(const GameConfig(WorldKind.mountains, 3), seed: 4);
    final m = game.maze as PolarMaze;
    final n = m.sectors.last;
    final theta = (m.entrance + 0.5) * 2 * pi / n;
    final out = Offset(cos(theta), sin(theta));
    final rock = out * (m.radius + 0.6);
    game.hazards.add(Hazard(rock, armAt: 0, life: 9, radius: 0.85));
    game.pos = out * (m.radius - 0.3);
    game.vel = out * 3;
    game.started = true;
    for (var i = 0; i < 90; i++) {
      game.update(1 / 60, out);
    }
    expect(game.lost, isFalse);
    expect((game.pos - rock).distance,
        greaterThanOrEqualTo(GameController.rubbleRadius + game.ballRadius - 0.01),
        reason: 'the ball cannot pass through the rubble');
    game.dispose();
  });

  test('wind only blows on the two biggest sizes and pushes the ball', () {
    // The force itself.
    final game = GameController(const GameConfig(WorldKind.mountains, 5),
        hazardsEnabled: false, seed: 2);
    game.windDir = const Offset(1, 0);
    game.windLeft = 2;
    game.pos = Offset(game.maze.radius + 0.4, 0);
    game.vel = Offset.zero;
    game.started = true;
    game.update(1 / 60, Offset.zero);
    expect(game.vel.dx, greaterThan(0));
    game.dispose();

    // The schedule: warning first, then a gust; never at the smaller sizes.
    for (final level in [1, 3, 4, 5]) {
      final g = GameController(GameConfig(WorldKind.mountains, level), seed: 2);
      g.started = true;
      g.bonusLeft = 1000; // boulders off so the test ball survives
      var warned = false;
      var blew = false;
      for (var i = 0; i < 60 * 25; i++) {
        g.update(1 / 60, Offset.zero);
        warned = warned || g.windWarnLeft > 0;
        blew = blew || g.windLeft > 0;
      }
      expect(blew, level >= 4, reason: 'level $level');
      expect(warned, level >= 4, reason: 'level $level');
      g.dispose();
    }
  });
  test('the minimap only uncovers cells the ball has been near', () {
    final game = GameController(const GameConfig(WorldKind.forest, 3), seed: 5);
    final m = game.maze as PolarMaze;
    expect(game.explored[m.start], isTrue);
    final atStart = game.exploredCount;
    expect(atStart, lessThan(m.cellCount ~/ 4), reason: 'most of the maze is hidden');

    final far = m.solution[m.solution.length ~/ 2];
    expect(game.explored[far], isFalse);

    game.started = true;
    game.pos = m.cellCenter(far);
    game.update(1 / 60, Offset.zero);
    expect(game.explored[far], isTrue);
    expect(game.exploredCount, greaterThan(atStart));
    final cells = game.exploredCount;

    // Memory persists while playing, and a restart forgets it.
    game.pos = m.cellCenter(m.start);
    game.update(1 / 60, Offset.zero);
    expect(game.explored[far], isTrue);
    expect(game.exploredCount, greaterThanOrEqualTo(cells));
    game.restart();
    expect(game.explored[far], isFalse);
    expect(game.exploredCount, atStart);
    game.dispose();
  });

  group('ball materials', () {
    GameController make(BallKind b, {WorldKind w = WorldKind.forest, int level = 3}) =>
        GameController(GameConfig(w, level, ball: b), hazardsEnabled: false, seed: 4);

    // Open ground just outside the entrance, and the direction pointing out.
    (Offset, Offset) outside(GameController g) {
      final m = g.maze as PolarMaze;
      final theta = (m.entrance + 0.5) * 2 * pi / m.sectors.last;
      final out = Offset(cos(theta), sin(theta));
      return (out * (m.radius + 0.6), out);
    }

    test('eight different materials, and the chameleon that borrows them', () {
      expect(BallKind.values.length, 9);
      final sizes = {for (final k in BallKind.values) statsOf(k).radius};
      expect(sizes.length, greaterThan(2));
      for (final k in BallKind.values) {
        final g = make(k);
        expect(g.ballRadius, GameController.baseBallRadius * statsOf(k).radius);
        g.dispose();
      }
      expect(make(BallKind.glass).ballRadius, lessThan(make(BallKind.wood).ballRadius));
      expect(make(BallKind.stone).ballRadius, greaterThan(make(BallKind.wood).ballRadius));
    });

    test('steel is loud, rubber is quiet', () {
      double noiseAt(BallKind b) {
        final g = make(b);
        final (p, out) = outside(g);
        g.started = true;
        g.pos = p;
        g.vel = Offset(-out.dy, out.dx) * 3; // sideways, no wall in the way
        g.update(1 / 60, Offset.zero);
        final n = g.noiseLevel;
        g.dispose();
        return n;
      }

      final wood = noiseAt(BallKind.wood);
      expect(noiseAt(BallKind.steel), greaterThan(wood));
      expect(noiseAt(BallKind.stone), lessThan(wood));
      expect(noiseAt(BallKind.rubber), lessThan(noiseAt(BallKind.stone)));
    });

    test('wind: stone and steel resist it, rubber is blown hardest', () {
      double pushed(BallKind b) {
        final g = make(b, w: WorldKind.mountains, level: 5);
        final (p, out) = outside(g);
        g.started = true;
        g.pos = p;
        g.vel = Offset.zero;
        g.windDir = Offset(-out.dy, out.dx);
        g.windLeft = 2;
        g.update(1 / 60, Offset.zero);
        final v = g.vel.distance;
        g.dispose();
        return v;
      }

      final wood = pushed(BallKind.wood);
      expect(pushed(BallKind.stone), lessThan(pushed(BallKind.steel)));
      expect(pushed(BallKind.steel), lessThan(wood));
      expect(pushed(BallKind.rubber), greaterThan(wood));
    });

    test('a stone ball sinks into a bog more slowly', () {
      double sunk(BallKind b) {
        final g = make(b, w: WorldKind.mud, level: 3);
        g.started = true;
        g.pos = g.mud.last.pos;
        for (var i = 0; i < 60; i++) {
          g.update(1 / 60, Offset.zero);
        }
        final s = g.sink;
        g.dispose();
        return s;
      }

      expect(sunk(BallKind.stone), lessThan(sunk(BallKind.wood)));
    });

    test('glass shatters on a hard hit, the others do not', () {
      bool breaks(BallKind b, double speed) {
        final g = make(b);
        final m = g.maze as PolarMaze;
        final n = m.sectors.last;
        final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n; // a closed stretch of wall
        final out = Offset(cos(theta), sin(theta));
        g.started = true;
        g.pos = out * (m.radius - 0.5);
        g.vel = out * speed;
        for (var i = 0; i < 30 && !g.lost; i++) {
          g.update(1 / 60, out * 1.0);
        }
        final lost = g.lost && g.lostReason == 'lose.glass';
        g.dispose();
        return lost;
      }

      expect(breaks(BallKind.glass, 6), isTrue);
      expect(breaks(BallKind.glass, 1.5), isFalse, reason: 'a gentle bump is fine');
      expect(breaks(BallKind.wood, 6), isFalse);
      expect(breaks(BallKind.steel, 6), isFalse);
    });

    test('rubber bounces back off a wall much more than wood or steel', () {
      double rebound(BallKind b) {
        final g = make(b);
        final m = g.maze as PolarMaze;
        final n = m.sectors.last;
        final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
        final out = Offset(cos(theta), sin(theta));
        g.started = true;
        g.pos = out * (m.radius - 0.9);
        g.vel = out * 3;
        var back = 0.0;
        for (var i = 0; i < 60; i++) {
          g.update(1 / 60, Offset.zero);
          final along = g.vel.dx * out.dx + g.vel.dy * out.dy;
          if (along < 0) {
            back = -along;
            break;
          }
        }
        g.dispose();
        return back;
      }

      final wood = rebound(BallKind.wood);
      expect(rebound(BallKind.rubber), greaterThan(wood));
      expect(rebound(BallKind.steel), lessThan(wood));
      expect(statsOf(BallKind.stone).bounce, lessThan(statsOf(BallKind.steel).bounce));
      expect(statsOf(BallKind.steel).bounce, lessThan(statsOf(BallKind.wood).bounce));
    });
  });

}

/// Unit vector pointing out of the maze through the entrance.
Offset polarOutward(GameController g) {
  final c = g.maze.cellCenter(g.maze.start);
  return c / c.distance;
}
