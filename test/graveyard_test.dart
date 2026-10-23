import 'package:flutter_test/flutter_test.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/world.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/worlds.dart';

GameController yard({int level = 2, int seed = 3}) => GameController(
      GameConfig(WorldKind.graveyard, level),
      seed: seed,
    );

/// Wakes the first ghost and puts it a few cells from the ball.
Creature wake(GameController g, {double dist = 4}) {
  final ghost = g.creatures.first;
  g.started = true;
  ghost.asleep = false;
  ghost.grace = 0;
  ghost.awakeTimer = 30;
  ghost.pos = g.pos + Offset(dist, 0);
  return ghost;
}

void main() {
  test('the graveyard has ghosts (asleep at first, far from the start) and fog', () {
    final g = yard(level: 3);
    expect(g.creatures.length, g.config.chaserCount);
    for (final c in g.creatures) {
      expect(c.asleep, isTrue);
      expect((c.pos - g.pos).distance, greaterThan(6));
    }
    expect(g.fog.length, g.config.fogCount);
    expect(g.mud, isEmpty);
    expect(g.lasers, isEmpty);
  });

  test('a ghost floats straight at the ball, through the walls', () {
    final g = yard(level: 3, seed: 5);
    final ghost = wake(g, dist: 5);
    // A ball that keeps rolling back and forth, never still.
    var closest = (ghost.pos - g.pos).distance;
    for (var i = 0; i < 60 * 10 && !g.lost; i++) {
      g.update(1 / 60, Offset(i % 120 < 60 ? 0.3 : -0.3, 0));
      final d = (ghost.pos - g.pos).distance;
      closest = d < closest ? d : closest;
    }
    expect(closest, lessThan(1.0), reason: 'it came right at the ball');
    // Straight in: the maze is full of walls, yet it arrives in a few seconds.
    expect(g.lost, isTrue, reason: 'caught by the ghost');
    expect(g.lostReason, 'lose.ghost');
  });

  test('a ghost lies down when the ball stands still', () {
    final g = yard(level: 3, seed: 5);
    final ghost = wake(g, dist: 8);
    for (var i = 0; i < 60 * 8; i++) {
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isFalse);
    expect(ghost.asleep, isTrue, reason: 'lost interest and fell asleep');
  });

  test('a loud bump wakes a sleeping ghost', () {
    final g = yard(level: 3, seed: 5);
    final ghost = g.creatures.first;
    expect(ghost.asleep, isTrue);
    ghost.pos = g.pos + const Offset(1.5, 0);
    g.started = true;
    g.noise(g.pos);
    expect(ghost.asleep, isFalse);
  });

  test('holy water drives the ghosts off for its time, and they cannot catch the ball', () {
    final g = yard(level: 3, seed: 5);
    final ghost = wake(g, dist: 1.0);
    g.bonusCharges = 1;
    g.useBonus();
    expect(ghost.lockLeft, greaterThan(0));
    var farthest = 0.0;
    for (var i = 0; i < 60 * 8; i++) {
      g.update(1 / 60, const Offset(0.2, 0));
      final d = (ghost.pos - g.pos).distance;
      farthest = d > farthest ? d : farthest;
      expect(g.lost, isFalse, reason: 'not while the water works');
    }
    expect(farthest, greaterThan(2.5), reason: 'it fled');
  });

  test('cold fog slows the ball down, it does not stop it', () {
    double topSpeedIn(bool fogged) {
      final g = GameController(const GameConfig(WorldKind.graveyard, 2),
          hazardsEnabled: false, seed: 3);
      g.started = true;
      final at = g.maze.cellCenter(g.maze.start);
      g.fog
        ..clear()
        ..addAll(fogged ? [MudPatch(at, 30)] : const []);
      var top = 0.0;
      for (var i = 0; i < 90; i++) {
        g.pos = at;
        g.update(1 / 60, const Offset(0, 0.9));
        top = g.vel.distance > top ? g.vel.distance : top;
      }
      return top;
    }

    final free = topSpeedIn(false);
    final slow = topSpeedIn(true);
    expect(slow, lessThan(free * 0.7));
    expect(slow, greaterThan(0.5));
  });

  test('a grave cracks first, then caves in, and it is deadly only once open', () {
    final g = yard(level: 3, seed: 5);
    g.started = true;
    g.spawnTrap();
    expect(g.hazards, isNotEmpty);
    final grave = g.hazards.first;
    expect(grave.armAt, greaterThan(1.0), reason: 'a longer warning than spikes');
    // On a cracking grave: still safe.
    g.pos = grave.pos;
    g.update(0.5, Offset.zero);
    expect(g.lost, isFalse);
    // Once it has fallen in, standing there is fatal.
    for (var i = 0; i < 60 * 2 && !g.lost; i++) {
      g.pos = grave.pos;
      g.update(1 / 60, Offset.zero);
    }
    expect(g.lost, isTrue);
    expect(g.lostReason, 'lose.grave');
  });

  test('the graveyard is named, described, and has its texts in every language', () {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    final names = <String>{};
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      final t = themeFor(WorldKind.graveyard);
      expect(t.name, isNot(startsWith('world.')));
      expect(t.blurb, isNot(startsWith('world.')));
      expect(tr('bonus.graveyard'), isNot(startsWith('bonus.')));
      expect(tr('lose.ghost'), isNot(startsWith('lose.')));
      expect(tr('lose.grave'), isNot(startsWith('lose.')));
      expect(hazardNote(const GameConfig(WorldKind.graveyard, 2)), isNot(startsWith('note.')));
      names.add(t.name);
    }
    expect(names.length, 3);
  });
}
