import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/ui/boot_overlay.dart';

void main() {
  testWidgets('boot wave renders on start, then disposes itself once done', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BootOverlay(child: Text('shell')),
      ),
    );
    await tester.pump(); // first frame after didChangeDependencies starts the controller.

    // Boot visuals are up: the logo wordmark is showing, and the shell is
    // already mounted underneath (just covered by the boot layer).
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('Borg'), findsOneWidget);

    // Fast-forward past the ≤1.5s budget: the whole boot layer unmounts,
    // leaving only the child — nothing lingers.
    await tester.pump(const Duration(milliseconds: 1400));
    expect(find.text('Borg'), findsNothing);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('enabled: false skips the animation entirely', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: BootOverlay(enabled: false, child: Text('shell')),
      ),
    );
    // No extra pump needed: the overlay decides in didChangeDependencies,
    // before anything boot-related ever paints — so a test using this to
    // exercise the shell/home tree can pump/pumpAndSettle right away.
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('Borg'), findsNothing);
  });

  testWidgets('reduced motion (MediaQuery.disableAnimations) skips it too', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: BootOverlay(child: Text('shell')),
        ),
      ),
    );
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('Borg'), findsNothing);
  });
}
