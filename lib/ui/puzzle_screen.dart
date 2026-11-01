import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/haptics.dart';
import '../game/story.dart';
import '../game/story_progress.dart';
import '../game/tale.dart';
import '../l10n/strings.dart';
import 'kit.dart';
import 'palette.dart';
import 'tale_screen.dart';

const String _picture = 'assets/images/story/puzzle.webp';

/// The outline of [level]'s piece on a picture [size] wide.
Path _pieceOf(StoryLevel level, double size) {
  final c = Offset(size / 2, size / 2);
  final half = size / 2;
  final ro = Puzzle.radiusOf(level) * half;
  final ri = ro - Puzzle.ringWidth * half;
  final a = Puzzle.angleOf(level);
  final sweep = Puzzle.wedge;
  return Path()
    ..arcTo(Rect.fromCircle(center: c, radius: ro), a, sweep, true)
    ..arcTo(Rect.fromCircle(center: c, radius: ri), a + sweep, -sweep, false)
    ..close();
}

/// The picture cut down to [levels].
class _Pieces extends CustomClipper<Path> {
  const _Pieces(this.levels);

  final List<StoryLevel> levels;

  @override
  Path getClip(Size size) {
    final path = Path();
    for (final l in levels) {
      path.addPath(_pieceOf(l, size.width), Offset.zero);
    }
    return path;
  }

  @override
  bool shouldReclip(_Pieces old) => old.levels.length != levels.length;
}

/// The empty place of the piece that is waiting.
class _SlotPainter extends CustomPainter {
  const _SlotPainter(this.level);

  final StoryLevel level;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _pieceOf(level, size.width);
    canvas.drawPath(path, Paint()..color = Colors.black);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Palette.gold,
    );
  }

  @override
  bool shouldRepaint(_SlotPainter old) => old.level.index != level.index;
}

/// The whole board: the found pieces in colour, the others in the dark, and in
/// the middle what the story ended with.
class _Board extends StatelessWidget {
  const _Board({super.key, required this.size, required this.found, this.slot});

  final double size;
  final List<StoryLevel> found;
  final StoryLevel? slot;

