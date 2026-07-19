import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:balkon_borg/src/models/borg_event.dart';
import 'package:balkon_borg/src/services/shader_library.dart';
import 'package:balkon_borg/src/ui/widgets/sentry_glitch_overlay.dart';

/// `FragmentProgram.fromAsset` cannot compile under `flutter test`
/// (task spec) — every test here runs against [ShaderLibrary.empty], the
/// same "no program available" state a real device would fall back to if
/// shader compilation failed. The one thing worth verifying without a GPU
/// is that the host never crashes and stays a no-op in that state.
Widget _host(
  List<BorgEvent> recentEvents, {
  bool enabled = true,
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Provider<ShaderLibrary>.value(
      value: ShaderLibrary.empty,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Colors.black),
                SentryGlitchOverlay(recentEvents: recentEvents, enabled: enabled),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final now = DateTime(2026, 7, 19, 20, 0);
  BorgEvent at(Duration ago, EventCategory category) =>
      BorgEvent(ts: now.subtract(ago), category: category, text: 'x');

  testWidgets('renders with no shader available and stays a no-op', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();

    expect(find.byType(SentryGlitchOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new security event does not crash the host without a compiled shader',
      (tester) async {
    final baseline = [at(const Duration(minutes: 5), EventCategory.security)];
    await tester.pumpWidget(_host(baseline));
    await tester.pump();

    final withNewEvent = [at(const Duration(seconds: 1), EventCategory.security), ...baseline];
    await tester.pumpWidget(_host(withNewEvent));
    // Pump through the full ~400ms envelope: even a "triggered" state must
    // render as a no-op with no compiled program.
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled via settings renders fine regardless of new events', (tester) async {
    final baseline = [at(const Duration(minutes: 5), EventCategory.security)];
    await tester.pumpWidget(_host(baseline, enabled: false));
    await tester.pump();

    final withNewEvent = [at(const Duration(seconds: 1), EventCategory.security), ...baseline];
    await tester.pumpWidget(_host(withNewEvent, enabled: false));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });

  testWidgets('disableAnimations renders fine regardless of new events', (tester) async {
    final baseline = [at(const Duration(minutes: 5), EventCategory.security)];
    await tester.pumpWidget(_host(baseline, disableAnimations: true));
    await tester.pump();

    final withNewEvent = [at(const Duration(seconds: 1), EventCategory.security), ...baseline];
    await tester.pumpWidget(_host(withNewEvent, disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
