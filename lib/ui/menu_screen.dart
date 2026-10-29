
import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/ball_collection.dart';
import '../game/game_controller.dart';
import '../game/world.dart';
import '../l10n/strings.dart';
import 'ball_shop.dart';
import 'balls.dart';
import 'game_screen.dart';
import 'kit.dart';
import 'palette.dart';
import 'worlds.dart';

/// Second screen: pick the world, the ball and the size of the maze, then
/// play. Worlds and balls are rows of five buttons with one description
/// underneath that follows the selection, which keeps everything on one screen.
///
/// In [endless] mode there is no world or size to pick: the screen explains the
/// mode and offers only the ball.
class SelectScreen extends StatefulWidget {
  const SelectScreen({super.key, this.endless = false});

  final bool endless;

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
        listenable: Listenable.merge([AppLanguage.instance, BallCollection.instance]),
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
                    if (widget.endless) ...[
                      _endlessDescription(),
                      const SizedBox(height: 12),
                      _buttons(),
                      const SizedBox(height: 12),
                      _label(tr('sel.world')),
                      _infoList([for (final w in GameController.endlessWorlds) _worldInfo(w)]),
                      const SizedBox(height: 12),
                      _label(tr('sel.ball')),
                      _infoList([for (final b in BallKind.values) _ballInfo(b)]),
                      const SizedBox(height: 12),
                    ] else ...[
                      _buttons(),
                      const SizedBox(height: 12),
                      _label(tr('sel.world')),
                      _worldRow(),
                      _worldDescription(),
                      const SizedBox(height: 12),
                    ],
                    if (!widget.endless) ...[
                      _label(tr('sel.ball')),
                      _ballRow(),
                      _ballDescription(),
                      const SizedBox(height: 12),
                      _label(tr('sel.size')),
                      _sizePicker(),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Back (left) and play (right) share one row: at the top of the screen, or
  /// in endless mode right under the description.
  Widget _buttons() => Row(
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
              builder: (_) => GameScreen(
                config: widget.endless
                    ? GameController.endlessConfig(0, ball)
                    : config,
                endless: widget.endless,
              ),
            ),
          ),
        ),
      ),
    ],
  );

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
            height: 92,
            // 6 inside the border keeps a name at least 8 from the tile's edge.
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: selected ? 0.55 : 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? Palette.gold : Palette.ink,
                width: selected ? 3.5 : 2.5,
              ),
            ),
            // Only the name shrinks (never the picture) when it is too wide.
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name.replaceAll(' ', '\n'),
                      textAlign: TextAlign.center,
                      style: cartoon(11,
                          outline: 1.2,
                          weight: selected ? FontWeight.w900 : FontWeight.w700,
                          color: selected ? Palette.gold : Palette.cream),
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

  /// Tiles in rows of [perRow]; the last row is padded so the tiles all keep
  /// the same size.
  static const int perRow = 4;

  Widget _grid(List<Widget> tiles) => Column(
        children: [
          for (var i = 0; i < tiles.length; i += perRow)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: Row(
                children: [
                  ...tiles.skip(i).take(perRow),
                  for (var k = tiles.length - i; k < perRow; k++)
                    const Expanded(child: SizedBox()),
                ],
              ),
            ),
        ],
      );

  Widget _worldRow() => _grid([
        for (final w in WorldKind.values)
          _tile(
            selected: w == world,
            onTap: () => setState(() => world = w),
            name: themeFor(w).name,
            child: _worldIcon(w),
          ),
      ]);

  /// A schematic symbol of the world on its own colours.
  Widget _worldIcon(WorldKind w) {
    final t = themeFor(w);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t.panel,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.ink, width: 2),
      ),
      child: Icon(t.icon, size: 30, color: t.accent),
    );
  }

  /// What the endless mode is and how its levels follow one another.
  Widget _endlessDescription() => MossPanel(
        colors: themeFor(world).panel,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.all_inclusive_rounded, color: Palette.gold, size: 22),
                const SizedBox(width: 8),
                Flexible(child: Text(tr('endless.title'), style: cartoon(18, outline: 1.5))),
              ],
            ),
            const SizedBox(height: 6),
            Text(tr('endless.desc'),
                style: const TextStyle(color: Palette.cream, fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(tr('endless.rules'),
                style: const TextStyle(
                    color: Color(0xFF8FFBFF), fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  /// Endless mode: worlds and balls come up at random, so they are only
  /// described here, one row each: picture, name and what it is.
  Widget _infoList(List<Widget> rows) => MossPanel(
        colors: themeFor(world).panel,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(children: rows),
      );

  Widget _infoRow(Widget picture, String name, List<Widget> body) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 48, child: Center(child: picture)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(name, style: cartoon(16, outline: 1.5)), ...body],
              ),
            ),
          ],
        ),
      );

  Widget _worldInfo(WorldKind w) => _infoRow(_worldIcon(w), themeFor(w).name, [
        Text(
          themeFor(w).blurb,
          style: const TextStyle(color: Palette.cream, fontSize: 12.5),
        ),
      ]);

  Widget _ballInfo(BallKind b) {
    final info = infoOf(b);
    Widget line(String sign, String text, Color color) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  sign,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: Palette.cream, fontSize: 12.5),
                ),
              ),
            ],
          ),
        );
    return _infoRow(BallBubble(kind: b, size: 42), info.name, [
      for (final p in info.pros) line('+', p, const Color(0xFFA6F55B)),
      for (final c in info.cons) line('−', c, const Color(0xFFFF7A6B)),
      if (!BallCollection.instance.owns(b))
        line('!', tr('ball.locked_endless'), Palette.gold),
    ]);
  }

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

  Widget _ballRow() => _grid([
        for (final b in BallKind.values)
          _tile(
            selected: b == ball,
            onTap: () async {
              if (!BallCollection.instance.owns(b)) {
                await showBallShop(context);
                if (!mounted || !BallCollection.instance.owns(b)) return;
              }
              setState(() => ball = b);
            },
            name: infoOf(b).name,
            child: BallCollection.instance.owns(b)
                ? BallBubble(kind: b, size: 42)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(opacity: 0.4, child: BallBubble(kind: b, size: 42)),
                      const Icon(Icons.lock_rounded, color: Colors.white, size: 22),
                    ],
                  ),
          ),
      ]);

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
