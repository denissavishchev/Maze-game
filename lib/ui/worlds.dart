import 'package:flutter/material.dart';

import '../game/world.dart';
import '../l10n/strings.dart';

/// What is scattered around the outside of the maze.
enum Scenery { trees, swamp, snowPines, crystals, houses, space, graveyard }

/// How the walls are drawn.
enum WallStyle { hedge, mossRock, snowRock, brick, castle, hull }

/// How the floor is drawn.
enum FloorStyle { sand, flagstone, cobble, deck }

class WorldTheme {
  const WorldTheme({
    required this.id,
    required this.icon,
    required this.bg,
    required this.floor,
    required this.floorDark,
    required this.wallBase,
    required this.wallMain,
    required this.wallHi,
    required this.gate,
    required this.scenery,
    required this.wallStyle,
    required this.floorStyle,
    required this.panelTop,
    required this.panelBottom,
    required this.accent,
    this.dark = false,
  });

  /// Key part of this world's texts: `world.<id>.name` / `.blurb`.
  final String id;
  final IconData icon;

  String get name => tr('world.$id.name');
  String get blurb => tr('world.$id.blurb');

  /// Ground outside the maze (grass, water, snow...).
  final Color bg;

  /// The path the ball rolls on, and a darker tone for its texture.
  final Color floor;
  final Color floorDark;

  /// Walls: dark rim, body and highlight.
  final Color wallBase;
  final Color wallMain;
  final Color wallHi;

  /// The barrier that a button opens.
  final Color gate;
  final Scenery scenery;
  final WallStyle wallStyle;
  final FloorStyle floorStyle;

  /// Colours of the menu while this world is selected: the panels, and an
  /// accent for labels, the slider and the play button.
  final Color panelTop;
  final Color panelBottom;
  final Color accent;

  List<Color> get panel => [panelTop, panelBottom];

  /// Underground: only the area around the ball is lit.
  final bool dark;
}

