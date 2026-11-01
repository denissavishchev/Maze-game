import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/ball_collection.dart';
import '../game/story.dart';
import '../game/story_progress.dart';
import '../game/tale.dart';
import '../l10n/strings.dart';
import 'ball_shop.dart';
import 'balls.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'palette.dart';
import 'puzzle_screen.dart';
import 'tale_screen.dart';
import 'worlds.dart';

/// The story map: climbing towards the mirror through the five chapters, one
/// per maze size. Each chapter is two trees of levels that fork into four
/// lines, and only the four tips lead on to the next chapter. A closed chapter
/// stays folded up until it opens. Outlines and lines all take their colour
/// from [_colourOf].
Color _colourOf(StoryState state) => switch (state) {
      StoryState.locked => Palette.stoneDark,
      StoryState.open => const Color(0xFF2B7F8C),
      StoryState.done => Palette.leaf,
      StoryState.perfect => Palette.gold,
    };

class StoryMapScreen extends StatefulWidget {
  const StoryMapScreen({super.key});

  @override
  State<StoryMapScreen> createState() => _StoryMapScreenState();
}

class _StoryMapScreenState extends State<StoryMapScreen> {
  final Map<int, GlobalKey> _chapterKeys = {
    for (var c = 1; c <= StoryLevel.chapters; c++) c: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    // The map starts at the foot of the tree; climb to the newest chapter.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      var current = 1;
      for (var c = 2; c <= StoryLevel.chapters; c++) {
        if (StoryProgress.instance.chapterOpen(c)) current = c;
      }
      final target = _chapterKeys[current]!.currentContext;
      if (current > 1 && target != null) {
        Scrollable.ensureVisible(target, alignment: 1);
      }
      _tell();
    });
  }

  /// Tells whatever part of the story is due.
  Future<void> _tell() async {
    final tale = TaleProgress.instance;
    final progress = StoryProgress.instance;
    final pages = tale.duePages(progress);
    if (pages.isEmpty) return;
    await showTale(context, pages);
    await tale.markTold(progress);
  }

  /// The mirror: the way to the end of the story, open after the last chapter.
  Future<void> _openMirror() async {
    if (!StoryProgress.instance.chapterDone(StoryLevel.chapters)) {
      _say(tr('story.need_chapter', {'n': StoryLevel.chapters}));
      return;
    }
    final ending = await showTale(context, TalePages.finale);
    if (ending == null || !mounted) return;
    await TaleProgress.instance.setEnding(ending);
    if (!mounted) return;
    await showTale(context, TalePages.ending(ending));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PuzzleScreen(caption: ending == endingStay ? 'tale.ending.b.3' : null),
    ));
    if (!mounted) return;
    await showTale(
      context,
      TalePages.credits(hasChameleon: BallCollection.instance.owns(BallKind.chameleon)),
    );
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 2),
    ));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([AppLanguage.instance, StoryProgress.instance]),
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final progress = StoryProgress.instance;
    return Scaffold(
      body: ArtBackdrop(
        dim: 0.5,
        blur: 5,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        ChunkyIconButton(
                          icon: Icons.arrow_back_rounded,
                          tooltip: tr('tt.menu'),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: Text(tr('story.title'), style: cartoon(24, spacing: 3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        ChunkyIconButton(
                          key: const Key('open-puzzle'),
                          icon: Icons.extension_rounded,
                          tooltip: tr('tale.puzzle'),
                          size: 56,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => const PuzzleScreen()),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ChunkyIconButton(
                          key: const Key('open-ball-shop'),
                          icon: Icons.sports_baseball_rounded,
                          tooltip: tr('story.balls_shop'),
                          size: 56,
                          onTap: () => showBallShop(context),
                        ),
                        const Spacer(),
                        const Icon(Icons.star_rounded, color: Palette.gold, size: 26),
                        const SizedBox(width: 4),
                        Text(
                          tr('story.total', {
                            'n': progress.totalStars,
                            'max': StoryLevel.count * StoryLevel.maxStars,
                          }),
                          key: const Key('story-total'),
                          style: cartoon(17, outline: 1.5),
                        ),
                      ],
                    ),
                  ),
                  const _Legend(),
                  Expanded(
                    child: SingleChildScrollView(
                      // The tree is climbed from the bottom.
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _openMirror,
                            child: _Mirror(done: progress.chapterDone(StoryLevel.chapters)),
                          ),
                          // Each chapter leads up only once it is finished.
                          for (var c = StoryLevel.chapters; c >= 1; c--) ...[
                            SizedBox(
                              height: 18,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _TrunkPainter(
                                    progress.chapterDone(c)
                                        ? progress.chapterState(c)
                                        : StoryState.locked),
                              ),
                            ),
                            KeyedSubtree(key: _chapterKeys[c], child: _chapter(c)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One chapter, outlined in the colour of its state: its timelines above
  /// the plate that names it.
  Widget _chapter(int chapter) {
    final progress = StoryProgress.instance;
    final levels = StoryLevel.ofChapter(chapter);
    final state = progress.chapterState(chapter);
    final folded = state == StoryState.locked;
    final colour = _colourOf(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colour, width: 3),
      ),
      child: Column(
        children: [
          SizedBox(
            height: folded ? _TreePainter.foldedHeight : _TreePainter.height,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TreePainter(
                        chapter: state,
                        levels: [for (final l in levels) progress.levelState(l)],
                      ),
                    ),
                  ),
                  if (!folded)
                    for (final l in levels)
                      Positioned(
                        left: _TreePainter.center(l, box.maxWidth).dx - 36,
                        top: _TreePainter.center(l, box.maxWidth).dy -
                            _TreePainter.nodeSize / 2,
                        width: 72,
                        child: _Node(level: l, onTap: _open),
                      ),
                ],
              ),
            ),
          ),
          GestureDetector(
            key: Key('story-chapter-$chapter'),
            onTap: folded ? () => _tellLocked(levels.first) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Palette.wood, Palette.woodDark],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colour, width: 2.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (folded) ...[
                    const Icon(Icons.lock_rounded, color: Palette.sand, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      tr('story.chapter', {'n': chapter, 'size': tr('size.$chapter')})
                          .toUpperCase(),
                      style: cartoon(14, spacing: 1.5, outline: 1.5, color: Palette.cream),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 18,
            width: double.infinity,
            // Nothing leads into the first chapter.
            child: chapter == 1
                ? null
                : CustomPaint(painter: _TrunkPainter(state, under: _TreePainter.overlap)),
          ),
        ],
      ),
    );
  }

  /// Says what still keeps [level] closed.
  void _tellLocked(StoryLevel level) {
    final progress = StoryProgress.instance;
    final String text;
    if (level.chapter > 1 && !progress.chapterDone(level.chapter - 1)) {
      text = tr('story.need_chapter', {'n': level.chapter - 1});
    } else if (progress.missingStars(level) > 0) {
      text = tr('story.need', {'n': progress.missingStars(level)});
    } else {
      text = tr('story.need_branch');
    }
    _say(text);
  }

  Future<void> _open(StoryLevel level) async {
    final progress = StoryProgress.instance;
    if (!progress.isUnlocked(level)) {
      _tellLocked(level);
      return;
    }
    final ball = await showModalBottomSheet<BallKind>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StartSheet(level: level),
    );
    if (ball == null || !mounted) return;
    final next = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (_) => GameScreen(config: level.config(ball), story: level),
      ),
    );
    if (!mounted) return;
    await _tell();
    // "Next level" on the end card comes back here and opens its start sheet.
    if (next != null && mounted) {
      final nextLevel = StoryLevel(next);
      if (StoryProgress.instance.isUnlocked(nextLevel)) await _open(nextLevel);
    }
  }
}

