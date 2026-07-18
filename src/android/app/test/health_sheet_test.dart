import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/services/mqtt_service.dart';
import 'package:balkon_borg/src/state/app_state.dart';
import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/widgets/health_sheet.dart';

Future<AppState> _demoAppState() async {
  SharedPreferences.setMockInitialValues({'demo_mode': true});
  final settings = await Settings.load();
  final appState = AppState(MqttService(), settings);
  await appState.connect(); // demo mode: synchronous population.
  return appState;
}

void main() {
  testWidgets('Health sheet shows one row per capability with the right state colors',
      (tester) async {
    final appState = await _demoAppState();
    addTearDown(appState.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showHealthSheet(context, appState),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // DemoSource (services/demo_source.dart): 7 capabilities, all "ok"
    // except "wled" ("degraded", detail: "reconnecting").
    expect(find.text('clock'), findsOneWidget);
    expect(find.text('sdr'), findsOneWidget);
    expect(find.text('mic'), findsOneWidget);
    expect(find.text('speaker'), findsOneWidget);
    expect(find.text('camera'), findsOneWidget);
    expect(find.text('esp'), findsOneWidget);
    expect(find.text('wled'), findsOneWidget);
    expect(find.text('reconnecting'), findsOneWidget); // wled's detail line.

    // The aggregate summary line under the sheet title.
    expect(find.text('demo mode — wled reconnecting'), findsOneWidget);

    // One 10x10 circular dot per capability row: 6 green (ok), 1 amber
    // (degraded) — the color coding health_sheet.dart uses for HealthState.
    final dots = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.decoration is BoxDecoration &&
              (c.decoration! as BoxDecoration).shape == BoxShape.circle &&
              c.constraints?.maxWidth == 10,
        )
        .toList();
    expect(dots, hasLength(7));
    final colors = dots.map((c) => (c.decoration! as BoxDecoration).color).toList();
    expect(colors.where((c) => c == Colors.green), hasLength(6));
    expect(colors.where((c) => c == Colors.amber), hasLength(1));
  });
}
