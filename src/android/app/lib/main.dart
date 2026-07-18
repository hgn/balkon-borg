import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/services/haptics.dart';
import 'src/services/mqtt_service.dart';
import 'src/state/app_state.dart';
import 'src/state/settings.dart';
import 'src/theme/balkon_theme.dart';
import 'src/ui/boot_overlay.dart';
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
        // Gated by Settings.hapticsEnabled (E8, services/haptics.dart);
        // widgets read this via Provider, AppState gets it via constructor
        // injection (it has no BuildContext of its own).
        Provider<Haptics>(
          create: (_) => SystemHaptics(() => settings.hapticsEnabled),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              AppState(MqttService(), settings, haptics: context.read<Haptics>())..connect(),
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
          // Boot-Welle (E7): runs once per cold start, revealing the shell
          // underneath — never re-triggered by resume or tab switches since
          // BootOverlay only ever mounts here, at the app root.
          home: const BootOverlay(child: BorgShell()),
        ),
      ),
    );
  }
}
