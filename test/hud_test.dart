import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/world.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/game_screen.dart';

void main() {
  testWidgets('the noise bar only exists where noise matters; no bog bar at all', (tester) async {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    for (final world in WorldKind.values) {
      await tester.pumpWidget(MaterialApp(
        home: GameScreen(config: GameConfig(world, 2)),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      final hasNoise = find.text(tr('meter.noise')).evaluate().isNotEmpty;
      expect(
          hasNoise,
          world == WorldKind.forest || world == WorldKind.city || world == WorldKind.graveyard,
          reason: '${world.name}: noise bar');
      // The calibration button sits in the top bar.
      expect(find.byIcon(Icons.screen_rotation_alt_rounded), findsOneWidget,
          reason: '${world.name}: calibrate button');
      // The sinking is shown on the ball itself; there is no bar for it.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      // Leave the game screen so its ticker stops before the next world.
      await tester.pumpWidget(const SizedBox());
    }
  });
}
