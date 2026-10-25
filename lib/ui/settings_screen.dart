import 'package:flutter/material.dart';

import '../audio/haptics.dart';
import '../audio/sfx.dart';
import '../audio/sound_setting.dart';
import '../game/ball_collection.dart';
import '../l10n/strings.dart';
import '../monetization/vip.dart';
import 'kit.dart';
import 'palette.dart';

/// Settings: the language and whether sound effects are on.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the language or the sound setting changes.
    return ListenableBuilder(
      listenable: Listenable.merge([
        AppLanguage.instance,
        SoundSetting.instance,
        VibrationSetting.instance,
        Sfx.lastError,
        Vip.instance,
      ]),
      builder: (context, _) => Scaffold(
        body: ArtBackdrop(
          dim: 0.5,
          blur: 5,
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
                      _topBar(context),
                      const SizedBox(height: 22),
                      _card(
                        icon: Icons.language_rounded,
                        title: tr('set.language'),
                        child: _languages(),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        icon: SoundSetting.instance.on
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        title: tr('set.sound'),
                        child: _sound(),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        icon: Icons.vibration_rounded,
                        title: tr('set.vibration'),
                        child: _vibration(),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        icon: Icons.workspace_premium_rounded,
                        title: tr('set.vip'),
                        child: _vip(),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        icon: Icons.sports_baseball_rounded,
                        title: tr('set.balls'),
                        child: TextButton(
                          key: const Key('reset-balls'),
                          onPressed: BallCollection.instance.reset,
                          style: TextButton.styleFrom(foregroundColor: Palette.sand),
                          child: Text(tr('set.balls_reset')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) => Row(
        children: [
          ChunkyIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(tr('settings'), style: cartoon(24, spacing: 3)),
            ),
          ),
        ],
      );

  Widget _card({required IconData icon, required String title, required Widget child}) {
    return MossPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Palette.gold),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(title, style: cartoon(18, outline: 1.5, spacing: 1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  /// One button per language, named in that language.
  Widget _languages() {
    final current = AppLanguage.instance.lang;
    return Row(
      children: [
        for (final l in AppLang.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => AppLanguage.instance.set(l),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: l == current
                          ? const [Color(0xFFFFD968), Color(0xFFE0A21F)]
                          : const [Palette.woodLight, Palette.wood],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Palette.ink, width: 3),
                  ),
                  child: Column(
                    children: [
                      Text(l.label,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: l == current ? Palette.woodDark : Palette.cream,
                          )),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(l.nativeName,
                            style: TextStyle(
                              fontSize: 12,
                              color: l == current
                                  ? Palette.woodDark
                                  : Palette.cream.withValues(alpha: 0.85),
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _vip() {
    final on = Vip.instance.on;
    return Row(
      children: [
        Expanded(
          child: Text(on ? tr('set.vip_on') : tr('set.vip_off'),
              style: const TextStyle(fontSize: 16, color: Palette.cream)),
        ),
        Switch(
          key: const Key('vip-switch'),
          value: on,
          activeThumbColor: Palette.gold,
          activeTrackColor: Palette.leafMid,
          onChanged: Vip.instance.set,
        ),
      ],
    );
  }

  Widget _vibration() {
    final on = VibrationSetting.instance.on;
    return Row(
      children: [
        Expanded(
          child: Text(on ? tr('set.vib_on') : tr('set.vib_off'),
              style: const TextStyle(fontSize: 16, color: Palette.cream)),
        ),
        Switch(
          value: on,
          activeThumbColor: Palette.gold,
          activeTrackColor: Palette.leafMid,
          onChanged: VibrationSetting.instance.set,
        ),
      ],
    );
  }

  Widget _sound() {
    final on = SoundSetting.instance.on;
    final error = Sfx.lastError.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(on ? tr('set.sound_on') : tr('set.sound_off'),
                  style: const TextStyle(fontSize: 16, color: Palette.cream)),
            ),
            Switch(
              value: on,
              activeThumbColor: Palette.gold,
              activeTrackColor: Palette.leafMid,
              onChanged: SoundSetting.instance.set,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Plays a short knock, so the player can check that sound works.
        OutlinedButton.icon(
          onPressed: on ? () => Sfx.play(Sound.impactWood) : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: Palette.cream,
            side: const BorderSide(color: Palette.sand, width: 1.5),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(tr('set.test')),
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(tr('set.sound_error', {'e': error}),
              style: const TextStyle(color: Color(0xFFFF8A7A), fontSize: 12.5)),
        ],
      ],
    );
  }
}
