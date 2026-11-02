import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ball.dart';
import 'ball_collection.dart';
import 'story.dart';
import 'story_progress.dart';

/// One screen of the tale: a picture with a line under it, in text keys.
class TalePage {
  const TalePage(
    this.image, {
    this.text,
    this.ball,
    this.holdSeconds,
    this.choice = false,
  });

  /// Name of the file in assets/images/story, without the extension.
  final String image;
  final String? text;

  /// A ball just won, shown over the picture.
  final BallKind? ball;

  /// The page stands this long and takes no touch, then moves on by itself.
  final int? holdSeconds;

  /// The last page of the way to the mirror: the player picks an ending.
  final bool choice;

  String get asset => 'assets/images/story/$image.webp';
}

/// The two endings, as stored.
const String endingOpen = 'a';
const String endingStay = 'b';

/// The pages of the story, in the order the player meets them.
class TalePages {
  static const List<TalePage> intro = [
    TalePage('intro_1', text: 'tale.intro.1'),
    TalePage('intro_2', text: 'tale.intro.2'),
    TalePage('intro_3', text: 'tale.intro.3'),
    TalePage('intro_4', text: 'tale.intro.4'),
  ];

  static TalePage card(int chapter) =>
      TalePage('chapter_$chapter', text: 'tale.chapter.$chapter.card');

  /// The note at the end of a chapter and the ball it gave.
  static List<TalePage> note(int chapter) => [
        TalePage('note_$chapter', text: 'tale.chapter.$chapter.note'),
        TalePage(
          'note_$chapter',
          text: 'tale.chapter.$chapter.reward',
          ball: BallCollection.chapterRewards[chapter - 1],
        ),
      ];

  static const List<TalePage> finale = [
    TalePage('final_1', text: 'tale.final.1'),
    TalePage('final_2', text: 'tale.final.2'),
    TalePage('final_3', text: 'tale.final.3'),
    TalePage('final_4', text: 'tale.final.4'),
    TalePage('final_5', choice: true),
  ];

  static List<TalePage> ending(String ending) => ending == endingOpen
      ? const [
          TalePage('ending_a_1', text: 'tale.ending.a.1'),
          TalePage('ending_a_2', text: 'tale.ending.a.2'),
          TalePage('ending_a_3', text: 'tale.ending.a.3'),
        ]
      : const [
          TalePage('ending_b_1', text: 'tale.ending.b.1'),
          TalePage('ending_b_2', holdSeconds: 8),
        ];
}

/// The round puzzle: one piece per story level, five rings of fourteen wedges.
/// The first chapter is the outer ring; the first wedge starts at twelve
/// o'clock and they go clockwise. Sizes are shares of the picture's half width.
class Puzzle {
  static const double outer = 1000 / 1024;
  static const double inner = 240 / 1024;
  static double get wedge => 2 * pi / StoryLevel.perChapter;

  /// Where the rings meet in each wedge, from the rim inwards, in pixels of
  /// the 2048 picture from its centre. The painting does not keep its rings
  /// at one radius all the way round, so each wedge is cut along its own.
  static const List<List<int>> _borders = [
    [1000, 817, 676, 535, 389, 240],
    [1000, 816, 674, 534, 388, 240],
    [1000, 811, 671, 528, 384, 240],
    [1000, 815, 669, 520, 375, 240],
    [1000, 876, 665, 520, 373, 240],
    [1000, 811, 664, 510, 367, 240],
    [1000, 812, 659, 510, 361, 240],
    [1000, 904, 659, 493, 360, 240],
    [1000, 810, 664, 505, 365, 240],
    [1000, 793, 664, 513, 371, 240],
    [1000, 855, 668, 515, 374, 240],
    [1000, 878, 670, 529, 380, 240],
    [1000, 816, 674, 536, 389, 240],
    [1000, 818, 676, 535, 390, 240],
  ];

  static int ring(StoryLevel level) => level.chapter - 1;
  static int sector(StoryLevel level) => level.number - 1;

  static double _border(int sector, int i) => _borders[sector][i] / 1024;

  /// Outer and inner radius of [level]'s piece.
  static double radiusOf(StoryLevel level) => _border(sector(level), ring(level));
  static double innerOf(StoryLevel level) => _border(sector(level), ring(level) + 1);

  /// Angle of the start of [level]'s piece.
  static double angleOf(StoryLevel level) => -pi / 2 + sector(level) * wedge;

  /// The middle of [level]'s piece, from the centre of the picture.
  static (double, double) middleOf(StoryLevel level) {
    final r = (radiusOf(level) + innerOf(level)) / 2;
    final a = angleOf(level) + wedge / 2;
    return (r * cos(a), r * sin(a));
  }

  /// The level whose piece is at ([x], [y]) from the centre of the picture.
  static StoryLevel? levelAt(double x, double y) {
    final d = sqrt(x * x + y * y);
    if (d >= outer || d < inner) return null;
    final a = (atan2(y, x) + pi / 2) % (2 * pi);
    final s = (a / wedge).floor() % StoryLevel.perChapter;
    for (var r = 0; r < StoryLevel.chapters; r++) {
      if (d >= _border(s, r + 1)) return StoryLevel(r * StoryLevel.perChapter + s);
    }
    return null;
  }
}

/// What the player has already been told, and how the story ended.
class TaleProgress extends ChangeNotifier {
  TaleProgress._();

  static final TaleProgress instance = TaleProgress._();

  static const _key = 'tale_v1';

  bool _intro = false;
  final Set<int> _cards = {};
  final Set<int> _notes = {};
  String? _ending;

  /// The ending chosen last, which fills the middle of the puzzle.
  String? get ending => _ending;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _intro = m['intro'] as bool;
        _cards.addAll((m['cards'] as List).cast<int>());
        _notes.addAll((m['notes'] as List).cast<int>());
        _ending = m['ending'] as String?;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'intro': _intro,
          'cards': _cards.toList(),
          'notes': _notes.toList(),
          'ending': _ending,
        }),
      );
    } catch (_) {}
  }

  /// What the story still has to tell, oldest first: the intro, then the card
  /// of each open chapter and the note of each finished one.
  List<TalePage> duePages(StoryProgress progress) => [
        if (!_intro) ...TalePages.intro,
        for (var c = 1; c <= StoryLevel.chapters; c++) ...[
          if (progress.chapterOpen(c) && !_cards.contains(c)) TalePages.card(c),
          if (progress.chapterDone(c) && !_notes.contains(c)) ...TalePages.note(c),
        ],
      ];

  /// Everything in [duePages] has now been told.
  Future<void> markTold(StoryProgress progress) async {
    _intro = true;
    for (var c = 1; c <= StoryLevel.chapters; c++) {
      if (progress.chapterOpen(c)) _cards.add(c);
      if (progress.chapterDone(c)) _notes.add(c);
    }
    await _save();
  }

  Future<void> setEnding(String ending) async {
    _ending = ending;
    await _save();
  }

  /// Tests: nothing left to tell in the first chapters.
  @visibleForTesting
  void skipForTest() {
    _intro = true;
    for (var c = 1; c <= StoryLevel.chapters; c++) {
      _cards.add(c);
      _notes.add(c);
    }
  }

  /// Tests: forget everything without touching the disk.
  @visibleForTesting
  void resetForTest() {
    _intro = false;
    _cards.clear();
    _notes.clear();
    _ending = null;
  }
}
