import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/log_screen.dart';

Future<AppState> _demoAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings);
  await appState.connect(); // demo mode: synchronous population.
  return appState;
}

Widget _wrap(AppState appState, Settings settings) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: appState),
      ],
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: const Scaffold(body: LogScreen()),
      ),
    );

void main() {
  testWidgets('Log shows the bird-of-the-day header and demo log rows', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();

    expect(find.text('VOGEL DES TAGES'), findsOneWidget);

    // DemoSource: Amsel is bird of the day, count=5.
    final birdOfDay = appState.birdOfDay;
    expect(birdOfDay, isNotNull);
    expect(birdOfDay!.species, 'Amsel');
    expect(birdOfDay.count, 5);
    expect(find.text('Amsel'), findsWidgets);
    expect(find.textContaining('5× heute'), findsOneWidget);

    // At least one log row for a different demo species.
    expect(find.text('Kohlmeise'), findsWidgets);
  });
}
