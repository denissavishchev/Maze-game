import 'ball.dart';
import 'world.dart';

/// Story mode: 65 round mazes in five chapters, one chapter per maze size.
/// Every chapter visits all the worlds, from the gentlest to the hardest, so
/// the game starts with small mazes and grows from there.
class StoryLevel {
  const StoryLevel(this.index);

  final int index;

  static const List<WorldKind> worldOrder = [
    WorldKind.forest,
    WorldKind.mud,
    WorldKind.candy,
    WorldKind.mountains,
    WorldKind.city,
    WorldKind.ocean,
    WorldKind.underground,
    WorldKind.graveyard,
    WorldKind.glass,
    WorldKind.space,
    WorldKind.volcano,
    WorldKind.factory,
    WorldKind.shifting,
  ];

  static int get perChapter => worldOrder.length;
  static int get chapters => GameConfig.maxLevel;
  static int get count => perChapter * chapters;

  /// Every level can give three stars.
  static const int maxStars = 3;

  static List<StoryLevel> get all => [for (var i = 0; i < count; i++) StoryLevel(i)];

  /// Chapter 1..5, which is also the maze size.
  int get chapter => index ~/ perChapter + 1;
  int get size => chapter;
  WorldKind get world => worldOrder[index % perChapter];

  /// Position inside the chapter, 1..13.
  int get number => index % perChapter + 1;

  bool get isLast => index == count - 1;
  StoryLevel? get next => isLast ? null : StoryLevel(index + 1);

  GameConfig config(BallKind ball) => GameConfig(world, size, ball: ball);

  /// Stars the player must already hold to open this level: nothing for the
  /// first two, then one and a half per level that came before it. A player
  /// who earns three stars everywhere is never held up; one who only ever
  /// finishes has to go back and improve some times.
  int get requiredStars => index < 2 ? 0 : (index * 3 / 2).ceil();

  // ---- balls ------------------------------------------------------------

  /// Balls on offer per chapter. The first three suit the world and make the
  /// maze easy; more come with each chapter, and the last one is the hard one.
  static const List<int> ballsPerChapter = [3, 4, 5, 6, 6];

  /// All six balls of a world, from the friendliest to the hardest.
  static const Map<WorldKind, List<BallKind>> _balls = {
    WorldKind.forest: [BallKind.wood, BallKind.rubber, BallKind.slime, BallKind.paper, BallKind.stone, BallKind.steel],
    WorldKind.mud: [BallKind.bubble, BallKind.stone, BallKind.wood, BallKind.steel, BallKind.rubber, BallKind.paper],
    WorldKind.candy: [BallKind.bubble, BallKind.stone, BallKind.wood, BallKind.steel, BallKind.rubber, BallKind.paper],
    WorldKind.mountains: [BallKind.stone, BallKind.steel, BallKind.wood, BallKind.slime, BallKind.rubber, BallKind.bubble],
    WorldKind.city: [BallKind.rubber, BallKind.paper, BallKind.slime, BallKind.wood, BallKind.stone, BallKind.steel],
    WorldKind.ocean: [BallKind.stone, BallKind.steel, BallKind.wood, BallKind.slime, BallKind.rubber, BallKind.bubble],
    WorldKind.underground: [BallKind.wood, BallKind.rubber, BallKind.steel, BallKind.stone, BallKind.paper, BallKind.glass],
    WorldKind.graveyard: [BallKind.bubble, BallKind.rubber, BallKind.wood, BallKind.paper, BallKind.slime, BallKind.steel],
    WorldKind.glass: [BallKind.bubble, BallKind.wood, BallKind.steel, BallKind.rubber, BallKind.slime, BallKind.glass],
    WorldKind.space: [BallKind.wood, BallKind.steel, BallKind.stone, BallKind.slime, BallKind.glass, BallKind.bubble],
    WorldKind.volcano: [BallKind.wood, BallKind.steel, BallKind.stone, BallKind.rubber, BallKind.slime, BallKind.glass],
    WorldKind.factory: [BallKind.wood, BallKind.rubber, BallKind.stone, BallKind.slime, BallKind.paper, BallKind.steel],
    WorldKind.shifting: [BallKind.wood, BallKind.rubber, BallKind.steel, BallKind.stone, BallKind.slime, BallKind.glass],
  };

  /// The balls the player may pick on this level.
  List<BallKind> get balls => _balls[world]!.take(ballsPerChapter[chapter - 1]).toList();

  /// The ball that makes this world hardest; on offer only in the last two
  /// chapters (null before that).
  BallKind? get hardBall => balls.length >= 6 ? _balls[world]!.last : null;

  /// The first ball on offer that [owned] holds; the starters are in every
  /// world's list of three, so there always is one.
  BallKind defaultBallFor(Iterable<BallKind> owned) =>
      balls.firstWhere(owned.contains, orElse: () => balls.first);

  /// The ball preselected on this level.
  BallKind get defaultBall => balls.first;

  // ---- time and stars ---------------------------------------------------

  /// Per maze size. A bot steering straight along the route needs about 29,
  /// 36, 68, 88 and 128 seconds in the plainest world, and a person needs
  /// two to three times that.
  static const List<double> _goodSeconds = [85, 110, 175, 220, 310];

  static const Map<WorldKind, double> _worldFactor = {
    WorldKind.forest: 1.0,
    WorldKind.mud: 1.1,
    WorldKind.candy: 1.1,
    WorldKind.mountains: 1.1,
    WorldKind.city: 1.15,
    WorldKind.ocean: 1.15,
    WorldKind.underground: 1.25,
    WorldKind.graveyard: 1.2,
    WorldKind.glass: 1.2,
    WorldKind.space: 1.2,
    WorldKind.volcano: 1.25,
    WorldKind.factory: 1.25,
    WorldKind.shifting: 1.35,
  };

  /// Finish within this time for the second star.
  double get goodSeconds => _goodSeconds[size - 1] * _worldFactor[world]!;

  /// Finish within this time for the third star.
  double get greatSeconds => goodSeconds * 0.6;

  /// Stars for a finished run: one for finishing, one for [goodSeconds], and
  /// the third for [greatSeconds]; the hard ball earns it already at
  /// [goodSeconds].
  int starsFor(double seconds, BallKind ball) {
    if (seconds <= greatSeconds) return 3;
    if (seconds <= goodSeconds) return ball == hardBall ? 3 : 2;
    return 1;
  }
}
