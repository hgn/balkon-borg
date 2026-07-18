import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:balkon_borg/src/state/settings.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/settings_screen.dart';
import 'package:balkon_borg/src/ui/widgets/borg_switch.dart';

Widget _wrap(Settings settings) => ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: const SettingsScreen(),
      ),
    );

/// The settings screen's 5 sections don't fit the default 800x600 test
/// surface, and `ListView` only builds children within (or near) the
/// viewport — so a tall surface is needed to reach the lower sections
/// without scrolling gymnastics in every test.
Future<void> _pumpTall(WidgetTester tester, Settings settings) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_wrap(settings));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Settings renders every section, incl. the demo-mode switch and the App section',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    await _pumpTall(tester, settings);

    expect(find.text('ALLGEMEIN'), findsOneWidget);
    expect(find.text('BROKER'), findsOneWidget);
    expect(find.text('WATCH-WINDOW'), findsOneWidget);
    expect(find.text('BENACHRICHTIGUNGEN'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);

    // Demo-mode switch row (D2, surfaced per E6 scope).
    expect(find.text('Demo-Modus'), findsOneWidget);
    expect(find.byType(BorgSwitch), findsWidgets);

    // App section: version line + APK-source hint.
    expect(find.textContaining('0.1.0'), findsOneWidget);
    expect(find.text('APK-Quelle: borg-pi/apk'), findsOneWidget);
  });

  testWidgets('Tapping an interval chip updates Settings.checkInterval', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await Settings.load();
    expect(settings.checkInterval, const Duration(seconds: 30)); // default
    await _pumpTall(tester, settings);

    await tester.tap(find.text('2 min'));
    await tester.pumpAndSettle();

    expect(settings.checkInterval, const Duration(seconds: 120));
  });

  testWidgets('Toggling the demo-mode switch updates Settings.demoMode', (tester) async {
    SharedPreferences.setMockInitialValues({'demo_mode': true});
    final settings = await Settings.load();
    expect(settings.demoMode, isTrue);
    await _pumpTall(tester, settings);

    // The demo switch is the first BorgSwitch on the screen (ALLGEMEIN is
    // the first section).
    await tester.tap(find.byType(BorgSwitch).first);
    await tester.pumpAndSettle();

    expect(settings.demoMode, isFalse);
  });
}
