import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:balkon_borg/src/services/shader_library.dart';
import 'package:balkon_borg/src/ui/widgets/condensation_overlay.dart';

/// `FragmentProgram.fromAsset` cannot compile under `flutter test` (task
/// spec) — every test here runs against [ShaderLibrary.empty], the same
/// "no program available" state a real device falls back to if shader
/// compilation failed. Verifies the host never crashes and stays a no-op.
Widget _host(double? humidity, {bool enabled = true, bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Provider<ShaderLibrary>.value(
      value: ShaderLibrary.empty,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 600,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                CondensationOverlay(humidity: humidity, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders below threshold with no shader available and stays a no-op',
      (tester) async {
    await tester.pumpWidget(_host(60.0));
    await tester.pump();

    expect(find.byType(CondensationOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crossing above 85% humidity does not crash without a compiled shader',
      (tester) async {
    await tester.pumpWidget(_host(60.0));
    await tester.pump();

    await tester.pumpWidget(_host(90.0));
    // Drive through the fade-in and a few drift ticks.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('dropping back below 82% fades out and settles without error', (tester) async {
    await tester.pumpWidget(_host(90.0));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.pumpWidget(_host(70.0));
    await tester.pump(const Duration(milliseconds: 1600)); // past the 1500ms fade.

    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled via settings renders fine even above threshold', (tester) async {
    await tester.pumpWidget(_host(90.0, enabled: false));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('disableAnimations renders fine even above threshold', (tester) async {
    await tester.pumpWidget(_host(90.0, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('no humidity data yet renders fine', (tester) async {
    await tester.pumpWidget(_host(null));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
