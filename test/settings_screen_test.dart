import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maze/audio/haptics.dart';
import 'package:maze/audio/sfx.dart';
import 'package:maze/audio/sound_setting.dart';
import 'package:maze/l10n/strings.dart';
import 'package:maze/ui/home_screen.dart';
import 'package:maze/ui/settings_screen.dart';

Future<void> show(WidgetTester tester, {Size size = const Size(390, 844), double scale = 1}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: const MaterialApp(home: SettingsScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  tearDown(() {
    AppLanguage.instance.lang = AppLang.pl;
    SoundSetting.instance.on = true;
    VibrationSetting.instance.on = true;
    Sfx.enabled = false;
    Haptics.enabled = false;
  });

  testWidgets('the title on the main screen follows the language chosen in settings', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('LABIRYNT'), findsOneWidget);
    AppLanguage.instance.lang = AppLang.en;
    AppLanguage.instance.notifyListeners();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('MAZE'), findsOneWidget);
    expect(find.text('LABIRYNT'), findsNothing);
  });

  testWidgets('the language buttons change every text on the screen', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    await show(tester);
    expect(find.text('USTAWIENIA'), findsOneWidget);
    expect(find.text('Język'), findsOneWidget);
    expect(find.text('Dźwięk'), findsOneWidget);

    // Each language is offered by its own name.
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(AppLanguage.instance.lang, AppLang.en);

    await tester.tap(find.text('Русский'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    expect(find.text('Звук'), findsOneWidget);

    await tester.tap(find.text('Polski'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('USTAWIENIA'), findsOneWidget);
  });

  testWidgets('the highlighted language is the selected one', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    await show(tester);
    Color labelColor(String l) => tester.widget<Text>(find.text(l)).style!.color!;
    expect(labelColor('PL'), const Color(0xFF5A3720), reason: 'dark text on the gold button');
    expect(labelColor('EN'), const Color(0xFFFBF1D2));
    await tester.tap(find.text('English'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(labelColor('EN'), const Color(0xFF5A3720));
    expect(labelColor('PL'), const Color(0xFFFBF1D2));
  });

  testWidgets('the sound switch turns sound effects off and on', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    SoundSetting.instance.on = true;
    Sfx.enabled = true; // as the running app has it
    await show(tester);
    expect(find.text('Włączony'), findsOneWidget);
    expect(Sfx.audible, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(SoundSetting.instance.on, isFalse);
    expect(find.text('Wyłączony'), findsOneWidget);
    expect(Sfx.audible, isFalse, reason: 'nothing plays with sound off');

    await tester.tap(find.byType(Switch).first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(SoundSetting.instance.on, isTrue);
    expect(Sfx.audible, isTrue);
  });

  testWidgets('the vibration switch turns vibration off and on', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    VibrationSetting.instance.on = true;
    Haptics.enabled = true;
    await show(tester);
    expect(find.text('Wibracje'), findsOneWidget);
    expect(find.textContaining('Włączone'), findsOneWidget);
    expect(Haptics.active, isTrue);

    await tester.tap(find.byType(Switch).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(VibrationSetting.instance.on, isFalse);
    expect(find.text('Wyłączone'), findsOneWidget);
    expect(Haptics.active, isFalse, reason: 'nothing vibrates with it off');

    await tester.tap(find.byType(Switch).last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(VibrationSetting.instance.on, isTrue);
  });

  testWidgets('the test button plays a sound, and a playback error is shown', (tester) async {
    AppLanguage.instance.lang = AppLang.pl;
    SoundSetting.instance.on = true;
    Sfx.record = [];
    addTearDown(() {
      Sfx.record = null;
      Sfx.lastError.value = null;
    });
    await show(tester);
    await tester.tap(find.text('Sprawdź dźwięk'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(Sfx.record!.map((p) => p.$1), [Sound.impactWood]);

    // When the audio plugin is missing the reason is shown to the player.
    expect(find.textContaining('Dźwięk nie działa'), findsNothing);
    Sfx.lastError.value = 'MissingPluginException';
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('MissingPluginException'), findsOneWidget);
    expect(find.textContaining('uruchom ją od nowa'), findsOneWidget);

    // With sound off the test button is disabled.
    SoundSetting.instance.on = false;
    SoundSetting.instance.notifyListeners();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
  });

  testWidgets('settings never overflow: small screens, large fonts, every language', (tester) async {
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final scale in [1.0, 1.3, 1.6]) {
        for (final size in [const Size(320, 568), const Size(360, 640), const Size(390, 844)]) {
          await show(tester, size: size, scale: scale);
          expect(tester.takeException(), isNull, reason: '${lang.name} scale $scale at $size');
        }
      }
    }
  });
}
