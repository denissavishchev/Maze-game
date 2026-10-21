import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/game_controller.dart';
import '../game/world.dart';
import '../l10n/strings.dart';
import 'balls.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'palette.dart';
import 'worlds.dart';

/// Where in the key art each world lives: the centre of a square window and
/// its width, as fractions of the picture (the wolf, the frog, the drone, the
/// ghost, the lantern mushroom).
const Map<WorldKind, (Offset, double)> _worldCrops = {
  WorldKind.forest: (Offset(0.44, 0.10), 0.46),
  WorldKind.mud: (Offset(0.40, 0.31), 0.42),
  WorldKind.mountains: (Offset(0.55, 0.69), 0.50),
  WorldKind.underground: (Offset(0.64, 0.905), 0.46),
  WorldKind.city: (Offset(0.50, 0.485), 0.46),
};

/// Second screen: pick the world, the ball and the size of the maze, then
/// play. Worlds and balls are rows of five buttons with one description
/// underneath that follows the selection, which keeps everything on one screen.
class SelectScreen extends StatefulWidget {
  const SelectScreen({super.key});

  @override
  State<SelectScreen> createState() => _SelectScreenState();
}

class _SelectScreenState extends State<SelectScreen> {
  WorldKind world = WorldKind.forest;
  BallKind ball = BallKind.wood;
  int level = GameConfig.minLevel;

  GameConfig get config => GameConfig(world, level, ball: ball);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppLanguage.instance,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    return Scaffold(
      body: ArtBackdrop(
        dim: 0.5,
        blur: 5,
        tint: themeFor(world).accent,
        child: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _label(tr('sel.world')),
                    _worldRow(),
                    _worldDescription(),
                    const SizedBox(height: 12),
                    _label(tr('sel.ball')),
                    _ballRow(),
                    _ballDescription(),
                    const SizedBox(height: 12),
                    _label(tr('sel.size')),
                    _sizePicker(),
                    const SizedBox(height: 12),
                    // Back (left) and play (right) share one row at the bottom.
                    Row(
                      children: [
                        ChunkyIconButton(
                          icon: Icons.arrow_back_rounded,
                          size: 62,
                          tooltip: tr('tt.menu'),
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ChunkyButton(
                            label: tr('play'),
                            icon: Icons.play_arrow_rounded,
                            tint: themeFor(world).accent,
                            fontSize: 22,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => GameScreen(config: config),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: cartoon(13,
                spacing: 1.5,
                color: Color.lerp(themeFor(world).accent, Colors.white, 0.55)!,
                outline: 1.5)),
      );

  /// One square choice button: [child] on top, a short [name] under it.
  Widget _tile({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
    required String name,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 84,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: selected ? 0.55 : 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? Palette.gold : Palette.ink,
                width: selected ? 3.5 : 2.5,
              ),
            ),
            // Scales down instead of overflowing when the system font is big.
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    child,
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: cartoon(11,
                          outline: 1.2,
                          weight: selected ? FontWeight.w900 : FontWeight.w700,
                          color: selected ? Palette.gold : Palette.cream),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The text box under a row of buttons; its height stays put so the layout
  /// does not jump when the selection changes.
  Widget _description(double minHeight, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: MossPanel(
            colors: themeFor(world).panel,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: child,
              ),
            ),
          ),
        ),
      );

  Widget _worldRow() => Row(
        children: [
          for (final w in WorldKind.values)
            _tile(
              selected: w == world,
              onTap: () => setState(() => world = w),
              name: themeFor(w).name,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Palette.ink, width: 2),
                ),
                child: ArtCrop(
                  center: _worldCrops[w]!.$1,
                  width: _worldCrops[w]!.$2,
                  size: 48,
                  radius: 10,
                ),
              ),
            ),
        ],
      );

  Widget _worldDescription() {
    final t = themeFor(world);
    return _description(
      64,
      Column(
        key: ValueKey(world),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.name, style: cartoon(18, outline: 1.5)),
          const SizedBox(height: 3),
          Text(t.blurb, style: const TextStyle(color: Palette.cream, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(
            tr('sel.bonus', {
              'name': GameController.bonusName(world).toLowerCase(),
              'n': GameController.usesPerBonus,
            }),
            style: const TextStyle(
                color: Color(0xFF8FFBFF), fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _ballRow() => Row(
        children: [
          for (final b in BallKind.values)
            _tile(
              selected: b == ball,
              onTap: () => setState(() => ball = b),
              name: infoOf(b).name,
              child: BallBubble(kind: b, size: 42),
            ),
        ],
      );

  Widget _ballDescription() {
    final info = infoOf(ball);
    Widget line(String sign, String text, Color color) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Text(sign,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              Expanded(
                child: Text(text,
                    style: const TextStyle(color: Palette.cream, fontSize: 12.5)),
              ),
            ],
          ),
        );
    return _description(
      100,
      Column(
        key: ValueKey(ball),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.name, style: cartoon(18, outline: 1.5)),
          for (final p in info.pros) line('+', p, const Color(0xFFA6F55B)),
          for (final c in info.cons) line('−', c, const Color(0xFFFF7A6B)),
        ],
      ),
    );
  }

  /// Maze size: a slider, its size name and what comes with it, on a panel so
  /// the slider stands out from the artwork.
  Widget _sizePicker() {
    return MossPanel(
      colors: themeFor(world).panel,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 12, color: Palette.cream),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 10,
                    activeTrackColor: themeFor(world).accent,
                    inactiveTrackColor: Colors.black.withValues(alpha: 0.55),
                    thumbColor: Palette.gold,
                    overlayColor: Palette.gold.withValues(alpha: 0.25),
                    activeTickMarkColor: Colors.black.withValues(alpha: 0.35),
                    inactiveTickMarkColor: Palette.cream.withValues(alpha: 0.6),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                  ),
                  child: Slider(
                    value: level.toDouble(),
                    min: GameConfig.minLevel.toDouble(),
                    max: GameConfig.maxLevel.toDouble(),
                    divisions: GameConfig.maxLevel - GameConfig.minLevel,
                    onChanged: (v) => setState(() => level = v.round()),
                  ),
                ),
              ),
              const Icon(Icons.circle, size: 26, color: Palette.cream),
            ],
          ),
          Text(config.sizeName, style: cartoon(20, outline: 1.8)),
          const SizedBox(height: 2),
          Text(
            config.bonusCount == 1
                ? tr('summary.one', {'buttons': config.buttonCount, 'note': hazardNote(config)})
                : tr('summary.many', {
                    'buttons': config.buttonCount,
                    'note': hazardNote(config),
                    'bonuses': config.bonusCount,
                  }),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Palette.sand, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
