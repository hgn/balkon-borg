import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/services/shader_library.dart';
import 'package:balkon_borg/src/services/ui_sounds.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/state/tabs.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/shell.dart';

/// Records calls instead of hitting the real `HapticFeedback` platform
/// channel (mirrors `test/app_state_test.dart`'s `_RecordingHaptics`).
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

/// Records calls instead of hitting the real `audioplayers` plugin channel
/// (mirrors `test/app_state_test.dart`'s `_RecordingUiSounds`).
class _RecordingUiSounds implements UiSounds {
  final List<String> calls = [];

  @override
  void blip() => calls.add('blip');

  @override
  void confirm() => calls.add('confirm');

  @override
  void powerUp() => calls.add('powerUp');

  @override
  void powerDown() => calls.add('powerDown');

  @override
  void pttDown() => calls.add('pttDown');

  @override
  void pttSent() => calls.add('pttSent');

  @override
  void error() => calls.add('error');
}

/// Bounded settle instead of `pumpAndSettle`: demo mode's health includes a
/// "degraded" capability (`wled`, `demo_source.dart`), so the header health
/// dot is "live" and its sonar ping (E8) loops continuously — an ambient
/// animation is always running once demo data is in, same reasoning as
/// radio_screen_test's/camera_screen_test's `_settle`.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('shell renders header + bottom nav and switches tabs on tap',
      (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': true});
    final settings = await Settings.load();
    final appState = AppState(MqttService(), settings);
    addTearDown(appState.dispose);
    await appState.connect(); // demo mode: synchronous population.

    final haptics = _RecordingHaptics();
    final uiSounds = _RecordingUiSounds();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
          Provider<ShaderLibrary>.value(value: ShaderLibrary.empty),
          ChangeNotifierProvider(create: (_) => BorgTabs()),
          Provider<Haptics>.value(value: haptics),
          Provider<UiSounds>.value(value: uiSounds),
        ],
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: const BorgShell(),
        ),
      ),
    );
    await _settle(tester);

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
    expect(find.text('DAB+'), findsNothing); // Radio-only band chip.

    // Tapping a nav item switches the visible tab and fires both the
    // haptic and its "second sense" UI-sound counterpart (E8 follow-up).
    await tester.tap(find.text('Radio'));
    await _settle(tester);

    // Radio tab (E3): opens on the segment holding the tuner, which in demo
    // data is SIGINT (ADS-B). COMMS is one tap away.
    expect(find.text('SIGINT'), findsWidgets);
    expect(find.text('LUMEN'), findsNothing);
    await tester.tap(find.text('COMMS'));
    await _settle(tester);
    expect(find.text('DAB+'), findsOneWidget);

    expect(haptics.calls, contains('selectionClick'));
    expect(uiSounds.calls, contains('blip'));
  });

  // Key the health dot's sonar-ping ring is built with (shell.dart's
  // `_HealthDotState`); a private widget type isn't reachable from this
  // separate test library, so identify it by key instead.
  const pingKey = ValueKey('health-ping-ring');

  testWidgets('health dot sonar ping is present while health is live (demo)', (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': true});
    final settings = await Settings.load();
    final appState = AppState(MqttService(), settings);
    addTearDown(appState.dispose);
    // Demo health includes a "degraded" capability (demo_source.dart) —
    // live, but not the all-green "ok" case either; either way not unknown.
    await appState.connect();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
          Provider<ShaderLibrary>.value(value: ShaderLibrary.empty),
          ChangeNotifierProvider(create: (_) => BorgTabs()),
          Provider<Haptics>.value(value: const NoopHaptics()),
        ],
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: const BorgShell(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byKey(pingKey), findsOneWidget);
  });

  testWidgets('health dot sonar ping is absent while disconnected (unknown)', (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': false});
    final settings = await Settings.load();
    // Never call connect(): stays disconnected with no health data, i.e.
    // AggregateHealth.unknown — the grey dot that must never ping.
    final appState = AppState(MqttService(), settings);
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: appState),
          Provider<ShaderLibrary>.value(value: ShaderLibrary.empty),
          ChangeNotifierProvider(create: (_) => BorgTabs()),
          Provider<Haptics>.value(value: const NoopHaptics()),
        ],
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: const BorgShell(),
        ),
      ),
    );
    // No ambient loop running on this path — safe to fully settle.
    await tester.pumpAndSettle();

    expect(find.byKey(pingKey), findsNothing);
  });
}
