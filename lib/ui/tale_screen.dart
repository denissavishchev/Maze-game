import 'dart:async';

import 'package:flutter/material.dart';

import '../game/ball.dart';
import '../game/tale.dart';
import '../l10n/strings.dart';
import 'balls.dart';
import 'kit.dart';
import 'palette.dart';

/// How long a story animation runs: [ms], or nothing at all for a player who
/// has asked the phone for less motion.
Duration storyMotion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: ms);

/// Plays [pages]. Comes back with the ending picked on a choice page, if any.
Future<String?> showTale(BuildContext context, List<TalePage> pages) =>
    Navigator.of(context).push<String>(PageRouteBuilder<String>(
      transitionDuration: storyMotion(context, 320),
      reverseTransitionDuration: storyMotion(context, 320),
      pageBuilder: (_, _, _) => TaleScreen(pages: pages),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));

/// The picture of the ball won at the end of a chapter.
String? rewardAsset(BallKind ball) => switch (ball) {
      BallKind.steel ||
      BallKind.slime ||
      BallKind.glass ||
      BallKind.paper ||
      BallKind.bubble =>
        'assets/images/story/reward_${ball.name}.webp',
      _ => null,
    };

/// The story's picture book: one picture at a time with a line under it, and
/// a tap goes on.
class TaleScreen extends StatefulWidget {
  const TaleScreen({super.key, required this.pages});

  final List<TalePage> pages;

  @override
  State<TaleScreen> createState() => _TaleScreenState();
}

class _TaleScreenState extends State<TaleScreen> with WidgetsBindingObserver {
  int _index = 0;

  /// A page that stands still counts its time only while the game is on
  /// screen: put away and brought back, it waits out the rest.
  Timer? _hold;
  final _held = Stopwatch();

  TalePage get _page => widget.pages[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHold();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hold?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_page.holdSeconds == null) return;
    if (state == AppLifecycleState.resumed) {
      _resumeHold();
    } else {
      _hold?.cancel();
      _held.stop();
    }
  }

  void _startHold() {
    _held
      ..stop()
      ..reset();
    if (_page.holdSeconds != null) _resumeHold();
  }

  void _resumeHold() {
    final left = Duration(seconds: _page.holdSeconds!) - _held.elapsed;
    _hold?.cancel();
    _held.start();
    _hold = Timer(left.isNegative ? Duration.zero : left, _next);
  }

  void _next() {
    _hold?.cancel();
    if (_index + 1 >= widget.pages.length) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _index++);
    _startHold();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final still = page.holdSeconds != null || page.choice;
    final ball = page.ball;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('tale-page'),
        behavior: HitTestBehavior.opaque,
        onTap: still ? null : _next,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: storyMotion(context, 320),
              child: Image.asset(
                page.asset,
                key: ValueKey('${page.image}-${ball != null}'),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                color: ball == null ? null : Colors.black.withValues(alpha: 0.6),
                colorBlendMode: BlendMode.darken,
              ),
            ),
            if (ball != null) _Reward(ball: ball),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                child: Column(
                  children: [
                    if (!still)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('tale-skip'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(tr('tale.skip'), style: cartoon(15, outline: 1.5)),
                        ),
                      ),
                    const Spacer(),
                    if (page.text != null) TalePlate(tr(page.text!)),
                    if (page.choice) ...[
                      ChunkyButton(
                        key: const Key('tale-open'),
                        label: tr('tale.final.choice.open'),
                        look: ButtonLook.leaf,
                        fontSize: 20,
                        onTap: () => Navigator.of(context).pop(endingOpen),
                      ),
                      const SizedBox(height: 14),
                      ChunkyButton(
                        key: const Key('tale-stay'),
                        label: tr('tale.final.choice.stay'),
                        look: ButtonLook.gold,
                        fontSize: 20,
                        onTap: () => Navigator.of(context).pop(endingStay),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ball a chapter gave, coming forward over the dimmed note.
class _Reward extends StatelessWidget {
  const _Reward({required this.ball});

  final BallKind ball;

  @override
  Widget build(BuildContext context) {
    final asset = rewardAsset(ball);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(ball),
          tween: Tween(begin: 0, end: 1),
          duration: storyMotion(context, 320),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
          ),
          child: MossPanel(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('tale.reward'), style: cartoon(24, color: Palette.gold)),
                const SizedBox(height: 14),
                asset == null
                    ? BallBubble(kind: ball, size: 140)
                    : Image.asset(asset, key: const Key('tale-reward-ball'), width: 160, height: 160),
                const SizedBox(height: 10),
                Text(infoOf(ball).name, style: cartoon(20, outline: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of the story on its plate, rising gently into place.
class TalePlate extends StatelessWidget {
  const TalePlate(this.text, {super.key});

  final String text;

  static const Color _plate = Color(0xFF102018);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(text),
        tween: Tween(begin: 0, end: 1),
        duration: storyMotion(context, 240),
        curve: Curves.easeOut,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child),
        ),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: _plate.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.ink, width: 2.5),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.cream,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      );
}

/// The end of the story: its name, a thank you and the way back to the map.
/// A player still without the chameleon is told how to get it.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key, required this.hasChameleon});

  final bool hasChameleon;

  @override
  Widget build(BuildContext context) {
    Widget rise(int ms, Widget child) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: storyMotion(context, ms),
          curve: Curves.easeOut,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
          ),
          child: child,
        );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/story/chapter_5.webp',
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.45),
            colorBlendMode: BlendMode.darken,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  rise(
                    600,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(tr('tale.title'),
                          key: const Key('credits-title'),
                          style: cartoon(36, color: Palette.gold, spacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  rise(1000, TalePlate(tr('tale.credits'))),
                  if (!hasChameleon) ...[
                    const SizedBox(height: 12),
                    rise(1400, TalePlate(tr('tale.ending.chameleon'))),
                  ],
                  const Spacer(flex: 3),
                  rise(
                    1600,
                    ChunkyButton(
                      key: const Key('credits-back'),
                      label: tr('tale.to_map'),
                      icon: Icons.map_rounded,
                      look: ButtonLook.gold,
                      fontSize: 20,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
