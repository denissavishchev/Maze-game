import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/game/world.dart';
import 'package:maze/ui/kit.dart';
import 'package:maze/ui/menu_screen.dart';
import 'package:maze/ui/worlds.dart';

void main() {
  testWidgets('selection screen never overflows, even with large fonts', (tester) async {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    for (final lang in AppLang.values) {
      // Not awaited: saving to storage never completes inside a widget test.
      // ignore: unawaited_futures
      AppLanguage.instance.set(lang);
      for (final scale in [1.0, 1.3, 1.6]) {
      for (final size in [const Size(360, 640), const Size(390, 844), const Size(320, 568)]) {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
            child: const MaterialApp(home: SelectScreen()),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '${lang.name} scale $scale at $size');

        // Switching worlds and balls changes the descriptions: still fits.
        await tester.ensureVisible(find.text(tr('world.mountains.name')).first);
        await tester.tap(find.text(tr('world.mountains.name')).first);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.ensureVisible(find.text(tr('ball.steel.name')).first);
        await tester.tap(find.text(tr('ball.steel.name')).first);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: 'after selecting, ${lang.name} scale $scale at $size');
      }
      }
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('selecting a world recolours the menu to match it', (tester) async {
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    AppLanguage.instance.lang = AppLang.pl;
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SelectScreen()));
    await tester.pump(const Duration(milliseconds: 500));

    final seen = <Color>{};
    for (final w in WorldKind.values) {
      await tester.tap(find.text(themeFor(w).name).first);
      await tester.pump(const Duration(milliseconds: 500));
      final theme = themeFor(w);
      // Every panel on the screen wears the world's colours.
      final panels = tester.widgetList<Chunky>(find.byType(Chunky)).toList();
      expect(panels, isNotEmpty);
      for (final p in panels) {
        expect(p.colors, theme.panel, reason: '${w.name}: panel colours');
      }
      // The backdrop is tinted with the world's accent.
      final backdrop = tester.widget<ArtBackdrop>(find.byType(ArtBackdrop));
      expect(backdrop.tint, theme.accent, reason: '${w.name}: backdrop tint');
      // The play button uses the accent too.
      final play = tester.widget<ChunkyButton>(find.byType(ChunkyButton));
      expect(play.tint, theme.accent, reason: '${w.name}: play button');
      seen.add(theme.accent);
    }
    expect(seen.length, WorldKind.values.length, reason: 'every world has its own colour');
  });
}
