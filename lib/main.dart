import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'audio/haptics.dart';
import 'audio/sfx.dart';
import 'audio/sound_setting.dart';
import 'l10n/strings.dart';
import 'ui/home_screen.dart';
import 'ui/palette.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLanguage.instance.load();
  await SoundSetting.instance.load();
  await VibrationSetting.instance.load();
  Sfx.enabled = true;
  Haptics.enabled = true;
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MazeApp());
}

class MazeApp extends StatelessWidget {
  const MazeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maze',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
