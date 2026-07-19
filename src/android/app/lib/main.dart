import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/services/haptics.dart';
import 'src/services/mqtt_service.dart';
import 'src/services/shader_library.dart';
import 'src/services/sound_class.dart';
import 'src/services/ui_sounds.dart';
import 'src/state/app_state.dart';
import 'src/state/settings.dart';
import 'src/state/tabs.dart';
import 'src/theme/balkon_theme.dart';
import 'src/ui/boot_overlay.dart';
import 'src/ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  // E11: compiled once here, up front — compilation is allowed to fail (old
  // device, Impeller quirk), in which case `ShaderLibrary` just carries
  // `null` programs and every effect widget renders nothing extra
  // (services/shader_library.dart).
  final shaders = await ShaderLibrary.load();
  runApp(BalkonBorgApp(settings: settings, shaders: shaders));
}

class BalkonBorgApp extends StatelessWidget {
  const BalkonBorgApp({super.key, required this.settings, required this.shaders});

  final Settings settings;
  final ShaderLibrary shaders;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        // Compiled once in main() (E11); looked up by the effect widgets
        // themselves (`sentry_glitch_overlay.dart`, `condensation_overlay.dart`).
        Provider<ShaderLibrary>.value(value: shaders),
        // Gated by Settings.hapticsEnabled (E8, services/haptics.dart);
        // widgets read this via Provider, AppState gets it via constructor
        // injection (it has no BuildContext of its own).
        // Above MaterialApp on purpose: modal sheets are pushed on the root
        // navigator and would not see a provider living inside the shell.
        ChangeNotifierProvider(create: (_) => BorgTabs()),
        Provider<Haptics>(
          create: (_) => SystemHaptics(() => settings.hapticsEnabled),
        ),
        // Gated by Settings.uiSoundsEnabled (services/ui_sounds.dart), the
        // "second sense" alongside Haptics — same injection pattern.
        Provider<UiSounds>(
          create: (_) => PackageUiSounds(settings.soundAudible),
        ),
        ChangeNotifierProvider(
          create: (context) => AppState(
            MqttService(),
            settings,
            haptics: context.read<Haptics>(),
            uiSounds: context.read<UiSounds>(),
          )..connect(),
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
          home: BootOverlay(
            playSound: settings.soundAudible(SoundClass.boot),
            child: const BorgShell(),
          ),
        ),
      ),
    );
  }
}
