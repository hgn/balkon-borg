import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/services/mqtt_service.dart';
import 'src/state/app_state.dart';
import 'src/state/settings.dart';
import 'src/theme/balkon_theme.dart';
import 'src/ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  runApp(BalkonBorgApp(settings: settings));
}

class BalkonBorgApp extends StatelessWidget {
  const BalkonBorgApp({super.key, required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider(
          create: (_) => AppState(MqttService(), settings)..connect(),
        ),
      ],
      child: Consumer<Settings>(
        builder: (context, settings, _) => MaterialApp(
          title: 'Balkon-Borg',
          theme: buildBalkonTheme(brightness: Brightness.light),
          darkTheme: buildBalkonTheme(brightness: Brightness.dark),
          themeMode: settings.themeMode,
          // Light/dark crossfade (motion.md §5): MaterialApp already wraps
          // its child in an AnimatedTheme, driven by these two knobs.
          themeAnimationDuration: balkonThemeCrossfadeDuration,
          themeAnimationCurve: balkonThemeCrossfadeCurve,
          home: const BorgShell(),
        ),
      ),
    );
  }
}
