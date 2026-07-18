import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/services/boot_sound.dart';
import 'package:balkon_borg/src/ui/boot_overlay.dart';

/// Records calls instead of touching the real `audioplayers` plugin channel
/// (E8 — implementation-plan.md).
class _FakeBootSound implements BootSound {
  int playCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> dispose() async => disposeCount++;
}

void main() {
  testWidgets('boot wave renders on start, then disposes itself once done', (tester) async {
    final sound = _FakeBootSound();
    await tester.pumpWidget(
      MaterialApp(
        home: BootOverlay(soundPlayer: sound, child: const Text('shell')),
      ),
    );
    await tester.pump(); // first frame after didChangeDependencies starts the controller.

    // Boot visuals are up: the logo wordmark is showing, and the shell is
    // already mounted underneath (just covered by the boot layer).
    expect(find.text('shell'), findsOneWidget);
    expect(find.text('Borg'), findsOneWidget);

    // Fast-forward past the boot budget (referenced, not duplicated — the
    // timing has been retuned twice): the whole boot layer unmounts,
    // leaving only the child — nothing lingers.
    await tester.pump(BootOverlay.totalDuration + const Duration(milliseconds: 150));
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

  testWidgets('plays the boot sound exactly when the animation actually starts', (tester) async {
    final sound = _FakeBootSound();
    await tester.pumpWidget(
      MaterialApp(
        home: BootOverlay(soundPlayer: sound, child: const Text('shell')),
      ),
    );
    await tester.pump();
    expect(sound.playCount, 1);

    await tester.pump(BootOverlay.totalDuration + const Duration(milliseconds: 150));
    expect(sound.disposeCount, 0); // still mounted (only the overlay layer unmounted itself).

    await tester.pumpWidget(const SizedBox()); // unmount the whole widget.
    expect(sound.disposeCount, 1); // disposed along with the widget's State.
  });

  testWidgets('no sound at all on the enabled:false skip path', (tester) async {
    final sound = _FakeBootSound();
    await tester.pumpWidget(
      MaterialApp(
        home: BootOverlay(enabled: false, soundPlayer: sound, child: const Text('shell')),
      ),
    );
    expect(sound.playCount, 0);

    await tester.pumpWidget(const SizedBox()); // unmount to trigger dispose().
    expect(sound.disposeCount, 0); // never constructed/used, nothing to dispose.
  });

  testWidgets('no sound at all on the reduced-motion skip path', (tester) async {
    final sound = _FakeBootSound();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: BootOverlay(soundPlayer: sound, child: const Text('shell')),
        ),
      ),
    );
    expect(sound.playCount, 0);
  });
}
