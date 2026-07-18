import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';

/// Records calls instead of hitting the real `HapticFeedback` platform
/// channel (E8 — implementation-plan.md).
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

Future<AppState> _demoAppState(Haptics haptics) async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings, haptics: haptics);
  await appState.connect(); // demo mode: synchronous population, no haptic yet.
  return appState;
}

void main() {
  group('AppState state-echo confirmation (E8)', () {
    test('a genuinely different submode fires exactly one mediumImpact', () async {
      final haptics = _RecordingHaptics();
      final appState = await _demoAppState(haptics);
      addTearDown(appState.dispose);

      // Demo default: comms starts off.
      expect(appState.modes[MainMode.comms]!.submode, 'off');
      expect(haptics.calls, isEmpty); // initial snapshot never echoes a haptic.

      appState.setSubmode(MainMode.comms, 'fm');

      expect(appState.modes[MainMode.comms]!.submode, 'fm');
      expect(haptics.calls, ['mediumImpact']);
    });

    test('an identical republish (same submode+chan) fires no haptic', () async {
      final haptics = _RecordingHaptics();
      final appState = await _demoAppState(haptics);
      addTearDown(appState.dispose);

      // Demo default: sigint is already 'adsb'.
      expect(appState.modes[MainMode.sigint]!.submode, 'adsb');

      appState.setSubmode(MainMode.sigint, 'adsb');

      expect(appState.modes[MainMode.sigint]!.submode, 'adsb');
      expect(haptics.calls, isEmpty);
    });

    test('a channel-only change (same submode) still fires the haptic', () async {
      final haptics = _RecordingHaptics();
      final appState = await _demoAppState(haptics);
      addTearDown(appState.dispose);

      appState.setSubmode(MainMode.comms, 'dab', chan: 'ndr2');
      expect(haptics.calls, ['mediumImpact']);
      haptics.calls.clear();

      // Same submode ('dab'), different channel — still a real state change.
      appState.setSubmode(MainMode.comms, 'dab', chan: 'deutschlandfunk');
      expect(haptics.calls, ['mediumImpact']);

      haptics.calls.clear();
      // Repeating the exact same submode+chan is a no-op republish.
      appState.setSubmode(MainMode.comms, 'dab', chan: 'deutschlandfunk');
      expect(haptics.calls, isEmpty);
    });
  });
}
