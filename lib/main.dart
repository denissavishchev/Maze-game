import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio/haptics.dart';
import 'audio/sfx.dart';
import 'audio/sound_setting.dart';
import 'game/achievements.dart';
import 'game/ball_collection.dart';
import 'game/story_progress.dart';
import 'l10n/strings.dart';
import 'monetization/ad_service.dart';
import 'monetization/store.dart';
import 'monetization/vip.dart';
import 'ui/achievement_popup.dart';
import 'ui/home_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLanguage.instance.load();
  await SoundSetting.instance.load();
  await VibrationSetting.instance.load();
  await Vip.instance.load();
  await StoryProgress.instance.load();
  await BallCollection.instance.load();
  await Achievements.instance.load();
  Sfx.enabled = true;
  Haptics.enabled = true;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MazeApp());
  // After the first frame, so a consent form never delays the start.
  unawaited(AdService.start());
  unawaited(Store.start());
}

class MazeApp extends StatelessWidget {
  const MazeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Orbyrinth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg,
        useMaterial3: true,
      ),
      builder: (context, child) => AchievementPopup(child: child ?? const SizedBox()),
      home: const HomeScreen(),
    );
  }
}
