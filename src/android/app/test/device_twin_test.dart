import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/models/mode_state.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/services/ui_sounds.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/widgets/device_twin.dart';

Future<AppState> _demoAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings);
  await appState.connect(); // demo mode: synchronous population.
  return appState;
}

/// Never connects — `AppState.connected` stays the constructor default
/// (`false`), the "disconnected app" scenario.
Future<AppState> _disconnectedAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': false});
  final settings = await Settings.load();
  return AppState(MqttService(), settings);
}

Widget _wrap(AppState appState, {bool disableAnimations = false}) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        Provider<Haptics>.value(value: const NoopHaptics()),
        Provider<UiSounds>.value(value: const NoopUiSounds()),
      ],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 300, height: 100, child: DeviceTwin()),
            ),
          ),
        ),
      ),
    );

DeviceTwinPainter _painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<DeviceTwinPainter>()
    .single;

void main() {
  group('deviceTwinDiffuserColor', () {
    test('null (light off/unknown) is a dim neutral plate', () {
      final off = deviceTwinDiffuserColor(null);
      // Neutral: red/green/blue all close together, clearly not a vivid hue.
      expect((off.r - off.g).abs(), lessThan(0.15));
      expect(off.computeLuminance(), lessThan(0.2));
    });

    test('a set color lightens toward white rather than staying saturated',
        () {
      const raw = Color(0xFFFF8A3D);
      final tinted = deviceTwinDiffuserColor(raw);
      expect(tinted, Color.lerp(raw, Colors.white, 0.30));
      expect(tinted.computeLuminance(), greaterThan(raw.computeLuminance()));
    });

    test('is stable and distinct from the off color', () {
      expect(deviceTwinDiffuserColor(const Color(0xFF35E6FF)),
          isNot(deviceTwinDiffuserColor(null)));
    });
  });

  group('deviceTwinLedActive', () {
    test('empty modes map: all four off', () {
      expect(deviceTwinLedActive(const {}), [false, false, false, false]);
    });

    test('lumen/comms/sigint light when not off; sentry needs armed, not just not-off', () {
      final active = deviceTwinLedActive({
        MainMode.lumen: const ModeState(submode: 'ambient'),
        MainMode.comms: const ModeState(submode: 'off'),
        MainMode.sigint: const ModeState(submode: 'adsb'),
        MainMode.sentry: const ModeState(submode: 'armed'),
      });
      expect(active, [true, false, true, true]);
    });

    test('sentry present but off stays dark', () {
      final active = deviceTwinLedActive({
        MainMode.sentry: const ModeState(submode: 'off'),
      });
      expect(active[3], isFalse);
    });
  });

  group('deviceTwinVisual', () {
    test('disconnected forces the dim/unknown reading regardless of stale state', () {
      final visual = deviceTwinVisual(
        connected: false,
        wledColor: const Color(0xFFFF0000),
        modes: {MainMode.sentry: const ModeState(submode: 'armed')},
      );
      expect(visual.dim, isTrue);
      expect(visual.ledActive, [false, false, false, false]);
      expect(visual.sentryArmed, isFalse);
      expect(visual.diffuserColor, deviceTwinDiffuserColor(null));
    });

    test('connected + light off reads the neutral plate', () {
      final visual = deviceTwinVisual(connected: true, wledColor: null, modes: const {});
      expect(visual.dim, isFalse);
      expect(visual.diffuserColor, deviceTwinDiffuserColor(null));
    });

    test('connected + light on tints the diffuser and reports sentry armed', () {
      final visual = deviceTwinVisual(
        connected: true,
        wledColor: const Color(0xFF35E6FF),
        modes: {MainMode.sentry: const ModeState(submode: 'armed')},
      );
      expect(visual.dim, isFalse);
      expect(visual.diffuserColor, deviceTwinDiffuserColor(const Color(0xFF35E6FF)));
      expect(visual.sentryArmed, isTrue);
    });
  });

  group('deviceTwinBorderTint', () {
    test('ok and unknown stay untinted (quiet by design)', () {
      expect(deviceTwinBorderTint(AggregateHealth.ok), isNull);
      expect(deviceTwinBorderTint(AggregateHealth.unknown), isNull);
    });

    test('degraded is amber, bad is the danger color', () {
      expect(deviceTwinBorderTint(AggregateHealth.degraded), Colors.amber);
      expect(deviceTwinBorderTint(AggregateHealth.bad), BalkonColors.danger);
    });
  });

  group('DeviceTwin widget', () {
    testWidgets('light off renders the neutral diffuser (demo default: no ambient color)',
        (tester) async {
      final appState = await _demoAppState();
      addTearDown(appState.dispose);

      await tester.pumpWidget(_wrap(appState));
      await tester.pumpAndSettle();

      final painter = _painter(tester);
      expect(painter.dim, isFalse);
      expect(painter.diffuserColor, deviceTwinDiffuserColor(null));
    });

    testWidgets('light on tints the diffuser with the live WLED color', (tester) async {
      final appState = await _demoAppState();
      addTearDown(appState.dispose);

      await tester.pumpWidget(_wrap(appState));
      await tester.pumpAndSettle();

      // Same demo mutation wled_glow_test.dart uses: a LUMEN submode with a
      // plausible ambient color.
      appState.setSubmode(MainMode.lumen, 'cozy');
      await tester.pumpAndSettle();

      final painter = _painter(tester);
      expect(painter.dim, isFalse);
      expect(painter.diffuserColor, deviceTwinDiffuserColor(const Color(0xFFFF8A3D)));
      expect(painter.diffuserColor, isNot(deviceTwinDiffuserColor(null)));
    });

    testWidgets('disconnected dims the whole device instead of reading stale state',
        (tester) async {
      final appState = await _disconnectedAppState();
      addTearDown(appState.dispose);
      expect(appState.connected, isFalse);

      await tester.pumpWidget(_wrap(appState));
      await tester.pumpAndSettle();

      final painter = _painter(tester);
      expect(painter.dim, isTrue);
      expect(painter.ledActive, [false, false, false, false]);
      expect(painter.diffuserColor, deviceTwinDiffuserColor(null));
    });

    testWidgets('disableAnimations renders the final state directly, no crash', (tester) async {
      final appState = await _demoAppState();
      addTearDown(appState.dispose);

      await tester.pumpWidget(_wrap(appState, disableAnimations: true));
      await tester.pump();

      appState.setSubmode(MainMode.lumen, 'cozy');
      await tester.pump(); // a single frame — no animation ticks to wait out.

      final painter = _painter(tester);
      expect(painter.diffuserColor, deviceTwinDiffuserColor(const Color(0xFFFF8A3D)));
    });

    testWidgets('tapping opens the health sheet', (tester) async {
      final appState = await _demoAppState();
      addTearDown(appState.dispose);

      await tester.pumpWidget(_wrap(appState));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DeviceTwin));
      await tester.pumpAndSettle();

      expect(find.text('Health'), findsOneWidget);
    });
  });
}