  @override
  Widget build(BuildContext context) {
    final ending = TaleProgress.instance.ending;
    final middle = size * Puzzle.inner;
    const picture = _picture;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          ClipOval(
            child: ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                0.09, 0.18, 0.03, 0, 0, //
                0.09, 0.18, 0.03, 0, 0, //
                0.09, 0.18, 0.03, 0, 0, //
                0, 0, 0, 1, 0,
              ]),
              child: Image.asset(picture, width: size, height: size),
            ),
          ),
          ClipPath(
            clipper: _Pieces(found),
            child: Image.asset(picture, width: size, height: size),
          ),
          if (slot != null)
            Positioned.fill(child: CustomPaint(painter: _SlotPainter(slot!))),
          Center(
            child: Container(
              key: const Key('puzzle-middle'),
              width: middle,
              height: middle,
              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: ending == null
                  ? null
                  : Image.asset(
                      'assets/images/story/'
                      '${ending == endingOpen ? 'puzzle_center_a' : 'ending_b_3'}.webp',
                      fit: BoxFit.cover,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The picture of the player's memories, to pinch and look at closely. With
/// [place], the piece of that level has just been won and goes onto the board
/// first. Otherwise a tap on a piece shows its line again.
class PuzzleScreen extends StatefulWidget {
  const PuzzleScreen({super.key, this.place, this.caption});

  final StoryLevel? place;

  /// A line to close with, at the end of the story.
  final String? caption;

  @override
  State<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends State<PuzzleScreen> {
  /// The piece on its way; null once it is on the board.
  late StoryLevel? _waiting = widget.place;

  /// How far the piece has been dragged.
  Offset _drag = Offset.zero;

  /// The piece whose line is showing.
  StoryLevel? _line;

  static const double _pieceScale = 1.3;
  static const double _pieceWidth = 120;
  static const double _closeZoom = 3;
  static const double _headerHeight = 72;

  final _view = TransformationController();
  Offset _tap = Offset.zero;

  /// While the board is zoomed it has the whole screen to itself.
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _view.addListener(_onZoom);
  }

  @override
  void dispose() {
    _view.dispose();
    super.dispose();
  }

  void _onZoom() {
    final zoomed = _view.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  List<StoryLevel> get _found => [
        for (final l in StoryLevel.all)
          if (StoryProgress.instance.stars(l.index) > 0 && l.index != _waiting?.index) l,
      ];

  void _drop() {
    Haptics.play(Haptic.tick);
    setState(() {
      _line = _waiting;
      _waiting = null;
      _drag = Offset.zero;
    });
  }

  /// A double tap goes close to that spot, and the next one back.
  void _toggleZoom() {
    final k = _closeZoom;
    _view.value = _zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
          ..translateByDouble(_tap.dx * (1 - k), _tap.dy * (1 - k), 0, 1)
          ..scaleByDouble(k, k, 1, 1));
  }

  void _tapBoard(Offset at, double size) {
    final half = size / 2;
    final level = Puzzle.levelAt((at.dx - half) / half, (at.dy - half) / half);
    if (level == null || StoryProgress.instance.stars(level.index) == 0) return;
    setState(() => _line = level);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Palette.bg,
        body: LayoutBuilder(builder: (context, box) {
          final pad = MediaQuery.paddingOf(context);
          final top = pad.top + _headerHeight;
          final room = box.maxHeight - top - pad.bottom;
          final size = min(box.maxWidth - 24, room * 0.62).clamp(120.0, 520.0);
          final corner = Offset((box.maxWidth - size) / 2, top);
          return Stack(
            children: [
              _viewer(box, size, corner),
              _words(box, size, corner, pad),
              if (_waiting != null) _piece(_waiting!, box, size, corner, pad),
              Positioned(left: 0, right: 0, top: pad.top, child: _header()),
            ],
          );
        }),
      );

  /// The board. The view spans the whole screen, so that zoomed the picture
  /// runs from edge to edge.
  Widget _viewer(BoxConstraints box, double size, Offset corner) {
    final waiting = _waiting;
    return InteractiveViewer(
      key: const Key('puzzle-view'),
      transformationController: _view,
      minScale: 1,
      maxScale: 6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: waiting == null ? (d) => _tapBoard(d.localPosition - corner, size) : null,
        onDoubleTapDown: (d) => _tap = d.localPosition,
        onDoubleTap: _toggleZoom,
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            children: [
              Positioned(
                left: corner.dx,
                top: corner.dy,
                child: _Board(
                  key: const Key('puzzle-board'),
                  size: size,
                  found: _found,
                  slot: waiting,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final place = widget.place;
    final back = place == null && widget.caption == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          if (back) ...[
            ChunkyIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: tr('tt.menu'),
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 14),
          ],
          if (!_zoomed)
            Expanded(
              child: FittedBox(
                alignment: place == null ? Alignment.centerLeft : Alignment.center,
                fit: BoxFit.scaleDown,
                child: Text(
                  place == null
                      ? tr('tale.puzzle')
                      : '${tr('story.chapter', {
                            'n': place.chapter,
                            'size': tr('size.${place.chapter}')
                          })} · ${tr('story.level', {'n': place.number})}',
                  style: cartoon(20, spacing: 1),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Everything under the board. The words give way to a zoomed picture; the
  /// way on stays.
  Widget _words(BoxConstraints box, double size, Offset corner, EdgeInsets pad) {
    final String? text = widget.caption != null
        ? tr(widget.caption!)
        : _line == null
            ? null
            : tr('tale.level.${_line!.index + 1}');
    final waiting = _waiting;
    final done = waiting == null && (widget.place != null || widget.caption != null);
    return Positioned(
      left: 20,
      right: 20,
      top: corner.dy + size + 20,
      bottom: pad.bottom + 12,
      child: Column(
        children: [
          // On a small phone the words scroll rather than run off the screen.
          Expanded(
            child: _zoomed
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        if (waiting != null)
                          Text(tr('tale.place'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Palette.sand, fontSize: 15)),
                        if (text != null) ...[TalePlate(text), const SizedBox(height: 8)],
                        Text(tr('tale.zoom_hint'),
                            key: const Key('puzzle-hint'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Palette.sand, fontSize: 13)),
                      ],
                    ),
                  ),
          ),
          if (done)
            ChunkyButton(
              key: const Key('puzzle-next'),
              label: tr('tale.next'),
              look: ButtonLook.gold,
              fontSize: 20,
              onTap: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  /// The waiting piece, under the board until it is dragged onto its place. A
  /// tap puts it there too, so that small hands always manage.
  Widget _piece(
      StoryLevel level, BoxConstraints box, double size, Offset corner, EdgeInsets pad) {
    // The pieces near the middle are small; big enough to take hold of.
    final width = _pieceOf(level, size).getBounds().width;
    final big = size * max(_pieceScale, _pieceWidth / width);
    final bounds = _pieceOf(level, big).getBounds();
    final home = Offset(
      (box.maxWidth - bounds.width) / 2,
      min(corner.dy + size + 84, box.maxHeight - pad.bottom - bounds.height - 12),
    );
    final (mx, my) = Puzzle.middleOf(level);
    final target = Offset(size / 2 + mx * size / 2, size / 2 + my * size / 2);
    return Positioned(
      left: home.dx + _drag.dx,
      top: home.dy + _drag.dy,
      child: GestureDetector(
        key: const Key('puzzle-piece'),
        onTap: _drop,
        onPanUpdate: (d) => setState(() => _drag += d.delta),
        onPanEnd: (_) {
          // Where it was let go on the board, however far that is zoomed.
          final centre = home + _drag + bounds.size.center(Offset.zero);
          final onBoard = _view.toScene(centre) - corner;
          if ((onBoard - target).distance < size * 0.28) {
            _drop();
          } else {
            setState(() => _drag = Offset.zero);
          }
        },
        child: SizedBox.fromSize(
          size: bounds.size,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: big,
              maxWidth: big,
              minHeight: big,
              maxHeight: big,
              child: Transform.translate(
                offset: -bounds.topLeft,
                child: ClipPath(
                  clipper: _Pieces([level]),
                  child: Image.asset(_picture, width: big, height: big),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
