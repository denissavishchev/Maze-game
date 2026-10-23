import 'dart:math';
import 'dart:ui' show Offset, Path;

/// A wall piece used for collision. [gate] is the index of the gate this
/// piece belongs to, or -1 for a permanent wall.
class Seg {
  const Seg(this.a, this.b, this.gate);

  final Offset a;
  final Offset b;
  final int gate;
}

/// What the game needs from a maze, whatever its shape: a graph of cells with
/// walls, some of them gates that stay closed until a button is pressed, and a
/// way to ask which walls are near a point.
abstract interface class Maze {
  int get cellCount;
  int get start;
  int get goal;
  int get gateCount;

  /// Per gate index: the cell holding the button that opens it.
  List<int> get buttonCells;

  /// Cells from the start to the goal.
  List<int> get solution;

  /// Half the size of the maze: no point of it is farther from the middle.
  double get radius;

  /// How many scattered dangers (bogs) a maze of this size gets.
  int get scatterCount;

  /// True when the whole maze fits on the screen at once (no scrolling).
  bool get fullView;

  Offset cellCenter(int cell);

  /// The cell containing [p] (points outside the maze map to the nearest).
  int cellAt(Offset p);

  List<(int, int)> neighbours(int cell);
  int edgeBetween(int a, int b);

  /// Passage that can be walked with the given gate states.
  bool passable(int edge, List<bool> gateOpen);

  /// Shortest walk from [from] to [to] through passable edges, or null.
  List<int>? path(int from, int to, List<bool> gateOpen);

  /// Points to walk through to get along [cells].
  List<Offset> routePoints(List<int> cells);

  /// Rough centre of gate [index], for effects and hints.
  Offset gateCenter(int index);

  /// All permanent walls as one path to stroke.
  Path wallPath();

  /// The wall piece that gate [index] closes.
  Path gatePath(int index);

  /// The walls that can touch a ball at [p].
  Iterable<Seg> segmentsNear(Offset p);

  /// The walls that can cross the line from [a] to [b].
  Iterable<Seg> segmentsAlong(Offset a, Offset b);

  /// Whether [p] is at the goal.
  bool atGoal(Offset p);

  /// [p] moved to the nearest point inside the maze.
  Offset clampInside(Offset p);

  /// For a ball of radius [r] at [p] that has strayed out of bounds: where to
  /// put it back and the outward direction there; null while it is inside.
  (Offset, Offset)? constrain(Offset p, double r);
}

/// Cells reachable from [from] through edges accepted by [ok].
Set<int> reachable(Maze m, Iterable<int> from, bool Function(int) ok) {
  final seen = <int>{...from};
  final queue = [...from];
  for (var i = 0; i < queue.length; i++) {
    for (final (n, e) in m.neighbours(queue[i])) {
      if (!seen.contains(n) && ok(e)) {
        seen.add(n);
        queue.add(n);
      }
    }
  }
  return seen;
}

/// Steps from the nearest of [from] to every cell reachable through [ok].
Map<int, int> distancesFrom(Maze m, Iterable<int> from, bool Function(int) ok) {
  final dist = {for (final c in from) c: 0};
  final queue = [...from];
  for (var i = 0; i < queue.length; i++) {
    for (final (n, e) in m.neighbours(queue[i])) {
      if (!dist.containsKey(n) && ok(e)) {
        dist[n] = dist[queue[i]]! + 1;
        queue.add(n);
      }
    }
  }
  return dist;
}

/// One gate per slice of the route, so they are spread out. [edges] are the
/// edge ids along the route.
void placeGates(List<int> edges, int gates, List<int> gateOf, Random rnd) {
  for (var j = 0; j < gates; j++) {
    final lo = edges.length * j ~/ gates;
    final hi = max(lo + 1, edges.length * (j + 1) ~/ gates);
    gateOf[edges[lo + rnd.nextInt(hi - lo)]] = j;
  }
}

/// Button j goes somewhere reachable while gates j.. are still closed,
/// preferably down a side branch away from the main route. Returns the button
/// cells, or null when some button has nowhere to go. [scale] is the size of
/// the maze in cells across.
List<int>? placeButtons(
  Maze probe, {
  required List<bool> open,
  required List<int> gateOf,
  required List<int> route,
  required int gates,
  required double scale,
  required Random rnd,
}) {
  final start = route.first;
  final onRoute = route.toSet();
  final used = <int>{start, route.last};
  final buttons = <int>[];
  for (var j = 0; j < gates; j++) {
    bool before(int e) => open[e] && gateOf[e] < j;
    final comp = reachable(probe, [start], before);
    final dist = distancesFrom(probe, onRoute.where(comp.contains), before);
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
    var sep = 1.2 * scale / sqrt(gates);
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
  return buttons;
}
