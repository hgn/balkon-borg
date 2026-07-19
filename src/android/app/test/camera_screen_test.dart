import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/services/shader_library.dart';
import 'package:balkon_borg/src/services/talkdown_recorder.dart';
import 'package:balkon_borg/src/services/ui_sounds.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/state/tabs.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/camera_screen.dart';
import 'package:balkon_borg/src/ui/widgets/ptt_button.dart';
import 'package:balkon_borg/src/ui/widgets/sentry_switch.dart';

/// No-op stand-in for [TalkdownRecorder]: widget tests must never touch the
/// real `record` plugin channel (no platform binding under `flutter test`).
/// `CameraScreen` accepts an injectable recorder exactly for this.
class _FakeRecorder implements TalkdownRecorder {
  bool started = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async => started = true;

  @override
  Future<String?> stop() async {
    started = false;
    return 'fake.wav';
  }

  @override
  Future<void> cancel() async => started = false;

  @override
  Future<void> dispose() async {}
}

Future<AppState> _demoAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings);
  await appState.connect(); // demo mode: synchronous population.
  return appState;
}

Widget _wrap(AppState appState, Settings settings, TalkdownRecorder recorder) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: appState),
        Provider<ShaderLibrary>.value(value: ShaderLibrary.empty),
        ChangeNotifierProvider(create: (_) => BorgTabs()),
        Provider<Haptics>.value(value: const NoopHaptics()),
        Provider<UiSounds>.value(value: const NoopUiSounds()),
      ],
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: Scaffold(body: CameraScreen(recorder: recorder)),
      ),
    );

/// Bounded settle instead of `pumpAndSettle`: the LIVE dot pulses
/// continuously in demo mode by design (components.md, "demo: pulse on"),
/// so an ambient animation is *always* running on this screen and
/// `pumpAndSettle` would never return. Long enough to drain the 300ms
/// spring transitions and, where used after a PTT release, the ~2s SnackBar
/// auto-dismiss timer too (same reasoning as radio_screen_test's `_settle`).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 2100));
}

void main() {
  testWidgets('Camera screen renders live area, SENTRY card and PTT from demo state', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    await tester.pumpWidget(_wrap(appState, settings, _FakeRecorder()));
    await _settle(tester);

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('SENTRY'), findsOneWidget);
    expect(find.text('Nicht scharf'), findsOneWidget); // demo: sentry starts off.
    expect(find.text('HALTEN'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget); // default voice-effect chip.
  });

  testWidgets('toggling the SENTRY switch in demo mode flips status and border', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());

    expect(appState.modes[MainMode.sentry]!.submode, 'off');

    await tester.pumpWidget(_wrap(appState, settings, _FakeRecorder()));
    await _settle(tester);
    expect(find.text('Nicht scharf'), findsOneWidget);

    await tester.tap(find.byType(SentrySwitch));
    await _settle(tester);

    expect(appState.modes[MainMode.sentry]!.submode, 'armed');
    expect(find.text('Scharf — Kamera bestätigt Personen'), findsOneWidget);
    expect(find.text('Nicht scharf'), findsNothing);

    // Disarm again, back to the off status line.
    await tester.tap(find.byType(SentrySwitch));
    await _settle(tester);
    expect(appState.modes[MainMode.sentry]!.submode, 'off');
    expect(find.text('Nicht scharf'), findsOneWidget);
  });

  testWidgets('PTT press-down changes the label to AUFNAHME', (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);
    final settings = Settings(await SharedPreferences.getInstance());
    final recorder = _FakeRecorder();

    await tester.pumpWidget(_wrap(appState, settings, recorder));
    await _settle(tester);
    expect(find.text('HALTEN'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(PttButton)));
    await _settle(tester);

    expect(find.text('AUFNAHME'), findsOneWidget);
    expect(find.text('HALTEN'), findsNothing);
    expect(recorder.started, isTrue);

    await gesture.up();
    await _settle(tester);

    expect(find.text('HALTEN'), findsOneWidget);
    expect(recorder.started, isFalse);

    // Release in demo mode shows a "Demo — nicht gesendet" SnackBar; drain
    // its ~2s auto-dismiss timer fully so nothing leaks past the test (same
    // reasoning as radio_screen_test's displacement-SnackBar teardown).
    await tester.pump(const Duration(milliseconds: 2100));
  });
}