/// The mirror at the top of the tree, where the story ends.
class _Mirror extends StatelessWidget {
  const _Mirror({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('story-mirror'),
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.panel,
          border: Border.all(color: done ? Palette.gold : Palette.stoneDark, width: 4),
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: done ? Palette.gold : Colors.white54,
          size: 34,
        ),
      );
}

/// What the colours of the map mean.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final state in StoryState.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colourOf(state),
                      border: Border.all(color: Palette.ink, width: 1.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(tr('story.state.${state.name}'),
                      style: const TextStyle(color: Palette.cream, fontSize: 11.5)),
                ],
              ),
          ],
        ),
      );
}

/// One thick line of the map.
class _Line {
  const _Line(this.a, this.b, this.width, this.colour, {this.square = false});

  final Offset a;
  final Offset b;
  final double width;
  final Color colour;

  /// Ends square, to meet another piece of the same line without a seam.
  final bool square;
}

/// Draws lines that join up solidly: all the cartoon outlines first, then all
/// the colours on top, so no outline ever cuts across a join.
void _drawLines(Canvas canvas, List<_Line> lines) {
  for (final outline in [true, false]) {
    for (final line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = line.square ? StrokeCap.butt : StrokeCap.round
        ..strokeWidth = outline ? line.width + 3 : line.width
        ..color = outline ? Palette.ink : line.colour;
      canvas.drawLine(line.a, line.b, paint);
    }
  }
}

