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
import 'package:balkon_borg/src/ui/home_screen.dart';
import 'package:balkon_borg/src/ui/widgets/borg_switch.dart';
import 'package:balkon_borg/src/ui/widgets/env_chart.dart';

/// Records calls instead of hitting the real `HapticFeedback` platform
/// channel (same style as `_RecordingHaptics` in app_state_test.dart).
class _RecordingHaptics implements Haptics {
  final List<String> calls = [];

  @override
  void selectionClick() => calls.add('selectionClick');

  @override
  void lightImpact() => calls.add('lightImpact');

  @override
  void mediumImpact() => calls.add('mediumImpact');

  @override
  void heavyImpact() => calls.add('heavyImpact');
}

Future<AppState> _demoAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings);
  await appState.connect(); // demo mode: synchronous population.
  return appState;
}

Widget _wrap(AppState appState, Settings settings, {Haptics? haptics}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(create: (_) => BorgTabs()),
        Provider<Haptics>.value(value: haptics ?? const NoopHaptics()),
        Provider<UiSounds>.value(value: const NoopUiSounds()),
      ],
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: const Scaffold(body: HomeScreen()),
      ),
    );

void main() {
  testWidgets('Home shows the 4 mode cards and env tiles from demo data', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();

    for (final label in ['LUMEN', 'COMMS', 'SIGINT', 'SENTRY']) {
      expect(find.text(label), findsOneWidget);
    }
    // DemoSource: lumen=ticker, comms=off, sigint=adsb, sentry=off.
    expect(find.text('Info-Ticker'), findsOneWidget);
    expect(find.text('ADS-B'), findsOneWidget);
    expect(find.text('Aus'), findsNWidgets(2));

    // Env stat tiles, built from the last demo envHistory sample.
    expect(find.text('Temperatur'), findsOneWidget);
    expect(find.text('Luftfeuchte'), findsOneWidget);
    expect(find.text('Luftdruck'), findsOneWidget);
    final latest = appState.envHistory.last;
    expect(find.text('${latest.t.toStringAsFixed(1)}°C'), findsOneWidget);
  });

  testWidgets('tapping a mode card opens the submode sheet', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text('LUMEN'));
    await tester.pumpAndSettle();

    // Sheet title + a submode option that isn't visible on the card itself.
    expect(find.text('Disco'), findsOneWidget);
    expect(find.text('Ambient'), findsOneWidget);
  });

  testWidgets('selecting a submode in demo mode updates the card value', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();

    // COMMS starts off.
    expect(find.text('Aus'), findsNWidgets(2));

    await tester.tap(find.text('COMMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FM'));
    await tester.pumpAndSettle();

    expect(appState.modes[MainMode.comms]!.submode, 'fm');
    // The sheet deliberately stays open after a pick (user call 2026-07-19),
    // so 'FM' is on screen twice now: the sheet row and the card behind it.
    expect(find.text('FM'), findsNWidgets(2));
    expect(find.text('COMMS'), findsWidgets); // sheet header still up
  });

  testWidgets('the header switch turns a mode off and back to its last program', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LUMEN'));
    await tester.pumpAndSettle();

    final running = appState.modes[MainMode.lumen]!.submode;
    expect(running, isNot('off')); // demo data starts LUMEN on a program

    // "Aus" is no longer offered as a row; it is the switch in the header. The
    // two remaining ones are the COMMS and SENTRY cards behind the sheet, the
    // same count as before it opened.
    expect(find.text('Aus'), findsNWidgets(2));

    await tester.tap(find.byType(BorgSwitch));
    await tester.pumpAndSettle();
    expect(appState.modes[MainMode.lumen]!.submode, 'off');

    await tester.tap(find.byType(BorgSwitch));
    await tester.pumpAndSettle();
    expect(appState.modes[MainMode.lumen]!.submode, running);
  });

  testWidgets('starting COMMS from Home switches SIGINT off — one tuner', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    // Demo defaults: sigint runs ADS-B, comms is off.
    expect(appState.modes[MainMode.sigint]!.submode, 'adsb');

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMMS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FM'));
    await tester.pump();

    expect(appState.modes[MainMode.comms]!.submode, 'fm');
    expect(appState.modes[MainMode.sigint]!.submode, 'off');
    expect(find.textContaining('SIGINT pausiert'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2100)); // drain the snackbar
  });

  testWidgets('a submode row is tappable across its full width', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('COMMS'));
    await tester.pumpAndSettle();

    // Tap near the right edge of the row, far from the label glyphs — with a
    // shrink-wrapped row this lands on the sheet background and does nothing.
    final row = tester.getRect(find.byKey(const ValueKey('submode-fm')));
    await tester.tapAt(Offset(row.right - 8, row.center.dy));
    await tester.pumpAndSettle();

    expect(appState.modes[MainMode.comms]!.submode, 'fm');
  });

  testWidgets('scrubbing the env chart shows the selected sample, not the current value', (
    tester,
  ) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());
    final haptics = _RecordingHaptics();

    await tester.pumpWidget(_wrap(appState, settings, haptics: haptics));
    await tester.pumpAndSettle();

    final latest = appState.envHistory.last;
    final currentText = '${latest.t.toStringAsFixed(1)}°C';
    await tester.tap(find.text('Temperatur'));
    await tester.pumpAndSettle();
    // Scope to the sheet: the stat tile behind it may show the same text.
    final inSheet = find.descendant(of: find.byType(BottomSheet), matching: find.text(currentText));
    expect(inSheet, findsOneWidget);

    final chartRect = tester.getRect(find.byType(EnvChart));
    final gesture = await tester.startGesture(chartRect.centerLeft);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();

    final index = nearestSampleIndex(
      dx: 30,
      width: chartRect.width,
      length: appState.envHistory.length,
    )!;
    final selectedSample = appState.envHistory[index];
    final expectedTime = '${selectedSample.ts.hour.toString().padLeft(2, '0')}:'
        '${selectedSample.ts.minute.toString().padLeft(2, '0')}';
    final scrubText = '${selectedSample.t.toStringAsFixed(1)}°C · $expectedTime';

    expect(find.text(scrubText), findsOneWidget);
    expect(inSheet, findsNothing); // current-value readout is swapped out in the sheet.
    expect(haptics.calls, isNotEmpty);

    await gesture.up();
    await tester.pump();

    expect(find.text(scrubText), findsNothing);
    expect(inSheet, findsOneWidget); // restored, no stale selection.
  });
}
