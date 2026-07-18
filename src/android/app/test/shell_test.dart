import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/shell.dart';

void main() {
  testWidgets('shell renders header + bottom nav and switches tabs on tap',
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
        ],
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: const BorgShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Header.
    expect(find.text('BALKON'), findsOneWidget);
    expect(find.text('Borg'), findsOneWidget);

    // Bottom nav, all 4 items.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Kamera'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Log'), findsOneWidget);

    // Home tab is visible initially (E2 mode-card grid).
    expect(find.text('LUMEN'), findsOneWidget);
    expect(find.text('E3 FOLGT'), findsNothing);

    // Tapping a nav item switches the visible tab.
    await tester.tap(find.text('Radio'));
    await tester.pumpAndSettle();

    expect(find.text('E3 FOLGT'), findsOneWidget);
    expect(find.text('LUMEN'), findsNothing);
  });
}
