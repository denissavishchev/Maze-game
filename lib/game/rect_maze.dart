import 'dart:math';
import 'dart:ui' show Offset, Path;

import 'maze.dart';

/// A rectangular hedge maze that fills the screen: the entrance is a gap in
/// the top wall, the exit a gap in the bottom wall, and the whole maze is in
/// view at once. The start cell is in the top row and the goal cell in the
/// bottom row.
///
/// Cells are (row, column), cell id `row * cols + col`, one unit square each,
/// with the maze's top-left corner at the origin. Every cell owns two walls:
/// the one on its *top* side (edge id `2 * cell`, towards the cell above) and
/// the one on its *right* side (edge id `2 * cell + 1`, towards the next
/// column). The maze is a spanning tree of open edges; some tree edges on the
/// start-to-goal route are *gates* that stay closed until a button is pressed,
/// so the maze is always solvable.
class RectMaze implements Maze {
  RectMaze._({
    required this.cols,
    required this.rows,
    required this.start,
    required this.goal,
  })  : open = List<bool>.filled(2 * cols * rows, false),
        gateOf = List<int>.filled(2 * cols * rows, -1) {
    _adjacency = [for (var c = 0; c < cellCount; c++) _neighboursOf(c)];
  }

  /// Walls are this thick (half of it on each side of the cell border).
  static const double wallHalf = 0.1;

  /// The maze is shown edge to edge: this much width beyond its cells (so the
  /// side walls are not cut in half) and this much room above and below it.
  static const double padX = 0.45;
  static const double padTop = 0.15;
  static const double padBottom = 0.15;

  final int cols;
  final int rows;

  @override
  final int start;
  @override
  final int goal;

  /// By edge id: the passage is part of the maze (a gate counts as open here).
  final List<bool> open;

  /// By edge id: gate index or -1.
  final List<int> gateOf;

  @override
  List<int> buttonCells = const [];
  @override
  List<int> solution = const [];
  @override
  List<int> loops = const [];

  late final List<List<(int, int)>> _adjacency;

  @override
  int get cellCount => cols * rows;
  @override
  int get gateCount => buttonCells.length;
  @override
  double get radius => max(cols, rows) / 2;
  @override
  int get scatterCount => 5;
  @override
  bool get fullView => true;

  Offset get middle => Offset(cols / 2, rows / 2);

  /// Columns of the entrance in the top wall and the exit in the bottom wall.
  int get startCol => start;
  int get goalCol => goal % cols;

  int rowOf(int cell) => cell ~/ cols;
  int colOf(int cell) => cell % cols;

  // ---- geometry ---------------------------------------------------------

  @override
  Offset cellCenter(int cell) => Offset(colOf(cell) + 0.5, rowOf(cell) + 0.5);

  @override
  int cellAt(Offset p) {
    final col = p.dx.floor().clamp(0, cols - 1);
    final row = p.dy.floor().clamp(0, rows - 1);
    return row * cols + col;
  }

