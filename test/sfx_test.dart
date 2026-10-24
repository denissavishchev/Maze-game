import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:maze/audio/sfx.dart';
import 'package:maze/game/ball.dart';
import 'package:maze/game/game_controller.dart';
import 'package:maze/game/polar_maze.dart';
import 'package:maze/game/world.dart';

Sound impactOf(BallKind k) => switch (k) {
      BallKind.wood => Sound.impactWood,
      BallKind.steel => Sound.impactSteel,
      BallKind.rubber => Sound.impactRubber,
      BallKind.glass => Sound.impactGlass,
      BallKind.stone => Sound.impactStone,
      BallKind.slime => Sound.impactSlime,
      BallKind.paper => Sound.impactPaper,
    };

/// Drives the ball into a stretch of closed outer wall at [speed].
List<(Sound, double)> hitWall(BallKind kind, double speed, {int frames = 40}) {
  final g = GameController(GameConfig(WorldKind.forest, 3, ball: kind),
      hazardsEnabled: false, seed: 4);
  final m = g.maze as PolarMaze;
  final n = m.sectors.last;
  final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
  final out = Offset(cos(theta), sin(theta));
  g.started = true;
  g.pos = out * (m.radius - 1.0);
  g.vel = out * speed;
  Sfx.record!.clear();
  for (var i = 0; i < frames; i++) {
    g.update(1 / 60, Offset.zero);
  }
  g.dispose();
  return List.of(Sfx.record!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => Sfx.record = []);
  tearDown(() => Sfx.record = null);

  test('every sound is a valid, audible, non-clipping WAV file', () {
    for (final s in Sound.values) {
      final bytes = Sfx.wavFor(s);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      final data = ByteData.sublistView(bytes);
      final samples = (bytes.length - 44) ~/ 2;
      expect(samples, greaterThan(22050 * 0.1), reason: '$s is long enough to hear');
      var peak = 0;
      for (var i = 0; i < samples; i++) {
        peak = max(peak, data.getInt16(44 + i * 2, Endian.little).abs());
      }
      expect(peak, greaterThan(8000), reason: '$s is audible');
      expect(peak, lessThan(32767), reason: '$s does not clip');
    }
  });

  test('a hit on a wall plays the sound of the ball material', () {
    for (final kind in BallKind.values) {
      final played = hitWall(kind, 3.5);
      expect(played, isNotEmpty, reason: '$kind: no sound on impact');
      expect({for (final p in played) p.$1}, {impactOf(kind)});
    }
  });

  test('harder hits are louder, and gentle contact is silent', () {
    final soft = hitWall(BallKind.wood, 1.6).first.$2;
    final hard = hitWall(BallKind.wood, 4.8).first.$2;
    expect(hard, greaterThan(soft));
    expect(hitWall(BallKind.wood, 0.5), isEmpty, reason: 'too gentle to hear');
  });

  test('pressing against a wall does not rattle every frame', () {
    final g = GameController(const GameConfig(WorldKind.forest, 3),
        hazardsEnabled: false, seed: 4);
    final m = g.maze as PolarMaze;
    final n = m.sectors.last;
    final theta = ((m.entrance + n ~/ 2) % n + 0.5) * 2 * pi / n;
    final out = Offset(cos(theta), sin(theta));
    g.started = true;
    g.pos = out * (m.radius - 0.6);
    g.vel = out * 4;
    Sfx.record!.clear();
    for (var i = 0; i < 120; i++) {
      g.update(1 / 60, out); // 2 seconds of leaning on the wall
    }
    expect(Sfx.record!.length, lessThan(12), reason: 'at most ~10 per second, usually far fewer');
    g.dispose();
  });

  test('a wolf waking up growls once, louder when close', () {
    double growl(Offset away) {
      final g = GameController(const GameConfig(WorldKind.forest, 2), seed: 14);
      final wolf = g.creatures.first;
      g.pos = wolf.pos + away;
      Sfx.record!.clear();
      g.noise(wolf.pos);
      g.noise(wolf.pos); // already awake: silent
      final woke = Sfx.record!.where((p) => p.$1 == Sound.wolfWake).toList();
      expect(woke, hasLength(1));
      g.dispose();
      return woke.first.$2;
    }

    expect(growl(const Offset(1.5, 0)), greaterThan(growl(const Offset(9, 0))));
  });

  test('a drone waking up whirs once', () {
    final g = GameController(const GameConfig(WorldKind.city, 2), seed: 18);
    final d = g.creatures.first;
    expect(d.asleep, isTrue);
    Sfx.record!.clear();
    g.noise(d.pos);
    expect(Sfx.record!.where((p) => p.$1 == Sound.droneWake), hasLength(1));
    g.noise(d.pos); // awake already
    expect(Sfx.record!.where((p) => p.$1 == Sound.droneWake), hasLength(1));
    g.dispose();
  });
}
