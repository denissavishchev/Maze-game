import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/ball_collection.dart';
import '../game/story.dart';
import '../game/story_progress.dart';
import '../l10n/strings.dart';
import 'ball_shop.dart';
import 'balls.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'palette.dart';
import 'worlds.dart';

/// The story map: five chapters, one per maze size, each a winding trail of
/// the 13 worlds. A level opens once enough stars have been collected.
class StoryMapScreen extends StatefulWidget {
  const StoryMapScreen({super.key});

  @override
  State<StoryMapScreen> createState() => _StoryMapScreenState();
}

class _StoryMapScreenState extends State<StoryMapScreen> {
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
                        ChunkyIconButton(
                          key: const Key('open-ball-shop'),
                          icon: Icons.sports_baseball_rounded,
                          tooltip: tr('story.balls_shop'),
                          size: 40,
                          onTap: () => showBallShop(context),
                        ),
                        const SizedBox(width: 10),
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
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        for (var c = 1; c <= StoryLevel.chapters; c++) ..._chapter(c),
                      ],
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

  List<Widget> _chapter(int chapter) {
    final levels = [
      for (var n = 0; n < StoryLevel.perChapter; n++)
        StoryLevel((chapter - 1) * StoryLevel.perChapter + n),
    ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(
          tr('story.chapter', {'n': chapter, 'size': tr('size.$chapter')}).toUpperCase(),
          style: cartoon(14, spacing: 1.5, outline: 1.5, color: Palette.gold),
        ),
      ),
      // Four nodes to a row, the trail snaking back and forth; the trail
      // itself is drawn behind the nodes between levels that are done.
      Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TrailPainter(
                stars: [for (final l in levels) StoryProgress.instance.stars(l.index)],
              ),
            ),
          ),
          Column(
            children: [
              for (var r = 0; r * 4 < levels.length; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: _TrailPainter.rowGap),
                  child: Row(
                    textDirection: r.isOdd ? TextDirection.rtl : TextDirection.ltr,
                    children: [
                      for (var k = 0; k < 4; k++)
                        Expanded(
                          child: r * 4 + k < levels.length
                              ? _Node(level: levels[r * 4 + k], onTap: _open)
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ];
  }

  Future<void> _open(StoryLevel level) async {
    final progress = StoryProgress.instance;
    if (!progress.isUnlocked(level)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(tr('story.need', {'n': progress.missingStars(level)})),
          duration: const Duration(seconds: 2),
        ));
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
    // "Next level" on the end card comes back here and opens its start sheet.
    if (next != null && mounted) {
      final nextLevel = StoryLevel(next);
      if (StoryProgress.instance.isUnlocked(nextLevel)) await _open(nextLevel);
    }
  }
}

/// The trail between levels that are done: a band from one node to the next
/// along the snake, bending round at the end of each row. Each piece has the
/// colour of the outline of the weaker of its two nodes: gold when both have
/// all three stars, sand otherwise.
class _TrailPainter extends CustomPainter {
  const _TrailPainter({required this.stars});

  /// Stars of the chapter's levels, in order.
  final List<int> stars;

  static const double nodeSize = 62;
  static const double rowHeight = 81; // the node, its gap and its stars
  static const double rowGap = 10;
  static const double width = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final col = size.width / 4;
    Offset center(int i) {
      final r = i ~/ 4;
      final k = i % 4;
      final visual = r.isOdd ? 3 - k : k;
      return Offset((visual + 0.5) * col, r * (rowHeight + rowGap) + nodeSize / 2);
    }

    for (var i = 0; i + 1 < stars.length; i++) {
      if (stars[i] == 0 || stars[i + 1] == 0) continue;
      final a = center(i);
      final b = center(i + 1);
      final both = stars[i] < stars[i + 1] ? stars[i] : stars[i + 1];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = both == StoryLevel.maxStars ? Palette.gold : Palette.sand;
      final path = Path()..moveTo(a.dx, a.dy);
      if ((i + 1) % 4 == 0) {
        // The end of a row: out to the side and round to the row below.
        final out = (i ~/ 4).isEven ? 57.0 : -57.0;
        path.cubicTo(a.dx + out, a.dy, b.dx + out, b.dy, b.dx, b.dy);
      } else {
        path.lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
          path, Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = width + 3..color = Palette.ink);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => !listEquals(old.stars, stars);
}

/// One level on the trail.
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
              border: Border.all(
                color: stars == 3 ? Palette.gold : Palette.ink,
                width: stars == 3 ? 4 : 3.5,
              ),
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
          const SizedBox(height: 4),
          _StarRow(stars: stars, size: 15, dim: !open),
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
              color: i < stars ? Palette.gold : Colors.black.withValues(alpha: dim ? 0.25 : 0.45),
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
