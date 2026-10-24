import 'dart:math';
import 'dart:ui' show Offset, Path, Rect;

import 'maze.dart';

export 'maze.dart' show Seg;

const double kTwoPi = 2 * pi;

Offset polar(double rho, double theta) =>
    Offset(rho * cos(theta), rho * sin(theta));

/// A circular hedge maze: ring 0 is the centre disc (the goal), ring
/// `rings - 1` is the outermost ring with the entrance in its outer wall.
///
/// Cells are (ring, sector). Every cell owns two walls: an *inward* arc
/// between it and its parent in the ring below (edge id `2 * cell`), and a
/// *clockwise* radial wall between it and the next sector (edge id
/// `2 * cell + 1`). The maze is a spanning tree of open edges; some tree edges
/// on the start-to-goal route are *gates* that stay closed until a button is
/// pressed, so the maze is always solvable.
class PolarMaze implements Maze {
  PolarMaze._({
    required this.rings,
    required this.sectors,
    required this.offset,
    required this.open,
    required this.gateOf,
    required this.entrance,
    required this.buttonCells,
    required this.solution,
    this.loops = const [],
  }) {
    cellCount = offset.last + sectors.last;
    ringOfCell = List<int>.filled(cellCount, 0);
    for (var r = 0; r < rings; r++) {
      for (var s = 0; s < sectors[r]; s++) {
        ringOfCell[offset[r] + s] = r;
      }
    }
    _adjacency = [for (var c = 0; c < cellCount; c++) _neighboursOf(c)];
    _buildSegments();
  }

  static const double wallHalf = 0.1;

  /// How far the entrance trail reaches beyond the outer wall.
  static const double trailLength = 1.0;

  final int rings;
  final List<int> sectors;
  final List<int> offset;

  /// By edge id: the passage is part of the maze (a gate counts as open here).
  final List<bool> open;

  /// By edge id: gate index or -1.
  final List<int> gateOf;

  /// Sector of the outermost ring whose outer wall is open.
  final int entrance;

  /// Per gate index: the cell holding the button that opens it.
  @override
  final List<int> buttonCells;

  /// Cells from the start to the goal.
  @override
  final List<int> solution;

  @override
  final List<int> loops;

  @override
  late final int cellCount;
  late final List<int> ringOfCell;
  late final List<List<(int, int)>> _adjacency;

  /// Collision walls grouped by ring (arcs appear in both rings they touch).
  late final List<List<Seg>> byRing;

  @override
  int get goal => 0;
  @override
  int get start => offset[rings - 1] + entrance;
  @override
  int get gateCount => buttonCells.length;
  @override
  double get radius => rings.toDouble();

  int sectorOf(int cell) => cell - offset[ringOfCell[cell]];

  // ---- geometry ---------------------------------------------------------

  @override
  Offset cellCenter(int cell) {
    final r = ringOfCell[cell];
    if (r == 0) return Offset.zero;
    final n = sectors[r];
    return polar(r + 0.5, (sectorOf(cell) + 0.5) * kTwoPi / n);
  }

  /// The cell containing [p] (points outside the maze map to the outer ring).
  @override
  int cellAt(Offset p) {
    final rho = p.distance;
    if (rho < 1) return 0;
    final r = min(rho.floor(), rings - 1);
    var theta = atan2(p.dy, p.dx);
    if (theta < 0) theta += kTwoPi;
    final n = sectors[r];
    return offset[r] + min(n - 1, (theta / kTwoPi * n).floor());
  }

  /// Points to walk through to get along [cells]: the centre of each cell with
  /// the middle of each passage in between.
  @override
  List<Offset> routePoints(List<int> cells) {
    final pts = <Offset>[];
    for (var i = 0; i < cells.length; i++) {
      if (i > 0) pts.add(passageMid(cells[i - 1], cells[i]));
      pts.add(cellCenter(cells[i]));
    }
    return pts;
  }

  Offset passageMid(int a, int b) {
    final e = edgeBetween(a, b);
    final cell = e >> 1;
    final r = ringOfCell[cell];
    final n = sectors[r];
    if (e.isEven) {
      return polar(r.toDouble(), (sectorOf(cell) + 0.5) * kTwoPi / n);
    }
    return polar(r + 0.5, ((sectorOf(cell) + 1) % n) * kTwoPi / n);
  }

