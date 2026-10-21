import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/audio/haptics.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/world.dart';

List<Haptic> hitWall(double speed, {int frames = 40}) {
  final g = GameController(const GameConfig(WorldKind.forest, 3),
      hazardsEnabled: false, seed: 4);
  final m = g.maze;
  final n = m.sectors.last;
  final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
  final out = Offset(cos(theta), sin(theta));
  g.started = true;
  g.pos = out * (m.radius - 1.0);
  g.vel = out * speed;
  Haptics.record!.clear();
  for (var i = 0; i < frames; i++) {
    g.update(1 / 60, Offset.zero);
  }
  g.dispose();
  return List.of(Haptics.record!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Haptics.record = []);
  tearDown(() {
    Haptics.record = null;
    Haptics.enabled = false;
    VibrationSetting.instance.on = true;
  });

  test('a hit on a wall is felt: a faint tick when soft, a firmer bump when hard', () {
    expect(hitWall(2.4), contains(Haptic.tick));
    expect(hitWall(2.4), isNot(contains(Haptic.bump)));
    expect(hitWall(4.8), contains(Haptic.bump));
    expect(hitWall(0.5), isEmpty, reason: 'too gentle to feel');
  });

  test('pressing against a wall does not buzz every frame', () {
    final g = GameController(const GameConfig(WorldKind.forest, 3),
        hazardsEnabled: false, seed: 4);
    final m = g.maze;
    final n = m.sectors.last;
    final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
    final out = Offset(cos(theta), sin(theta));
    g.started = true;
    g.pos = out * (m.radius - 0.6);
    g.vel = out * 4;
    Haptics.record!.clear();
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, out);
    }
    expect(Haptics.record!.length, lessThan(12));
    g.dispose();
  });

  test('a loud ball ticks gently now and then where noise matters, and nowhere else', () {
    int ticksFor(WorldKind world, double noise) {
      final g = GameController(GameConfig(world, 2), hazardsEnabled: false, seed: 6);
      g.started = true;
      g.forcedNoise = noise;
      g.forcedStill = 0;
      g.pos = g.maze.cellCenter(g.maze.start);
      Haptics.record!.clear();
      for (var i = 0; i < 120; i++) { // two seconds
        g.pos = g.maze.cellCenter(g.maze.start);
        g.vel = Offset.zero;
        g.update(1 / 60, Offset.zero);
      }
      final n = Haptics.record!.length;
      expect(Haptics.record!.every((h) => h == Haptic.tick), isTrue, reason: 'only faint ticks');
      g.dispose();
      return n;
    }

    final loud = ticksFor(WorldKind.forest, 0.9);
    expect(loud, inInclusiveRange(4, 7), reason: 'about every third of a second');
    expect(ticksFor(WorldKind.city, 0.9), inInclusiveRange(4, 7));
    expect(ticksFor(WorldKind.forest, 0.3), 0, reason: 'quiet: nothing to report');
    expect(ticksFor(WorldKind.mud, 0.9), 0, reason: 'noise does not matter in the mud');
    expect(ticksFor(WorldKind.underground, 0.9), 0);
  });

  test('nothing vibrates when the setting is off', () {
    Haptics.enabled = true;
    VibrationSetting.instance.on = true;
    expect(Haptics.active, isTrue);
    VibrationSetting.instance.on = false;
    expect(Haptics.active, isFalse);
  });
}
