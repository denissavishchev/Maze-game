import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball.dart';
import 'package:orbyrinth/game/ball_collection.dart';
import 'package:orbyrinth/game/game_controller.dart';
import 'package:orbyrinth/game/story.dart';
import 'package:orbyrinth/game/story_progress.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/ball_shop.dart';
import 'package:orbyrinth/ui/game_screen.dart';
import 'package:orbyrinth/ui/home_screen.dart';
import 'package:orbyrinth/ui/kit.dart';
import 'package:orbyrinth/ui/menu_screen.dart';
import 'package:orbyrinth/ui/settings_screen.dart';
import 'package:orbyrinth/ui/story_map_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smallest gap, in logical pixels, between a button's label and the edge of
/// the button.
const double minGap = 8;

/// A label may be shrunk to fit, but not below this share of its size. Tests
/// draw text in the Ahem font, whose letters are about twice as wide as real
/// ones, so 0.38 here is about 0.7 on a phone.
const double minScale = 0.38;

const sizes = [Size(320, 568), Size(360, 640), Size(390, 844)];

/// Every label that sits on a button or a tile, with the button it sits on.
List<String> crowded(WidgetTester tester, String where) {
  final problems = <String>[];
  final roots = <Finder>[
    find.byType(ChunkyButton),
    find.byType(ButtonStyleButton),
    find.byType(InkWell),
  ];
  final seen = <Element>{};
  for (final root in roots) {
    for (final e in root.evaluate()) {
      if (!seen.add(e)) continue;
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      final outer = tester.getRect(find.byElementPredicate((x) => x == e));
      // Rows that stretch across a list are not buttons with a label.
      for (final t in find
          .descendant(of: find.byElementPredicate((x) => x == e), matching: find.byType(Text))
          .evaluate()) {
        final text = (t.widget as Text).data ?? '';
        if (text.isEmpty) continue;
        final r = tester.getRect(find.byElementPredicate((x) => x == t));
        final natural = t.renderObject is RenderBox ? (t.renderObject! as RenderBox).size.width : r.width;
        final shrink = natural == 0 ? 1.0 : r.width / natural;
        if (shrink < minScale) {
          problems.add('$where: "$text" shrunk to ${(shrink * 100).round()}%');
        }
        if (r.left < outer.left + minGap - 0.5 || r.right > outer.right - minGap + 0.5) {
          problems.add('$where: "$text" ${r.left.toStringAsFixed(1)}..${r.right.toStringAsFixed(1)}'
              ' in ${outer.left.toStringAsFixed(1)}..${outer.right.toStringAsFixed(1)}');
        }
      }
    }
  }
  return problems;
}

Future<void> show(WidgetTester tester, Size size, Widget home, {double scale = 1}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
    child: MaterialApp(key: UniqueKey(), home: home),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

GameController lostEndless() {
  for (var seed = 0; seed < 300; seed++) {
    final c = GameController(GameController.endlessConfig(0, BallKind.wood),
        endless: true, seed: seed);
    c.started = true;
    var n = 0;
    while (c.status == GameStatus.playing && n++ < 6000) {
      c.update(1 / 60, Offset.zero);
    }
    if (c.lost) return c;
  }
  throw StateError('nothing lost');
}

GameController storyController(StoryLevel level, {required bool win}) {
  final c = GameController(level.config(BallKind.wood), seed: 3);
  c.started = true;
  if (win) {
    c.pos = c.maze.cellCenter(c.maze.goal);
    c.update(1 / 60, Offset.zero);
  } else {
    var n = 0;
    while (c.status == GameStatus.playing && n++ < 6000) {
      c.update(1 / 60, Offset.zero);
    }
  }
  return c;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StoryProgress.instance.resetForTest();
    await BallCollection.instance.reset();
  });
  tearDown(() => AppLanguage.instance.lang = AppLang.pl);

  testWidgets('no label comes closer than 8 to the edge of its button', (tester) async {
    addTearDown(tester.view.reset);
    final problems = <String>{};
    final screens = <String, Widget Function()>{
      'home': () => const HomeScreen(),
      'single': () => const SelectScreen(),
      'endless': () => const SelectScreen(endless: true),
      'settings': () => const SettingsScreen(),
      'story map': () => const StoryMapScreen(),
      'endless lost': () {
        final g = lostEndless();
        return GameScreen(config: g.config, endless: true, controller: g);
      },
      'single lost': () {
        final g = storyController(StoryLevel(0), win: false);
        return GameScreen(config: g.config, controller: g);
      },
      'story lost': () {
        final l = StoryLevel(0);
        final g = storyController(l, win: false);
        return GameScreen(config: g.config, story: l, controller: g);
      },
      'story won': () {
        final l = StoryLevel(0);
        final g = storyController(l, win: true);
        return GameScreen(config: g.config, story: l, controller: g);
      },
      'single won': () {
        final g = storyController(StoryLevel(0), win: true);
        return GameScreen(config: g.config, controller: g);
      },
    };
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final size in sizes) {
        for (final entry in screens.entries) {
          await show(tester, size, entry.value());
          problems.addAll(crowded(tester, '${lang.name} ${size.width.toInt()} ${entry.key}'));
          final error = tester.takeException();
          if (error != null) {
            problems.add('${lang.name} ${size.width.toInt()} ${entry.key}: '
                '${error.toString().split('\n').first}');
          }
        }
        // Sheets.
        await show(tester, size, Builder(builder: (c) {
          return Scaffold(
            body: Column(children: [
              TextButton(key: const Key('shop'), onPressed: () => showBallShop(c), child: const Text('shop')),
            ]),
          );
        }));
        await tester.tap(find.byKey(const Key('shop')));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        problems.addAll(crowded(tester, '${lang.name} ${size.width.toInt()} ball shop'));

        // The start sheet of a story level.
        await show(tester, size, const StoryMapScreen());
        await tester.tap(find.byKey(const Key('story-node-0')));
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        problems.addAll(crowded(tester, '${lang.name} ${size.width.toInt()} start sheet'));
        final sheetError = tester.takeException();
        if (sheetError != null) {
          problems.add('${lang.name} ${size.width.toInt()} start sheet: '
              '${sheetError.toString().split('\n').first}');
        }
        final shopError = tester.takeException();
        if (shopError != null) {
          problems.add('${lang.name} ${size.width.toInt()} ball shop: '
              '${shopError.toString().split('\n').first}');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