  // ---- graph ------------------------------------------------------------

  int parentOf(int cell) {
    final r = ringOfCell[cell];
    return offset[r - 1] + sectorOf(cell) * sectors[r - 1] ~/ sectors[r];
  }

  List<(int, int)> _neighboursOf(int c) {
    final r = ringOfCell[c];
    final res = <(int, int)>[];
    if (r >= 1) {
      res.add((parentOf(c), 2 * c));
      final n = sectors[r];
      final s = sectorOf(c);
      res.add((offset[r] + (s + 1) % n, 2 * c + 1));
      final prev = offset[r] + (s - 1 + n) % n;
      res.add((prev, 2 * prev + 1));
    }
    if (r < rings - 1) {
      for (var s2 = 0; s2 < sectors[r + 1]; s2++) {
        final child = offset[r + 1] + s2;
        if (parentOf(child) == c) res.add((child, 2 * child));
      }
    }
    return res;
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

  /// Passage that can be walked with the given gate states.
  @override
  bool passable(int edge, List<bool> gateOpen) =>
      open[edge] && (gateOf[edge] < 0 || gateOpen[gateOf[edge]]);

  /// Shortest walk from [from] to [to] through passable edges, or null.
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

  // ---- Maze interface ---------------------------------------------------

  @override
  int get scatterCount => rings;

  @override
  bool get fullView => false;

  @override
  Iterable<Seg> segmentsNear(Offset p) sync* {
    final ring = min(p.distance.floor(), rings + 1);
    for (var k = max(0, ring - 1); k <= min(rings + 1, ring + 1); k++) {
      yield* byRing[k];
    }
  }

  @override
  Iterable<Seg> segmentsAlong(Offset a, Offset b) sync* {
    final steps = max(1, ((b - a).distance / 0.5).ceil());
    final seen = <int>{};
    for (var i = 0; i <= steps; i++) {
      final p = Offset.lerp(a, b, i / steps)!;
      seen.add(min(p.distance.floor(), rings + 1));
    }
    for (final k in seen) {
      yield* byRing[k];
    }
  }

  @override
  bool atGoal(Offset p) => p.distance < 0.55;

  @override
  Offset clampInside(Offset p) =>
      p.distance > radius ? p / p.distance * radius : p;

  @override
  (Offset, Offset)? constrain(Offset p, double r) {
    final limit = radius + trailLength - r;
    if (p.distance <= limit) return null;
    final n = p / p.distance;
    return (n * limit, n);
  }

  // ---- walls ------------------------------------------------------------

  void _buildSegments() {
    // One list per ring, plus the ring just outside the wall that holds the
    // entrance trail.
    byRing = List.generate(rings + 2, (_) => <Seg>[]);
    void arc(double rho, double t0, double t1, int gate) {
      final pieces = max(1, ((t1 - t0) * rho / 0.3).ceil());
      for (var i = 0; i < pieces; i++) {
        final a = t0 + (t1 - t0) * i / pieces;
        final b = t0 + (t1 - t0) * (i + 1) / pieces;
        final seg = Seg(polar(rho, a), polar(rho, b), gate);
        final ri = rho.round();
        byRing[ri - 1].add(seg);
        byRing[ri].add(seg);
      }
    }

    for (var c = 0; c < cellCount; c++) {
      final r = ringOfCell[c];
      if (r == 0) continue;
      final n = sectors[r];
      final s = sectorOf(c);
      final inward = 2 * c;
      if (!open[inward] || gateOf[inward] >= 0) {
        arc(r.toDouble(), s * kTwoPi / n, (s + 1) * kTwoPi / n, gateOf[inward]);
      }
      final cw = 2 * c + 1;
      if (!open[cw] || gateOf[cw] >= 0) {
        final theta = ((s + 1) % n) * kTwoPi / n;
        byRing[r].add(Seg(polar(r.toDouble(), theta), polar(r + 1.0, theta), gateOf[cw]));
      }
    }
    final n = sectors[rings - 1];
    for (var s = 0; s < n; s++) {
      if (s == entrance) continue;
      arc(rings.toDouble(), s * kTwoPi / n, (s + 1) * kTwoPi / n, -1);
    }

    // The trail outside the entrance is a short fenced wedge: solid sides and
    // an end, so the ball can only roll along it, never over the open ground.
    final t0 = entrance * kTwoPi / n;
    final t1 = (entrance + 1) * kTwoPi / n;
    final outer = rings.toDouble();
    for (final theta in [t0, t1]) {
      byRing[rings].add(Seg(polar(outer, theta), polar(outer + trailLength, theta), -1));
    }
    arc(outer + trailLength, t0, t1, -1);
  }

  /// The ground of the entrance trail: a wedge from just inside the wall to
  /// the fenced end.
  Path trailPath() {
    final n = sectors[rings - 1];
    final t0 = entrance * kTwoPi / n;
    final t1 = (entrance + 1) * kTwoPi / n;
    final end = rings + trailLength;
    final a = polar(rings - 0.3, t0);
    final b = polar(rings - 0.3, t1);
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(polar(end, t0).dx, polar(end, t0).dy)
      ..arcTo(Rect.fromCircle(center: Offset.zero, radius: end), t0, t1 - t0, false)
      ..lineTo(b.dx, b.dy)
      ..close();
  }

  void _addEdge(Path path, int edge) {
    final c = edge >> 1;
    final r = ringOfCell[c];
    final n = sectors[r];
    final s = sectorOf(c);
    if (edge.isEven) {
      path.arcTo(
        Rect.fromCircle(center: Offset.zero, radius: r.toDouble()),
        s * kTwoPi / n,
        kTwoPi / n,
        true,
      );
    } else {
      final theta = ((s + 1) % n) * kTwoPi / n;
      path
        ..moveTo(r * cos(theta), r * sin(theta))
        ..lineTo((r + 1) * cos(theta), (r + 1) * sin(theta));
    }
  }

  /// All permanent walls, including the outer wall, as one path to stroke.
  @override
  Path wallPath() {
    final path = Path();
    for (var e = 2 * offset[1]; e < 2 * cellCount; e++) {
      if (!open[e]) _addEdge(path, e);
    }
    final n = sectors[rings - 1];
    for (var s = 0; s < n; s++) {
      if (s == entrance) continue;
      path.arcTo(
        Rect.fromCircle(center: Offset.zero, radius: rings.toDouble()),
        s * kTwoPi / n,
        kTwoPi / n,
        true,
      );
    }
    return path;
  }

  /// The wall piece that gate [index] closes.
  @override
  Path gatePath(int index) {
    final path = Path();
    for (var e = 2 * offset[1]; e < 2 * cellCount; e++) {
      if (gateOf[e] == index) _addEdge(path, e);
    }
    return path;
  }

  @override
  Path edgePath(int edge) {
    final path = Path();
    _addEdge(path, edge);
    return path;
  }

  @override
  List<Seg> edgeSegs(int edge) {
    final c = edge >> 1;
    final r = ringOfCell[c];
    final n = sectors[r];
    final s = sectorOf(c);
    if (edge.isOdd) {
      final theta = ((s + 1) % n) * kTwoPi / n;
      return [Seg(polar(r.toDouble(), theta), polar(r + 1.0, theta), -1)];
    }
    final t0 = s * kTwoPi / n;
    final t1 = (s + 1) * kTwoPi / n;
    final pieces = max(1, ((t1 - t0) * r / 0.3).ceil());
    return [
      for (var i = 0; i < pieces; i++)
        Seg(
          polar(r.toDouble(), t0 + (t1 - t0) * i / pieces),
          polar(r.toDouble(), t0 + (t1 - t0) * (i + 1) / pieces),
          -1,
        ),
    ];
  }

  /// Rough centre of gate [index], for effects and hints.
  @override
  Offset gateCenter(int index) {
    for (var e = 2 * offset[1]; e < 2 * cellCount; e++) {
      if (gateOf[e] == index) {
        final c = e >> 1;
        final (a, b) = (c, _otherSide(e));
        return (cellCenter(a) + cellCenter(b)) / 2;
      }
    }
    return Offset.zero;
  }

  int _otherSide(int edge) {
    final c = edge >> 1;
    if (edge.isEven) return parentOf(c);
    final r = ringOfCell[c];
    return offset[r] + (sectorOf(c) + 1) % sectors[r];
  }

  // ---- generation -------------------------------------------------------

  static List<int> _sectorsFor(int rings) {
    final s = <int>[1];
    for (var i = 1; i < rings; i++) {
      if (i == 1) {
        s.add(6);
      } else {
        // Split the ring when its cells would get too wide.
        s.add(2 * pi * (i + 0.5) / s[i - 1] > 1.9 ? s[i - 1] * 2 : s[i - 1]);
      }
    }
    return s;
  }

  /// Builds a perfect maze with [gates] gates on the way to the centre and one
  /// button per gate, placed so each button can be reached before its gate.
  ///
  /// With [entranceOnTop] the entrance is the sector at the top of the screen
  /// (otherwise a random one).
  static PolarMaze generate({
    required int rings,
    required int gates,
    Random? random,
    bool entranceOnTop = false,
    int loops = 0,
  }) {
    final rnd = random ?? Random();
    PolarMaze? best;
    for (var attempt = 0; attempt < 80; attempt++) {
      final m = _attempt(rings, gates, rnd, top: entranceOnTop, loops: loops);
      if (m == null) continue;
      if (best == null || m.solution.length > best.solution.length) best = m;
      if (m.solution.length >= gates * 3 + rings) break;
    }
    return best ??
        _attempt(rings, gates, rnd, relaxed: true, top: entranceOnTop, loops: loops)!;
  }

  static PolarMaze? _attempt(int rings, int gates, Random rnd,
      {bool relaxed = false, bool top = false, int loops = 0}) {
    final sectors = _sectorsFor(rings);
    final offset = <int>[0];
    for (var r = 1; r < rings; r++) {
      offset.add(offset[r - 1] + sectors[r - 1]);
    }
    final cellCount = offset.last + sectors.last;
    final open = List<bool>.filled(2 * cellCount, false);
    final gateOf = List<int>.filled(2 * cellCount, -1);
    // Screen y points down, so the top of the screen is the angle 3/2 pi.
    final entrance = top ? sectors.last * 3 ~/ 4 : rnd.nextInt(sectors.last);

    // Throwaway instance just to reuse the adjacency logic.
    final probe = PolarMaze._(
      rings: rings,
      sectors: sectors,
      offset: offset,
      open: open,
      gateOf: gateOf,
      entrance: entrance,
      buttonCells: const [],
      solution: const [],
    );

    // Randomised depth-first search from the goal.
    final seen = List<bool>.filled(cellCount, false);
    final stack = <int>[0];
    seen[0] = true;
    while (stack.isNotEmpty) {
      final cur = stack.last;
      final options = [
        for (final (n, e) in probe._adjacency[cur])
          if (!seen[n]) (n, e),
      ];
      if (options.isEmpty) {
        stack.removeLast();
        continue;
      }
      final (n, e) = options[rnd.nextInt(options.length)];
      open[e] = true;
      seen[n] = true;
      stack.add(n);
    }

    final start = offset[rings - 1] + entrance;
    final allOpen = List<bool>.filled(gates, true);
    final route = probe.path(start, 0, allOpen)!;
    final edges = [
      for (var i = 0; i + 1 < route.length; i++)
        probe.edgeBetween(route[i], route[i + 1]),
    ];
    if (!relaxed && edges.length < gates * 2 + 3) return null;
    if (edges.length < gates) return null;

    placeGates(edges, gates, gateOf, rnd);
    final buttons = placeButtons(
      probe,
      open: open,
      gateOf: gateOf,
      route: route,
      gates: gates,
      scale: rings.toDouble(),
      rnd: rnd,
    );
    if (buttons == null) return null;
    final extra = loops > 0 ? addLoops(probe, open, gateOf, loops, rnd) : const <int>[];

    return PolarMaze._(
      rings: rings,
      sectors: sectors,
      offset: offset,
      open: open,
      gateOf: gateOf,
      entrance: entrance,
      buttonCells: buttons,
      solution: route,
      loops: extra,
    );
  }
}