  @override
  List<Offset> routePoints(List<int> cells) {
    final pts = <Offset>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) pts.add((cellCenter(cells[i - 1]) + cellCenter(cells[i])) / 2);
      pts.add(cellCenter(cells[i]));
    }
    return pts;
  }

  // ---- graph ------------------------------------------------------------

  List<(int, int)> _neighboursOf(int c) {
    final row = rowOf(c);
    final col = colOf(c);
    return [
      if (row > 0) (c - cols, 2 * c),
      if (row < rows - 1) (c + cols, 2 * (c + cols)),
      if (col < cols - 1) (c + 1, 2 * c + 1),
      if (col > 0) (c - 1, 2 * (c - 1) + 1),
    ];
  }

  @override
  List<(int, int)> neighbours(int cell) => _adjacency[cell];

  @override
  int edgeBetween(int a, int b) {
    for (final (n, e) in _adjacency[a]) {
      if (n == b) return e;
    }
    throw ArgumentError('cells $a and $b are not adjacent');
  }

  @override
  bool passable(int edge, List<bool> gateOpen) =>
      open[edge] && (gateOf[edge] < 0 || gateOpen[gateOf[edge]]);

  @override
  List<int>? path(int from, int to, List<bool> gateOpen) {
    final prev = List<int>.filled(cellCount, -2);
    prev[from] = -1;
    final queue = <int>[from];
    for (var i = 0; i < queue.length; i++) {
      final c = queue[i];
      if (c == to) break;
      for (final (n, e) in _adjacency[c]) {
        if (prev[n] != -2 || !passable(e, gateOpen)) continue;
        prev[n] = c;
        queue.add(n);
      }
    }
    if (prev[to] == -2) return null;
    final out = <int>[];
    for (var c = to; c != -1; c = prev[c]) {
      out.add(c);
    }
    return out.reversed.toList();
  }

  // ---- walls ------------------------------------------------------------

  /// The two ends of the wall that edge [e] stands for.
  (Offset, Offset) _ends(int e) {
    final c = e >> 1;
    final x = colOf(c).toDouble();
    final y = rowOf(c).toDouble();
    return e.isEven
        ? (Offset(x, y), Offset(x + 1, y))
        : (Offset(x + 1, y), Offset(x + 1, y + 1));
  }

  /// Edges that are not part of the maze are walls, and so is the whole
  /// border (the top and right edges of the outer cells).
  bool _isWall(int e) => !open[e] || gateOf[e] >= 0;

  @override
  Path wallPath() {
    final path = Path();
    for (var e = 0; e < 2 * cellCount; e++) {
      if (open[e] || e == 2 * start) continue; // 2 * start: the entrance gap
      final (a, b) = _ends(e);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    // The left and bottom border, with the exit gap in the bottom.
    final h = rows.toDouble();
    path
      ..moveTo(0, 0)
      ..lineTo(0, h)
      ..lineTo(goalCol.toDouble(), h)
      ..moveTo(goalCol + 1.0, h)
      ..lineTo(cols.toDouble(), h);
    return path;
  }

  @override
  Path gatePath(int index) {
    final path = Path();
    for (var e = 0; e < 2 * cellCount; e++) {
      if (gateOf[e] != index) continue;
      final (a, b) = _ends(e);
      path
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    return path;
  }

  @override
  Offset gateCenter(int index) {
    for (var e = 0; e < 2 * cellCount; e++) {
      if (gateOf[e] == index) {
        final c = e >> 1;
        return (cellCenter(c) + cellCenter(e.isEven ? c - cols : c + 1)) / 2;
      }
    }
    return Offset.zero;
  }

  @override
  List<Seg> edgeSegs(int edge) {
    final (a, b) = _ends(edge);
    return [Seg(a, b, -1)];
  }

  @override
  Path edgePath(int edge) {
    final (a, b) = _ends(edge);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }

  /// Collision walls grouped by the rows they touch.
  late final List<List<Seg>> byRow = _buildSegments();

  List<List<Seg>> _buildSegments() {
    final grouped = List.generate(rows, (_) => <Seg>[]);
    void add(Seg s, int row) => grouped[row.clamp(0, rows - 1)].add(s);
    for (var e = 0; e < 2 * cellCount; e++) {
      if (!_isWall(e) || e == 2 * start) continue;
      final (a, b) = _ends(e);
      final seg = Seg(a, b, gateOf[e]);
      if (e.isEven) {
        // Horizontal: between the row above and the row of the cell.
        add(seg, rowOf(e >> 1) - 1);
        add(seg, rowOf(e >> 1));
      } else {
        add(seg, rowOf(e >> 1));
      }
    }
    for (var r = 0; r < rows; r++) {
      add(Seg(Offset(0, r.toDouble()), Offset(0, r + 1.0), -1), r);
    }
    final h = rows.toDouble();
    add(Seg(Offset(0, h), Offset(goalCol.toDouble(), h), -1), rows - 1);
    add(Seg(Offset(goalCol + 1.0, h), Offset(cols.toDouble(), h), -1), rows - 1);
    return grouped;
  }

  @override
  Iterable<Seg> segmentsNear(Offset p) sync* {
    final row = p.dy.floor().clamp(0, rows - 1);
    for (var r = max(0, row - 1); r <= min(rows - 1, row + 1); r++) {
      yield* byRow[r];
    }
  }

  @override
  Iterable<Seg> segmentsAlong(Offset a, Offset b) sync* {
    final steps = max(1, ((b - a).distance / 0.5).ceil());
    final seen = <int>{};
    for (var i = 0; i <= steps; i++) {
      final p = Offset.lerp(a, b, i / steps)!;
      seen.add(p.dy.floor().clamp(0, rows - 1));
    }
    for (final r in seen) {
      yield* byRow[r];
    }
  }

  /// The ball has left through the exit in the bottom wall.
  @override
  bool atGoal(Offset p) => p.dy >= rows && p.dx > goalCol && p.dx < goalCol + 1;

  @override
  Offset clampInside(Offset p) => Offset(
        p.dx.clamp(0.5, cols - 0.5),
        p.dy.clamp(0.5, rows - 0.5),
      );

  @override
  (Offset, Offset)? constrain(Offset p, double r) {
    final x = p.dx.clamp(r, cols - r);
    // Below the bottom wall only the exit leads on; a little room beyond it.
    final y = p.dy.clamp(r, rows + 0.7);
    if (x == p.dx && y == p.dy) return null;
    final fixed = Offset(x, y);
    final out = p - fixed;
    return (fixed, out / out.distance);
  }

  // ---- generation -------------------------------------------------------

  /// Builds a perfect maze with [gates] gates on the way down and one button
  /// per gate, placed so each button can be reached before its gate. The
  /// entrance is in column [startCol] (random when null), so a maze can start
  /// right below the exit of the one before.
  static RectMaze generate({
    required int cols,
    required int rows,
    required int gates,
    Random? random,
    int? startCol,
    int loops = 0,
  }) {
    final rnd = random ?? Random();
    RectMaze? best;
    for (var attempt = 0; attempt < 80; attempt++) {
      final m = _attempt(cols, rows, gates, rnd, startCol: startCol, loops: loops);
      if (m == null) continue;
      if (best == null || m.solution.length > best.solution.length) best = m;
      if (m.solution.length >= gates * 3 + rows) break;
    }
    return best ??
        _attempt(cols, rows, gates, rnd, relaxed: true, startCol: startCol, loops: loops)!;
  }

  static RectMaze? _attempt(int cols, int rows, int gates, Random rnd,
      {bool relaxed = false, int? startCol, int loops = 0}) {
    final start = startCol ?? rnd.nextInt(cols);
    final goal = (rows - 1) * cols + rnd.nextInt(cols);
    final m = RectMaze._(cols: cols, rows: rows, start: start, goal: goal);

    // Randomised depth-first search from the goal.
    final seen = List<bool>.filled(m.cellCount, false);
    final stack = <int>[goal];
    seen[goal] = true;
    while (stack.isNotEmpty) {
      final cur = stack.last;
      final options = [
        for (final (n, e) in m._adjacency[cur])
          if (!seen[n]) (n, e),
      ];
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final (n, e) = options[rnd.nextInt(options.length)];
      m.open[e] = true;
      seen[n] = true;
      stack.add(n);
    }

    final route = m.path(start, goal, List<bool>.filled(gates, true))!;
    final edges = [
      for (var i = 0; i + 1 < route.length; i++)
        m.edgeBetween(route[i], route[i + 1]),
    ];
    if (!relaxed && edges.length < gates * 2 + 3) return null;
    if (edges.length < gates) return null;

    placeGates(edges, gates, m.gateOf, rnd);
    final buttons = placeButtons(
      m,
      open: m.open,
      gateOf: m.gateOf,
      route: route,
      gates: gates,
      scale: 5,
      rnd: rnd,
    );
    if (buttons == null) return null;
    m.buttonCells = buttons;
    m.solution = route;
    if (loops > 0) m.loops = addLoops(m, m.open, m.gateOf, loops, rnd);
    return m;
  }
}
