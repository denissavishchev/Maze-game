import 'dart:async';

import 'package:flutter/material.dart';

import '../game/achievements.dart';
import '../l10n/strings.dart';
import 'kit.dart';
import 'palette.dart';

/// Slides a card up from the bottom of whatever screen is showing whenever an
/// achievement is earned, one at a time.
class AchievementPopup extends StatefulWidget {
  const AchievementPopup({super.key, required this.child});

  final Widget child;

  @override
  State<AchievementPopup> createState() => _AchievementPopupState();
}

class _AchievementPopupState extends State<AchievementPopup> {
  static const _slide = Duration(milliseconds: 350);
  static const _hold = Duration(milliseconds: 3200);

  final List<String> _queue = [];
  String? _showing;
  bool _up = false;
  bool _busy = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    Achievements.instance.addListener(_collect);
    _collect();
  }

  @override
  void dispose() {
    _gone = true;
    Achievements.instance.removeListener(_collect);
    super.dispose();
  }

  void _collect() {
    final fresh = Achievements.instance.fresh;
    if (fresh.isEmpty) return;
    _queue.addAll(fresh);
    fresh.clear();
    if (!_busy) _next();
  }

  Future<void> _next() async {
    _busy = true;
    while (_queue.isNotEmpty && !_gone) {
      setState(() {
        _showing = _queue.removeAt(0);
        _up = false;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (_gone) return;
      setState(() => _up = true);
      await Future<void>.delayed(_slide + _hold);
      if (_gone) return;
      setState(() => _up = false);
      await Future<void>.delayed(_slide);
    }
    _busy = false;
    if (!_gone) setState(() => _showing = null);
  }

  @override
  Widget build(BuildContext context) {
    final id = _showing;
    return Stack(
      children: [
        widget.child,
        if (id != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 16),
              child: IgnorePointer(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AnimatedSlide(
                      duration: _slide,
                      curve: Curves.easeOutCubic,
                      offset: _up ? Offset.zero : const Offset(0, 1.6),
                      child: AnimatedOpacity(
                        duration: _slide,
                        opacity: _up ? 1 : 0,
                        child: _Card(id),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.id);

  final String id;

  @override
  Widget build(BuildContext context) {
    final a = achievementList.firstWhere((a) => a.id == id);
    return Material(
      type: MaterialType.transparency,
      child: Chunky(
        key: Key('ach-popup-$id'),
        colors: const [Palette.woodLight, Palette.wood],
        border: 4,
        radius: 18,
        // The thin inner line sits half as far from the edge as the default.
        padding: const EdgeInsets.all(6),
        glow: const Color(0x66FFE2A8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.woodDark,
                border: Border.all(color: Palette.gold, width: 3),
              ),
              child: Icon(a.icon, color: Palette.gold, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('ach.title'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: Palette.cream)),
                  Text(tr('ach.${a.id}'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900, color: Palette.ink)),
                  Text(tr('ach.${a.id}.desc'),
                      style: const TextStyle(fontSize: 13, color: Palette.ink)),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
