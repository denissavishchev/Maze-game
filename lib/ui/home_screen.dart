import 'package:flutter/material.dart';

import '../game/world.dart';
import '../l10n/strings.dart';
import 'kit.dart';
import 'menu_screen.dart';
import 'palette.dart';
import 'records_sheet.dart';
import 'settings_screen.dart';
import 'story_map_screen.dart';

/// Main menu: the key art as the backdrop, the title on a wooden sign and
/// three buttons.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppLanguage.instance,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    return Scaffold(
      body: ArtBackdrop(
        dim: 0.12,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    const _Sign(),
                    const Spacer(flex: 4),
                    ChunkyButton(
                      label: tr('play.story'),
                      icon: Icons.map_rounded,
                      look: ButtonLook.gold,
                      fontSize: 20,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const StoryMapScreen()),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: tr('play.endless'),
                      icon: Icons.all_inclusive_rounded,
                      look: ButtonLook.leaf,
                      fontSize: 20,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SelectScreen(endless: true),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: tr('play.single'),
                      icon: Icons.play_arrow_rounded,
                      look: ButtonLook.leaf,
                      fontSize: 20,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const SelectScreen()),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: tr('records'),
                      icon: Icons.emoji_events_rounded,
                      onTap: () => showRecords(
                        context,
                        const GameConfig(WorldKind.forest, 1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ChunkyButton(
                      label: tr('settings'),
                      icon: Icons.settings_rounded,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The game's title on a wooden sign with a leaf on each side.
class _Sign extends StatelessWidget {
  const _Sign();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppLanguage.instance,
        builder: (context, _) => _sign(),
      );

  Widget _sign() {
    return Chunky(
      colors: const [Palette.woodLight, Palette.wood],
      border: 5,
      radius: 22,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      glow: const Color(0x66FFE2A8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.eco_rounded, color: Palette.leaf, size: 34, shadows: [
            Shadow(color: Palette.ink, offset: Offset(0, 2)),
            Shadow(color: Palette.ink, offset: Offset(1.5, 0)),
            Shadow(color: Palette.ink, offset: Offset(-1.5, 0)),
          ]),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(tr('title'), style: cartoon(40, spacing: 4, outline: 2.5)),
            ),
          ),
          const SizedBox(width: 10),
          Transform.scale(
            scaleX: -1,
            child: const Icon(Icons.eco_rounded, color: Palette.leaf, size: 34, shadows: [
              Shadow(color: Palette.ink, offset: Offset(0, 2)),
              Shadow(color: Palette.ink, offset: Offset(1.5, 0)),
              Shadow(color: Palette.ink, offset: Offset(-1.5, 0)),
            ]),
          ),
        ],
      ),
    );
  }
}
