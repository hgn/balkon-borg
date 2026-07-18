import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/shell.dart';
import 'package:balkon_borg/src/ui/widgets/wled_glow.dart';

/// Bounded settle, same reasoning as shell_test.dart: demo mode's health dot
/// sonar ping is an always-running ambient loop, so `pumpAndSettle` never
/// terminates.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('WledGlow reflects a demo LUMEN color and clears when LUMEN goes off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': true});
    final settings = await Settings.load();
    final appState = AppState(MqttService(), settings);
    addTearDown(appState.dispose);
    await appState.connect(); // demo mode: synchronous population.

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
          Provider<Haptics>.value(value: const NoopHaptics()),
        ],
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: const BorgShell(),
        ),
      ),
    );
    await _settle(tester);

    // Demo default LUMEN submode is 'info-ticker' — no plausible ambient
    // color (demo_source.dart), so the glow starts off.
    expect(tester.widget<WledGlow>(find.byType(WledGlow)).color, isNull);

    // Switching LUMEN to a submode with a demo color (the app's own
    // command path, not a direct field write) makes the glow appear.
    appState.setSubmode(MainMode.lumen, 'cozy');
    await _settle(tester);

    final glowColor = tester.widget<WledGlow>(find.byType(WledGlow)).color;
    expect(glowColor, isNotNull);
    expect(glowColor, const Color(0xFFFF8A3D));

    // Turning LUMEN off clears the glow again.
    appState.setSubmode(MainMode.lumen, 'off');
    await _settle(tester);

    expect(tester.widget<WledGlow>(find.byType(WledGlow)).color, isNull);
  });
}