/// A piece of trunk: between two chapters, or below a chapter's plate, running
/// [under] on past its foot so that it crosses the frame in one piece.
class _TrunkPainter extends CustomPainter {
  const _TrunkPainter(this.state, {this.under = 0});

  final StoryState state;
  final double under;

  @override
  void paint(Canvas canvas, Size size) => _drawLines(canvas, [
        _Line(Offset(size.width / 2, 0), Offset(size.width / 2, size.height + under),
            _TreePainter.width, _colourOf(state), square: true),
      ]);

  @override
  bool shouldRepaint(_TrunkPainter old) => old.state != state || old.under != under;
}

/// One chapter's lines. From a rail along the foot two first levels rise and
/// fork into four straight lines, whose tips meet a rail along the top that
/// leads on. The way up to a level has that level's colour; the top rail
/// lights up only when the whole chapter is finished. A closed chapter shows
/// only the trunk.
class _TreePainter extends CustomPainter {
  const _TreePainter({required this.chapter, required this.levels});

  final StoryState chapter;

  /// States of the chapter's levels, in order.
  final List<StoryState> levels;

  static const double nodeSize = 62;
  /// Every line of the map is this thick, so that they all join up smoothly.
  static const double width = 7;

  /// Rows of levels sit this far apart.
  static const double rise = 88;

  /// The top rail, the top row of levels and the rail along the foot.
  static const double _railTop = 14;
  static const double _rowTop = 60;
  static const double _railFoot = 392;

  static const double height = 410;
  static const double foldedHeight = 26;

  /// How far the trunk runs past the top of a chapter, across its frame.
  static const double overlap = 8;

  /// The middle of [level]'s node on a tree [w] wide: four columns of three
  /// rows, with the first level of each tree under the middle of its fork.
  static Offset center(StoryLevel level, double w) {
    final i = level.number - 1;
    final tree = i ~/ 7;
    final j = i % 7;
    final column = tree * 2 + (j == 0 ? 0.5 : (j > 3 ? 1.0 : 0.0));
    final row = j == 0 ? 0 : (j > 3 ? j - 3 : j);
    return Offset(w * (column + 0.5) / 4, _rowTop + (3 - row) * rise);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final colour = _colourOf(chapter);
    if (chapter == StoryState.locked) {
      _drawLines(canvas, [
        _Line(Offset(mid, -overlap), Offset(mid, size.height), width, colour, square: true),
      ]);
      return;
    }
    final foot = size.height - (height - _railFoot);
    final left = size.width * 0.25;
    final right = size.width * 0.75;

    // The way in, along the foot: each side has the colour of the level it
    // leads to, and the middle that of the further side.
    final first = levels.first;
    final second = levels[StoryLevel.perChapter ~/ 2];
    final leftAhead = first.index > second.index;
    final leftSide = _Line(Offset(left, foot), Offset(mid, foot), width, _colourOf(first));
    final rightSide = _Line(Offset(mid, foot), Offset(right, foot), width, _colourOf(second));
    final lines = [
      if (leftAhead) rightSide else leftSide,
      if (leftAhead) leftSide else rightSide,
      _Line(Offset(mid, foot), Offset(mid, size.height), width,
          _colourOf(leftAhead ? first : second), square: true),
    ];

    // The way out, along the top.
    final finished = chapter == StoryState.done || chapter == StoryState.perfect;
    final out = finished ? colour : _colourOf(StoryState.locked);
    final edge = size.width / 8;
    lines.addAll([
      _Line(Offset(mid, -overlap), Offset(mid, _railTop), width, out, square: true),
      _Line(Offset(edge, _railTop), Offset(size.width - edge, _railTop), width, out),
    ]);

    for (var i = 0; i < levels.length; i++) {
      final level = StoryLevel(i);
      final at = center(level, size.width);
      final before = level.before;
      final from = before == null ? Offset(at.dx, foot) : center(before, size.width);
      lines.add(_Line(from, at, width, _colourOf(levels[i])));
      if (level.afterwards.isEmpty) {
        final done = levels[i] == StoryState.done || levels[i] == StoryState.perfect;
        lines.add(_Line(at, Offset(at.dx, _railTop), width,
            _colourOf(done ? levels[i] : StoryState.locked)));
      }
    }
    _drawLines(canvas, lines);
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.chapter != chapter || !listEquals(old.levels, levels);
}

/// One level on a line.
class _Node extends StatelessWidget {
  const _Node({required this.level, required this.onTap});

  final StoryLevel level;
  final ValueChanged<StoryLevel> onTap;

