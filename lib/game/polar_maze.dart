import 'dart:math';
import 'dart:ui' show Offset, Path, Rect;

const double kTwoPi = 2 * pi;

Offset polar(double rho, double theta) =>
    Offset(rho * cos(theta), rho * sin(theta));

/// A wall piece used for collision. [gate] is the index of the gate this
/// piece belongs to, or -1 for a permanent wall.
class Seg {
  const Seg(this.a, this.b, this.gate);

  final Offset a;
  final Offset b;
  final int gate;
}

/// A circular hedge maze: ring 0 is the centre disc (the goal), ring
/// `rings - 1` is the outermost ring with the entrance in its outer wall.
///
/// Cells are (ring, sector). Every cell owns two walls: an *inward* arc
/// between it and its parent in the ring below (edge id `2 * cell`), and a
/// *clockwise* radial wall between it and the next sector (edge id
/// `2 * cell + 1`). The maze is a spanning tree of open edges; some tree edges
/// on the start-to-goal route are *gates* that stay closed until a button is
/// pressed, so the maze is always solvable.
class PolarMaze {
  PolarMaze._({
    required this.rings,
    required this.sectors,
    required this.offset,
    required this.open,
    required this.gateOf,
    required this.entrance,
    required this.buttonCells,
    required this.solution,
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
  final List<int> buttonCells;

  /// Cells from the start to the goal.
  final List<int> solution;

  late final int cellCount;
  late final List<int> ringOfCell;
  late final List<List<(int, int)>> _adjacency;

  /// Collision walls grouped by ring (arcs appear in both rings they touch).
  late final List<List<Seg>> byRing;

  int get goal => 0;
  int get start => offset[rings - 1] + entrance;
  int get gateCount => buttonCells.length;
  double get radius => rings.toDouble();

  int sectorOf(int cell) => cell - offset[ringOfCell[cell]];

  // ---- geometry ---------------------------------------------------------

  Offset cellCenter(int cell) {
    final r = ringOfCell[cell];
    if (r == 0) return Offset.zero;
    final n = sectors[r];
    return polar(r + 0.5, (sectorOf(cell) + 0.5) * kTwoPi / n);
  }

  /// The cell containing [p] (points outside the maze map to the outer ring).
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

  List<(int, int)> neighbours(int cell) => _adjacency[cell];

  int edgeBetween(int a, int b) {
    for (final (n, e) in _adjacency[a]) {
      if (n == b) return e;
    }
    throw ArgumentError('cells $a and $b are not adjacent');
  }

  /// Passage that can be walked with the given gate states.
  bool passable(int edge, List<bool> gateOpen) =>
      open[edge] && (gateOf[edge] < 0 || gateOpen[gateOf[edge]]);

  /// Shortest walk from [from] to [to] through passable edges, or null.
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
  Path gatePath(int index) {
    final path = Path();
    for (var e = 2 * offset[1]; e < 2 * cellCount; e++) {
      if (gateOf[e] == index) _addEdge(path, e);
    }
    return path;
  }

  /// Rough centre of gate [index], for effects and hints.
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
  static PolarMaze generate({
    required int rings,
    required int gates,
    Random? random,
  }) {
    final rnd = random ?? Random();
    PolarMaze? best;
    for (var attempt = 0; attempt < 80; attempt++) {
      final m = _attempt(rings, gates, rnd);
      if (m == null) continue;
      if (best == null || m.solution.length > best.solution.length) best = m;
      if (m.solution.length >= gates * 3 + rings) break;
    }
    return best ?? _attempt(rings, gates, rnd, relaxed: true)!;
  }

  static PolarMaze? _attempt(int rings, int gates, Random rnd,
      {bool relaxed = false}) {
    final sectors = _sectorsFor(rings);
    final offset = <int>[0];
    for (var r = 1; r < rings; r++) {
      offset.add(offset[r - 1] + sectors[r - 1]);
    }
    final cellCount = offset.last + sectors.last;
    final open = List<bool>.filled(2 * cellCount, false);
    final gateOf = List<int>.filled(2 * cellCount, -1);
    final entrance = rnd.nextInt(sectors.last);

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

    // One gate per slice of the route, so they are spread out.
    for (var j = 0; j < gates; j++) {
      final lo = edges.length * j ~/ gates;
      final hi = max(lo + 1, edges.length * (j + 1) ~/ gates);
      gateOf[edges[lo + rnd.nextInt(hi - lo)]] = j;
    }

    // Button j goes somewhere reachable while gates j.. are still closed,
    // preferably down a side branch away from the main route.
    final onRoute = route.toSet();
    final used = <int>{start, 0};
    final buttons = <int>[];
    for (var j = 0; j < gates; j++) {
      bool before(int e) => open[e] && gateOf[e] < j;
      final comp = _reach(probe, [start], before);
      final dist = _distances(probe, onRoute.where(comp.contains), before);
      var cands = [
        for (final c in comp)
          if (!onRoute.contains(c) && !used.contains(c)) c,
      ];
      if (cands.isEmpty) {
        cands = [
          for (final c in comp)
            if (!used.contains(c)) c,
        ];
      }
      if (cands.isEmpty) return null;
      // Keep the buttons apart: ask for a minimum distance to the earlier
      // ones, relaxing it when the allowed area is too small.
      var sep = 1.2 * rings / sqrt(gates);
      var spread = cands;
      while (sep > 0.5) {
        spread = [
          for (final c in cands)
            if (buttons.every((b) =>
                (probe.cellCenter(c) - probe.cellCenter(b)).distance >= sep))
              c,
        ];
        if (spread.isNotEmpty) break;
        sep *= 0.8;
      }
      if (spread.isEmpty) spread = cands;
      spread.sort((a, b) => (dist[b] ?? 0).compareTo(dist[a] ?? 0));
      final pick = spread[rnd.nextInt(max(1, min(spread.length, max(3, spread.length ~/ 3))))];
      used.add(pick);
      buttons.add(pick);
    }

    return PolarMaze._(
      rings: rings,
      sectors: sectors,
      offset: offset,
      open: open,
      gateOf: gateOf,
      entrance: entrance,
      buttonCells: buttons,
      solution: route,
    );
  }

  static Set<int> _reach(PolarMaze m, Iterable<int> from, bool Function(int) ok) {
    final seen = <int>{...from};
    final queue = [...from];
    for (var i = 0; i < queue.length; i++) {
      for (final (n, e) in m._adjacency[queue[i]]) {
        if (!seen.contains(n) && ok(e)) {
          seen.add(n);
          queue.add(n);
        }
      }
    }
    return seen;
  }

  static Map<int, int> _distances(
      PolarMaze m, Iterable<int> from, bool Function(int) ok) {
    final dist = {for (final c in from) c: 0};
    final queue = [...from];
    for (var i = 0; i < queue.length; i++) {
      for (final (n, e) in m._adjacency[queue[i]]) {
        if (!dist.containsKey(n) && ok(e)) {
          dist[n] = dist[queue[i]]! + 1;
          queue.add(n);
        }
      }
    }
    return dist;
  }
}
