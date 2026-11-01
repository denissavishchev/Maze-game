import 'dart:async';

import 'package:flutter/material.dart';

import '../game/tale.dart';
import '../l10n/strings.dart';
import 'balls.dart';
import 'kit.dart';
import 'palette.dart';

/// Plays [pages]. Comes back with the ending picked on a choice page, if any.
Future<String?> showTale(BuildContext context, List<TalePage> pages) =>
    Navigator.of(context).push<String>(PageRouteBuilder<String>(
      pageBuilder: (_, _, _) => TaleScreen(pages: pages),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));

/// The story's picture book: one picture at a time with a line under it, and
/// a tap goes on.
class TaleScreen extends StatefulWidget {
  const TaleScreen({super.key, required this.pages});

  final List<TalePage> pages;

  @override
  State<TaleScreen> createState() => _TaleScreenState();
}

class _TaleScreenState extends State<TaleScreen> {
  int _index = 0;
  Timer? _hold;

  TalePage get _page => widget.pages[_index];

  @override
  void initState() {
    super.initState();
    _startHold();
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _startHold() {
    final seconds = _page.holdSeconds;
    if (seconds != null) _hold = Timer(Duration(seconds: seconds), _next);
  }

  void _next() {
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
              duration: const Duration(milliseconds: 450),
              child: Image.asset(
                page.asset,
                key: ValueKey(page.image),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                color: ball == null ? null : Colors.black.withValues(alpha: 0.6),
                colorBlendMode: BlendMode.darken,
              ),
            ),
            if (ball != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
                  child: MossPanel(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('tale.reward'),
                            style: cartoon(24, color: Palette.gold)),
                        const SizedBox(height: 16),
                        BallBubble(kind: ball, size: 120),
                        const SizedBox(height: 10),
                        Text(infoOf(ball).name, style: cartoon(20, outline: 1.5)),
                      ],
                    ),
                  ),
                ),
              ),
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
                          child: Text(tr('tale.skip'),
                              style: cartoon(15, outline: 1.5)),
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

/// A line of the story on its dark plate.
class TalePlate extends StatelessWidget {
  const TalePlate(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 440),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.ink, width: 2.5),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Palette.cream,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      );
}
