import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/services/ui_sounds.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/state/tabs.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/radio_screen.dart';

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
        ChangeNotifierProvider(create: (_) => BorgTabs()),
        Provider<Haptics>.value(value: const NoopHaptics()),
        Provider<UiSounds>.value(value: const NoopUiSounds()),
      ],
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: const Scaffold(body: RadioScreen()),
      ),
    );

/// Bounded settle after a tap that may activate a mode: once a viewed mode
/// is non-off, `EqBars` repeats its animation forever, so `pumpAndSettle`
/// would never return. A fixed pump long enough for the 300ms chip/preset
/// spring *and* the ~2s SnackBar auto-dismiss also drains any pending
/// SnackBar timer, avoiding a leftover-timer failure at test teardown.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2100));
}

void main() {
  testWidgets('segmented tab switch shows COMMS content vs SIGINT content', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    // Bounded: the screen opens on whichever mode holds the tuner, and demo
    // SIGINT runs ADS-B, whose radar sweeps forever by design.
    await _settle(tester);

    // Demo SIGINT runs ADS-B, so the screen opens on the SIGINT segment: it
    // shows whichever mode currently holds the single tuner.
    expect(find.textContaining('Flugzeug-Tracking'), findsOneWidget);
    expect(find.text('DAB+'), findsNothing);

    await tester.tap(find.text('COMMS'));
    await _settle(tester);

    expect(find.text('DAB+'), findsOneWidget);
    expect(find.textContaining('Flugzeug-Tracking'), findsNothing);
  });

  testWidgets('tapping a band chip switches which preset list is shown', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await _settle(tester);
    await tester.tap(find.text('COMMS')); // opens on SIGINT (demo ADS-B runs)
    await _settle(tester);

    await tester.tap(find.text('FM'));
    await _settle(tester);
    expect(find.text('Bayern 3'), findsOneWidget);

    await tester.tap(find.text('Flugfunk'));
    await _settle(tester);
    expect(find.text('Approach'), findsOneWidget);
    expect(find.text('Bayern 3'), findsNothing);
  });

  testWidgets('selecting a DAB+ station in demo mode updates the active card', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await _settle(tester);
    await tester.tap(find.text('COMMS')); // opens on SIGINT (demo ADS-B runs)
    await _settle(tester);

    // COMMS starts off; tapping DAB+ activates it at its default station.
    await tester.tap(find.text('DAB+'));
    await _settle(tester);

    expect(appState.modes[MainMode.comms]!.submode, 'dab');
    expect(appState.modes[MainMode.comms]!.chan, 'deutschlandfunk');
    expect(find.textContaining('Deutschlandfunk'), findsWidgets);
  });

  testWidgets('activating COMMS displaces an active SIGINT function', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    // demo defaults: sigint=adsb, comms=off.
    expect(appState.modes[MainMode.sigint]!.submode, 'adsb');
    expect(appState.modes[MainMode.comms]!.submode, 'off');

    await tester.pumpWidget(_wrap(appState, settings));
    await _settle(tester);
    await tester.tap(find.text('COMMS')); // opens on SIGINT (demo ADS-B runs)
    await _settle(tester);

    await tester.tap(find.text('DAB+'));
    // Single bounded pump (not the full drain) so the SnackBar is still
    // visible for the text assertion, per the task's own guidance on
    // avoiding pumpAndSettle while a SnackBar timer is pending.
    await tester.pump();

    expect(appState.modes[MainMode.sigint]!.submode, 'off');
    expect(find.textContaining('SIGINT pausiert'), findsOneWidget);

    // Drain the SnackBar's timer so no pending Timer leaks past the test.
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
