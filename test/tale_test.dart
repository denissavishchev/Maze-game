import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbyrinth/game/ball_collection.dart';
import 'package:orbyrinth/game/story.dart';
import 'package:orbyrinth/game/story_progress.dart';
import 'package:orbyrinth/game/tale.dart';
import 'package:orbyrinth/l10n/strings.dart';
import 'package:orbyrinth/ui/puzzle_screen.dart';
import 'package:orbyrinth/ui/story_map_screen.dart';
import 'package:orbyrinth/ui/tale_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> finish(Iterable<int> levels) async {
  for (final i in levels) {
    await StoryProgress.instance.record(i, 3, 1000);
  }
}

Iterable<int> chapters(int n) => Iterable.generate(n * StoryLevel.perChapter);

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  final story = StoryProgress.instance;
  final tale = TaleProgress.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    story.resetForTest();
    tale.resetForTest();
    await BallCollection.instance.reset();
  });

  testWidgets('the puzzle screens fit a small phone in every language', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(() => AppLanguage.instance.lang = AppLang.pl);
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    await finish([0]);
    for (final lang in AppLang.values) {
      AppLanguage.instance.lang = lang;
      for (final screen in [const PuzzleScreen(), PuzzleScreen(place: StoryLevel(0))]) {
        await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: screen));
        await settle(tester);
        expect(tester.takeException(), isNull);
      }
    }
  });

  test('every page has its picture and its text', () {
    final pages = <TalePage>[
      ...TalePages.intro,
      ...TalePages.finale,
      for (var c = 1; c <= StoryLevel.chapters; c++) ...[TalePages.card(c), ...TalePages.note(c)],
      ...TalePages.ending(endingOpen),
      ...TalePages.ending(endingStay),
    ];
    for (final p in pages) {
      expect(File(p.asset).existsSync(), isTrue, reason: p.asset);
      if (p.text != null) expect(translationTables[AppLang.pl]!.containsKey(p.text), isTrue, reason: p.text);
    }
    expect(File('assets/images/story/puzzle.webp').existsSync(), isTrue);
    expect(File('assets/images/story/puzzle_center_a.webp').existsSync(), isTrue);
    expect(File('assets/images/story/ending_b_3.webp').existsSync(), isTrue);
  });

  test('every level has its own place on the puzzle, and a tap finds it', () {
    final seen = <(int, int)>{};
    for (final l in StoryLevel.all) {
      expect(seen.add((Puzzle.ring(l), Puzzle.sector(l))), isTrue);
      final (x, y) = Puzzle.middleOf(l);
      expect(Puzzle.levelAt(x, y)!.index, l.index);
    }
    expect(Puzzle.levelAt(0, 0), isNull, reason: 'the middle is not a piece');
    expect(Puzzle.levelAt(0.99, 0.99), isNull, reason: 'outside the circle');
    final (x, y) = Puzzle.middleOf(StoryLevel(0));
    expect(x, greaterThan(0), reason: 'the first wedge lies right of twelve o\'clock');
    expect(y, lessThan(0));
  });

  test('the story tells each thing once, oldest first', () async {
    expect(tale.duePages(story).map((p) => p.image),
        ['intro_1', 'intro_2', 'intro_3', 'intro_4', 'chapter_1']);
    await tale.markTold(story);
    expect(tale.duePages(story), isEmpty);

    await finish(chapters(1));
    final pages = tale.duePages(story);
    expect(pages.map((p) => p.image), ['note_1', 'note_1', 'chapter_2']);
    expect(pages[1].ball, BallCollection.chapterRewards.first);
    await tale.markTold(story);
    expect(tale.duePages(story), isEmpty);
  });

  test('no note while the chapter is unfinished, no card while it is closed', () async {
    await tale.markTold(story);
    await finish(chapters(1).take(13));
    expect(tale.duePages(story), isEmpty);
  });

  test('a player with an old save gets what was missed', () async {
    await finish(chapters(2));
    expect(tale.duePages(story).map((p) => p.image), [
      'intro_1', 'intro_2', 'intro_3', 'intro_4',
      'chapter_1', 'note_1', 'note_1', 'chapter_2', 'note_2', 'note_2', 'chapter_3',
    ]);
  });

  test('what was told and the ending survive a restart', () async {
    await tale.markTold(story);
    await tale.setEnding(endingStay);
    tale.resetForTest();
    await tale.load();
    expect(tale.ending, endingStay);
    expect(tale.duePages(story), isEmpty);
  });

  test('the two endings differ', () {
    expect(TalePages.ending(endingOpen).map((p) => p.image), ['ending_a_1', 'ending_a_2', 'ending_a_3']);
    expect(TalePages.ending(endingStay).last.holdSeconds, 8);
  });

  testWidgets('first visit: the intro plays, a tap goes on, and it comes only once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StoryMapScreen()));
    await settle(tester);
    expect(find.text(tr('tale.intro.1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tale-page')));
    await settle(tester);
    expect(find.text(tr('tale.intro.2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tale-skip')));
    await settle(tester);
    expect(find.byKey(const Key('tale-page')), findsNothing);
    expect(find.byKey(const Key('story-node-0')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: StoryMapScreen()));
    await settle(tester);
    expect(find.byKey(const Key('tale-page')), findsNothing);
  });

  testWidgets('a new piece: dropped far away it goes back, tapped it lands', (tester) async {
    await finish([0]);
    await tester.pumpWidget(MaterialApp(home: PuzzleScreen(place: StoryLevel(0))));
    await settle(tester);
    expect(find.text(tr('tale.level.1')), findsNothing);
    await tester.drag(find.byKey(const Key('puzzle-piece')), const Offset(0, 30));
    await settle(tester);
    expect(find.byKey(const Key('puzzle-piece')), findsOneWidget);
    await tester.tap(find.byKey(const Key('puzzle-piece')));
    await settle(tester);
    expect(find.byKey(const Key('puzzle-piece')), findsNothing);
    expect(find.text(tr('tale.level.1')), findsOneWidget);
    expect(find.byKey(const Key('puzzle-next')), findsOneWidget);
  });

  testWidgets('dragged onto its place, the piece lands', (tester) async {
    await finish([0]);
    await tester.pumpWidget(MaterialApp(home: PuzzleScreen(place: StoryLevel(0))));
    await settle(tester);
    final from = tester.getCenter(find.byKey(const Key('puzzle-piece')));
    final board = tester.getRect(find.byKey(const Key('puzzle-board')));
    final (x, y) = Puzzle.middleOf(StoryLevel(0));
    final to = board.center + Offset(x, y) * (board.width / 2);
    await tester.dragFrom(from, to - from);
    await settle(tester);
    expect(find.byKey(const Key('puzzle-piece')), findsNothing);
  });

  for (final placing in [true, false]) {
    testWidgets('a double tap zooms the board on the same screen (placing: $placing)', (tester) async {
      await finish([0]);
      await tester.pumpWidget(
          MaterialApp(home: PuzzleScreen(place: placing ? StoryLevel(0) : null)));
      await settle(tester);
      final view = tester.widget<InteractiveViewer>(find.byKey(const Key('puzzle-view')));
      final controller = view.transformationController!;
      final at = tester.getCenter(find.byKey(const Key('puzzle-view')));
      Future<void> doubleTap() async {
        await tester.tapAt(at);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(at);
        await settle(tester);
      }

      expect(find.byKey(const Key('puzzle-hint')), findsOneWidget);
      await doubleTap();
      expect(controller.value.getMaxScaleOnAxis(), 3);
      expect(find.byType(PuzzleScreen), findsOneWidget);
      expect(find.byKey(const Key('puzzle-hint')), findsNothing, reason: 'the words give way');
      await doubleTap();
      expect(controller.value.getMaxScaleOnAxis(), 1);
      expect(find.byKey(const Key('puzzle-hint')), findsOneWidget);
      if (placing) expect(find.byKey(const Key('puzzle-piece')), findsOneWidget);
    });
  }

  testWidgets('zoomed, the board spans the whole screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PuzzleScreen()));
    await settle(tester);
    final view = tester.getRect(find.byKey(const Key('puzzle-view')));
    expect(view, Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio);
  });

  testWidgets('on a zoomed board the piece still lands where it belongs', (tester) async {
    await finish([0]);
    await tester.pumpWidget(MaterialApp(home: PuzzleScreen(place: StoryLevel(0))));
    await settle(tester);
    final viewer = find.byKey(const Key('puzzle-view'));
    final controller = tester.widget<InteractiveViewer>(viewer).transformationController!;
    final board = tester.getRect(find.byKey(const Key('puzzle-board')));
    final (x, y) = Puzzle.middleOf(StoryLevel(0));
    final spot = board.center + Offset(x, y) * (board.width / 2);
    final mid = tester.getRect(viewer).center;
    controller.value = Matrix4.identity()
      ..translateByDouble(mid.dx - spot.dx * 2, mid.dy - spot.dy * 2, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await settle(tester);
    final from = tester.getCenter(find.byKey(const Key('puzzle-piece')));
    await tester.dragFrom(from, mid - from);
    await settle(tester);
    expect(find.byKey(const Key('puzzle-piece')), findsNothing);
  });

  testWidgets('from the map, a tap on a found piece shows its line, a dark one nothing', (tester) async {
    await finish([0]);
    await tester.pumpWidget(const MaterialApp(home: PuzzleScreen()));
    await settle(tester);
    final board = tester.getRect(find.byKey(const Key('puzzle-board')));
    Offset at(int level) {
      final (x, y) = Puzzle.middleOf(StoryLevel(level));
      return board.center + Offset(x, y) * (board.width / 2);
    }

    await tester.tapAt(at(1));
    await settle(tester);
    expect(find.text(tr('tale.level.2')), findsNothing);
    await tester.tapAt(at(0));
    await settle(tester);
    expect(find.text(tr('tale.level.1')), findsOneWidget);
  });

  testWidgets('every reward has its painted ball', (tester) async {
    for (final b in BallCollection.chapterRewards) {
      final asset = rewardAsset(b);
      expect(asset, isNotNull, reason: b.name);
      expect(File(asset!).existsSync(), isTrue, reason: asset);
    }
    await tester.pumpWidget(MaterialApp(home: TaleScreen(pages: [TalePages.note(1)[1]])));
    await settle(tester);
    expect(find.byKey(const Key('tale-reward-ball')), findsOneWidget);
  });

  testWidgets('the silence waits while the game is away', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => TextButton(
        onPressed: () => showTale(context, TalePages.ending(endingStay).sublist(1)),
        child: const Text('go'),
      ),
    )));
    await tester.tap(find.text('go'));
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 20));
    expect(find.byType(TaleScreen), findsOneWidget, reason: 'the time away does not count');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 9));
    await settle(tester);
    expect(find.byType(TaleScreen), findsNothing);
  });

  testWidgets('the mirror stays shut until the last chapter is finished', (tester) async {
    tale.skipForTest();
    await tester.pumpWidget(const MaterialApp(home: StoryMapScreen()));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('story-mirror')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('story-mirror')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TaleScreen), findsNothing);
  });

  testWidgets('the whole ending: mirror, choice, silence, puzzle, thanks', (tester) async {
    await finish(chapters(5));
    await tale.markTold(story);
    tester.view.physicalSize = const Size(1170, 2532);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: StoryMapScreen()));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('story-mirror')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('story-mirror')));
    await settle(tester);
    for (final key in ['tale.final.1', 'tale.final.2', 'tale.final.3', 'tale.final.4']) {
      expect(find.text(tr(key)), findsOneWidget);
      await tester.tap(find.byKey(const Key('tale-page')));
      await settle(tester);
    }
    await tester.tap(find.byKey(const Key('tale-stay')));
    await settle(tester);
    expect(tale.ending, endingStay);

    expect(find.text(tr('tale.ending.b.1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tale-page')));
    await settle(tester);
    expect(find.byKey(const Key('tale-skip')), findsNothing, reason: 'the silence takes no touch');
    await tester.tap(find.byKey(const Key('tale-page')), warnIfMissed: false);
    await settle(tester);
    expect(find.byKey(const Key('puzzle-next')), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    await settle(tester);

    expect(find.text(tr('tale.ending.b.3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('puzzle-next')));
    await settle(tester);
    expect(find.byKey(const Key('credits-title')), findsOneWidget);
    expect(find.text(tr('tale.credits')), findsOneWidget);
    expect(find.text(tr('tale.ending.chameleon')), findsOneWidget, reason: 'no chameleon yet');
    await tester.tap(find.byKey(const Key('credits-back')));
    await settle(tester);
    expect(find.byType(CreditsScreen), findsNothing);
    expect(find.byKey(const Key('story-mirror')), findsOneWidget, reason: 'back on the map');
  });
}