  @override
  Widget build(BuildContext context) {
    final progress = StoryProgress.instance;
    final theme = themeFor(level.world);
    final open = progress.isUnlocked(level);
    final stars = progress.stars(level.index);
    return GestureDetector(
      key: Key('story-node-${level.index}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(level),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: open
                    ? [theme.panelTop, theme.panelBottom]
                    : const [Color(0xFF555555), Color(0xFF333333)],
              ),
              border: Border.all(color: _colourOf(progress.levelState(level)), width: 4),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 3)),
              ],
            ),
            child: Icon(
              open ? theme.icon : Icons.lock_rounded,
              color: open ? Palette.cream : Colors.white54,
              size: 30,
            ),
          ),
          const SizedBox(height: 2),
          // A plate of their own, so the lines never run through the stars.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Palette.ink,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _colourOf(progress.levelState(level)), width: 1.5),
            ),
            child: _StarRow(stars: stars, size: 14, dim: !open),
          ),
        ],
      ),
    );
  }
}

/// Three stars, [stars] of them lit.
class _StarRow extends StatelessWidget {
  const _StarRow({required this.stars, required this.size, this.dim = false});

  final int stars;
  final double size;
  final bool dim;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < StoryLevel.maxStars; i++)
            Icon(
              Icons.star_rounded,
              size: size,
              color: i < stars ? Palette.gold : Colors.white.withValues(alpha: dim ? 0.12 : 0.28),
            ),
        ],
      );
}

/// What opens when a level is tapped: its world, its stars and goals, the
/// balls on offer and the play button.
class _StartSheet extends StatefulWidget {
  const _StartSheet({required this.level});

  final StoryLevel level;

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  late BallKind ball = widget.level.defaultBallFor(BallCollection.instance.owned);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: BallCollection.instance,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final level = widget.level;
    final theme = themeFor(level.world);
    final owned = BallCollection.instance;
    final best = StoryProgress.instance.bestMillis(level.index);
    final info = infoOf(ball);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: MossPanel(
          colors: theme.panel,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(theme.icon, color: Palette.gold, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(theme.name, style: cartoon(20, outline: 1.6)),
                  ),
                  _StarRow(stars: StoryProgress.instance.stars(level.index), size: 22),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${tr('story.chapter', {'n': level.chapter, 'size': tr('size.${level.size}')})}'
                ' · ${tr('story.level', {'n': level.number})}',
                style: const TextStyle(color: Palette.cream, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Text(
                tr('story.goal', {
                  'good': formatTime(level.goodSeconds),
                  'great': formatTime(level.greatSeconds),
                }),
                style: const TextStyle(color: Palette.cream, fontSize: 13),
              ),
              if (best != null)
                Text(tr('story.best', {'t': formatTime(best / 1000)}),
                    style: const TextStyle(
                        color: Palette.gold, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Text(tr('story.pick_ball').toUpperCase(),
                  style: cartoon(12, spacing: 1.5, outline: 1.2, color: Palette.sand)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final b in level.balls)
                    InkWell(
                      key: Key('story-ball-${b.name}'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: owned.owns(b)
                          ? () => setState(() => ball = b)
                          : () => showBallShop(context),
                      child: Container(
                        width: 72,
                        // 6 inside the border keeps a name 8 from the edge.
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: b == ball ? 0.55 : 0.3),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: b == ball ? Palette.gold : Palette.ink,
                            width: b == ball ? 3.5 : 2.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                    opacity: owned.owns(b) ? 1 : 0.4,
                                    child: BallBubble(kind: b, size: 36)),
                                if (!owned.owns(b))
                                  const Icon(Icons.lock_rounded,
                                      color: Colors.white, size: 20),
                              ],
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                infoOf(b).name + (b == level.hardBall ? ' ★' : ''),
                                style: cartoon(10,
                                    outline: 1,
                                    color: b == ball ? Palette.gold : Palette.cream),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(info.pros.join(' · '),
                  style: const TextStyle(color: Color(0xFFA6F55B), fontSize: 12)),
              Text(info.cons.join(' · '),
                  style: const TextStyle(color: Color(0xFFFF7A6B), fontSize: 12)),
              if (level.hardBall != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('story.hard_ball'),
                      style: const TextStyle(
                          color: Palette.gold, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 14),
              ChunkyButton(
                label: tr('play'),
                icon: Icons.play_arrow_rounded,
                tint: theme.accent,
                fontSize: 22,
                padding: const EdgeInsets.symmetric(vertical: 13),
                onTap: () => Navigator.of(context).pop(ball),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