/// The look of each world follows the key art: bushy hedges on sand paths in
/// the forest, mossy rock in the swamp, snowy rock in the mountains, brick
/// and torchlight underground, a castle town in the city.
WorldTheme themeFor(WorldKind kind) => switch (kind) {
      WorldKind.forest => const WorldTheme(
          id: 'forest',
          icon: Icons.park_rounded,
          bg: Color(0xFF5BA83A),
          floor: Color(0xFFE8D6A0),
          floorDark: Color(0xFFCBB67E),
          wallBase: Color(0xFF2F6B24),
          wallMain: Color(0xFF58B02F),
          wallHi: Color(0xFFA6EA63),
          gate: Color(0xFF9A6A38),
          scenery: Scenery.trees,
          wallStyle: WallStyle.hedge,
          floorStyle: FloorStyle.sand,
          panelTop: Color(0xEE2B4A2A),
          panelBottom: Color(0xEE1B3020),
          accent: Color(0xFF6DB83A),
        ),
      WorldKind.mud => const WorldTheme(
          id: 'mud',
          icon: Icons.water_drop_rounded,
          bg: Color(0xFF7D6B44),
          floor: Color(0xFFDCC995),
          floorDark: Color(0xFFBFA970),
          wallBase: Color(0xFF4E5A52),
          wallMain: Color(0xFF8E9A8C),
          wallHi: Color(0xFF7FCB45),
          gate: Color(0xFF8A5A30),
          scenery: Scenery.swamp,
          wallStyle: WallStyle.mossRock,
          floorStyle: FloorStyle.sand,
          panelTop: Color(0xEE514426),
          panelBottom: Color(0xEE31291A),
          accent: Color(0xFF47AFBB),
        ),
      WorldKind.mountains => const WorldTheme(
          id: 'mountains',
          icon: Icons.terrain_rounded,
          bg: Color(0xFFD6E5F1),
          floor: Color(0xFFD9C9A0),
          floorDark: Color(0xFFBBA980),
          wallBase: Color(0xFF454D4C),
          wallMain: Color(0xFF8B9391),
          wallHi: Color(0xFFFFFFFF),
          gate: Color(0xFFA9743F),
          scenery: Scenery.snowPines,
          wallStyle: WallStyle.snowRock,
          floorStyle: FloorStyle.sand,
          panelTop: Color(0xEE3D4C60),
          panelBottom: Color(0xEE243142),
          accent: Color(0xFF7FC8F0),
        ),
      WorldKind.underground => const WorldTheme(
          id: 'underground',
          icon: Icons.diamond_rounded,
          bg: Color(0xFF1A141C),
          floor: Color(0xFF8A6A4C),
          floorDark: Color(0xFF6B5039),
          wallBase: Color(0xFF16141A),
          wallMain: Color(0xFF58545E),
          wallHi: Color(0xFFA29CAE),
          gate: Color(0xFF8F98A6),
          scenery: Scenery.crystals,
          wallStyle: WallStyle.brick,
          floorStyle: FloorStyle.flagstone,
          panelTop: Color(0xEE41304F),
          panelBottom: Color(0xEE221730),
          accent: Color(0xFFFFA23A),
          dark: true,
        ),
      WorldKind.city => const WorldTheme(
          id: 'city',
          icon: Icons.location_city_rounded,
          bg: Color(0xFF6DB04A),
          floor: Color(0xFFC9BDA3),
          floorDark: Color(0xFFA89C82),
          wallBase: Color(0xFF7D7258),
          wallMain: Color(0xFFDDD2B4),
          wallHi: Color(0xFFF7F0DA),
          gate: Color(0xFFB7793F),
          scenery: Scenery.houses,
          wallStyle: WallStyle.castle,
          floorStyle: FloorStyle.cobble,
          panelTop: Color(0xEE5C5240),
          panelBottom: Color(0xEE393126),
          accent: Color(0xFFDA6A4C),
        ),
      WorldKind.space => const WorldTheme(
          id: 'space',
          icon: Icons.rocket_launch_rounded,
          bg: Color(0xFF0A0E1C),
          floor: Color(0xFF5B6881),
          floorDark: Color(0xFF3F4A62),
          wallBase: Color(0xFF161C2C),
          wallMain: Color(0xFF8DA0BD),
          wallHi: Color(0xFFE6F3FF),
          gate: Color(0xFF45C4F2),
          scenery: Scenery.space,
          wallStyle: WallStyle.hull,
          floorStyle: FloorStyle.deck,
          panelTop: Color(0xEE24304D),
          panelBottom: Color(0xEE111930),
          accent: Color(0xFF4FC3F7),
        ),
      WorldKind.graveyard => const WorldTheme(
          id: 'graveyard',
          icon: Icons.nightlight_round,
          bg: Color(0xFF1B2433),
          floor: Color(0xFF7A7C6E),
          floorDark: Color(0xFF5B5E52),
          wallBase: Color(0xFF232A36),
          wallMain: Color(0xFF8C93A3),
          wallHi: Color(0xFFD7DCEA),
          gate: Color(0xFF8E6BBF),
          scenery: Scenery.graveyard,
          wallStyle: WallStyle.castle,
          floorStyle: FloorStyle.flagstone,
          panelTop: Color(0xEE3A3550),
          panelBottom: Color(0xEE1B1A2C),
          accent: Color(0xFFB39DDB),
        ),
    };

/// Level-specific numbers for the select screen.
String hazardNote(GameConfig c) {
  final n = c.trapCount;
  final k = c.chaserCount;
  final trapEvery = c.trapInterval.toStringAsFixed(1);
  final boulderEvery = (c.trapInterval * 1.2).toStringAsFixed(1);
  return switch (c.world) {
    WorldKind.forest => k == 1 ? tr('note.wolf.one') : tr('note.wolf.many', {'n': k}),
    WorldKind.underground => tr('note.light', {'x': c.lightRadius.toStringAsFixed(1)}),
    WorldKind.city => k == 1 ? tr('note.drone.one') : tr('note.drone.many', {'n': k}),
    WorldKind.mud => n == 1
        ? tr('note.trap.one', {'s': trapEvery})
        : tr('note.trap.many', {'n': n, 's': trapEvery}),
    WorldKind.graveyard =>
      tr('note.graveyard', {'n': k, 's': trapEvery}),
    WorldKind.space => tr('note.space', {'l': c.laserCount, 'a': c.airlockCount, 'c': c.cameraCount}),
    WorldKind.mountains => n == 1
        ? tr('note.boulder.one', {'s': boulderEvery})
        : tr('note.boulder.many', {'n': n, 's': boulderEvery}),
  };
}
