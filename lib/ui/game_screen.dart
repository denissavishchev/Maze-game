import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../game/game_controller.dart';
import '../game/tilt.dart';
import '../game/world.dart';
import '../l10n/strings.dart';
import 'game_painter.dart';
import 'kit.dart';
import 'palette.dart';
import 'records_sheet.dart';
import 'worlds.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.config});

  final GameConfig config;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController game = GameController(widget.config);
  late final WorldTheme theme = themeFor(widget.config.world);
  late final Ticker _ticker;
  MazeRender? _render;

  // The only input: how far the phone is tilted from a reference
  // pose, read from the accelerometer.
  StreamSubscription<AccelerometerEvent>? _sensor;
  final TiltTracker _tilt = TiltTracker();
  Duration _last = Duration.zero;

  bool get _haveSensor => _tilt.hasSensor;

  @override
  void initState() {
    super.initState();
    try {
      _sensor = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (e) {
          // Browsers without the sensor API report a constant 0, 0, 0.
          if (e.x == 0 && e.y == 0 && e.z == 0) return;
          _tilt.feed(e.x, e.y, e.z);
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {}
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sensor?.cancel();
    game.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0) return;

    game.update(dt, _tilt.tilt);
    // The reference pose follows the hand until the first real tilt, so
    // however the phone is held when the game opens, it starts level.
    _tilt.step(dt, started: game.started, stillTime: game.stillTime);
  }

  void _calibrate() => setState(_tilt.calibrate);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: game,
          builder: (context, _) {
            if (_render?.maze != game.maze) {
              _render = MazeRender(game.maze, theme);
            }
            final render = _render!;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: _Header(game: game),
                ),
                Expanded(
                  child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(painter: GamePainter(game, render)),
                        ),
                        Positioned(
                          left: 12,
                          bottom: 12,
                          width: 104,
                          height: 104,
                          child: IgnorePointer(
                            child: CustomPaint(painter: MiniMapPainter(game, render)),
                          ),
                        ),
                        // Bottom right: the bonus above, calibration below. Each
                        // has a caption saying what it does.
                        Positioned(
                          right: 12,
                          bottom: 12,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _BonusButton(game: game),
                              const SizedBox(height: 10),
                              _CaptionedButton(
                                icon: Icons.screen_rotation_alt_rounded,
                                label: tr('cal.label'),
                                tooltip: tr('tt.calibrate'),
                                onPressed: _calibrate,
                              ),
                            ],
                          ),
                        ),
                        if (!game.started && !game.won && !game.lost)
                          Positioned(
                            left: 24,
                            right: 24,
                            bottom: 215,
                            child: _Hint(haveSensor: _haveSensor),
                          ),
                        if (game.config.world == WorldKind.forest ||
                            game.config.world == WorldKind.city)
                          Positioned(
                            left: 12,
                            right: 12,
                            top: 8,
                            child: _NoiseMeter(game: game),
                          ),
                        if (game.config.world == WorldKind.mountains &&
                            (game.windLeft > 0 || game.windWarnLeft > 0))
                          Positioned(
                            left: 12,
                            right: 12,
                            top: 8,
                            child: _WindBadge(game: game),
                          ),
                        if (game.noticeLeft > 0)
                          Positioned(
                            left: 24,
                            right: 24,
                            top: 56,
                            child: _Notice(text: tr(game.notice, game.noticeArgs)),
                          ),
                        if (game.won) _EndCard(game: game, won: true),
                        if (game.lost) _EndCard(game: game, won: false),
                      ],
                    ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A labelled bar with a green-to-red fill.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.icon,
    required this.label,
    required this.value,
    required this.text,
  });

  final IconData icon;
  final String label;
  final double value;
  final String text;

  @override
  Widget build(BuildContext context) {
    final n = value.clamp(0.0, 1.0);
    final color = Color.lerp(Colors.lightGreenAccent, Colors.redAccent, n)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.ink, width: 2.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: cartoon(11, spacing: 1, outline: 1.2)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                children: [
                  Container(height: 10, color: Colors.white12),
                  FractionallySizedBox(
                    widthFactor: n,
                    child: Container(
                      height: 10,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.lightGreenAccent, Colors.amber, Colors.redAccent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text(text,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Always-visible loudness of the ball (forest, city).
class _NoiseMeter extends StatelessWidget {
  const _NoiseMeter({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final quiet = game.noiseLevel < 0.04;
    return _Meter(
      icon: quiet ? Icons.volume_mute_rounded : Icons.volume_up_rounded,
      label: tr('meter.noise'),
      value: game.noiseLevel,
      text: quiet
          ? tr('meter.quiet')
          : tr('meter.cells', {'x': game.hearingRadius.toStringAsFixed(1)}),
    );
  }
}

/// Warning and direction of a gust of wind (mountains).
class _WindBadge extends StatelessWidget {
  const _WindBadge({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final active = game.windLeft > 0;
    final color = active ? Colors.cyanAccent : Colors.amberAccent;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.ink, width: 3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: game.windDir.direction,
              child: Icon(Icons.arrow_forward_rounded, color: color, size: 28),
            ),
            const SizedBox(width: 8),
            Text(active ? tr('wind.now') : tr('wind.coming'),
                style: cartoon(15, color: color, outline: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// Uses the collected bonus: three uses per pickup, ten seconds each.
class _BonusButton extends StatelessWidget {
  const _BonusButton({required this.game});

  final GameController game;

  IconData get icon => switch (game.config.world) {
        WorldKind.forest => Icons.bedtime_rounded,
        WorldKind.mud => Icons.shield_rounded,
        WorldKind.mountains => Icons.landslide_rounded,
        WorldKind.underground => Icons.light_mode_rounded,
        WorldKind.city => Icons.power_settings_new_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final active = game.bonusLeft > 0;
    final enabled = game.bonusCharges > 0 && !active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled || active ? 1 : 0.5,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(
                  value: active ? game.bonusLeft / GameController.bonusDuration : 0,
                  strokeWidth: 4,
                  color: const Color(0xFF7DF9FF),
                  backgroundColor: Colors.transparent,
                ),
              ),
              Material(
                color: Palette.wood,
                shape: CircleBorder(
                  side: BorderSide(
                    color: active ? const Color(0xFF7DF9FF) : Palette.ink,
                    width: 4,
                  ),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? game.useBonus : null,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                ),
              ),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: Palette.gold, shape: BoxShape.circle),
                  child: Text('${game.bonusCharges}',
                      style: const TextStyle(
                          color: Palette.woodDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(GameController.bonusName(game.config.world),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFD9503C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.ink, width: 3),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: cartoon(15, outline: 1.5, weight: FontWeight.w800),
        ),
      );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.haveSensor});

  final bool haveSensor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.ink, width: 2.5),
      ),
      child: Text(
        haveSensor
            ? tr('hint.tilt')
            : tr('hint.nosensor'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Palette.cream),
      ),
    );
  }
}

String formatTime(double seconds) {
  final m = seconds ~/ 60;
  final s = seconds - m * 60;
  return '${m.toString().padLeft(2, '0')}:${s.toStringAsFixed(1).padLeft(4, '0')}';
}

class _Header extends StatelessWidget {
  const _Header({required this.game});

  final GameController game;

  @override
  Widget build(BuildContext context) {
    final stat = cartoon(17, outline: 1.5, weight: FontWeight.w800)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.woodLight, Palette.wood],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.ink, width: 4),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      // Only the essentials: the way home, the time and the button count.
      child: Row(
        children: [
          _HeaderButton(
            icon: Icons.home_rounded,
            tooltip: tr('tt.menu'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          const Icon(Icons.timer_outlined, size: 20, color: Palette.cream),
          const SizedBox(width: 6),
          Text(formatTime(game.elapsed), style: stat),
          const SizedBox(width: 24),
          const Icon(Icons.radio_button_checked_rounded,
              size: 20, color: Palette.gold),
          const SizedBox(width: 6),
          Text('${game.pressedCount}/${game.maze.gateCount}', style: stat),
          const Spacer(),
          _HeaderButton(
            icon: Icons.replay_rounded,
            tooltip: tr('tt.restart'),
            onPressed: game.restart,
          ),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      ChunkyIconButton(icon: icon, tooltip: tooltip, onTap: onPressed, size: 40);
}

/// A round button with a short caption underneath, so it is clear what it
/// does without a long press.
class _CaptionedButton extends StatelessWidget {
  const _CaptionedButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChunkyIconButton(
          icon: icon,
          tooltip: tooltip,
          onTap: onPressed,
          size: 54,
          round: true,
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
      ],
    );
  }
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.game, required this.won});

  final GameController game;
  final bool won;

  @override
  Widget build(BuildContext context) {
    final gold = ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Palette.gold),
      foregroundColor: const WidgetStatePropertyAll(Palette.woodDark),
    );
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xF51F3322),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Palette.ink, width: 5),
          boxShadow: [
            BoxShadow(
              color: (won ? Palette.gold : Colors.redAccent).withValues(alpha: 0.55),
              blurRadius: 24,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(won ? Icons.emoji_events_rounded : Icons.heart_broken_rounded,
                color: won ? Palette.gold : Colors.redAccent, size: 48),
            const SizedBox(height: 8),
            Text(won ? tr('end.win') : tr(game.lostReason),
                textAlign: TextAlign.center,
                style: cartoon(22, outline: 1.8)),
            const SizedBox(height: 4),
            Text(tr('end.time', {'t': formatTime(game.elapsed)}),
                style: const TextStyle(color: Palette.cream)),
            if (won && game.recordRank > 0) ...[
              const SizedBox(height: 4),
              Text(tr('end.rank', {'n': game.recordRank}),
                  style: const TextStyle(
                      color: Palette.gold, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (won)
                  FilledButton(
                    style: gold,
                    onPressed: game.newMaze,
                    child: Text(tr('end.next')),
                  )
                else ...[
                  FilledButton(
                    style: gold,
                    onPressed: game.restart,
                    child: Text(tr('end.retry')),
                  ),
                  OutlinedButton(
                    onPressed: game.newMaze,
                    child: Text(tr('end.new_maze')),
                  ),
                ],
                OutlinedButton(
                  onPressed: () => showRecords(context, game.config),
                  child: Text(tr('end.records')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
