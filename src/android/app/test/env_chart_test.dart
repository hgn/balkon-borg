import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/widgets/env_chart.dart';

/// Records calls instead of hitting the real `HapticFeedback` platform
/// channel (same style as `_RecordingHaptics` in app_state_test.dart).
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

List<EnvChartPoint> _points(int count) => [
      for (var i = 0; i < count; i++) (ts: DateTime(2026, 7, 19, 0, i * 10), value: i.toDouble()),
    ];

Widget _wrap(Widget child, Haptics haptics) => MultiProvider(
      providers: [Provider<Haptics>.value(value: haptics)],
      child: MaterialApp(
        theme: buildBalkonTheme(brightness: Brightness.dark),
        home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
      ),
    );

void main() {
  group('nearestSampleIndex', () {
    test('left edge maps to the first index', () {
      expect(nearestSampleIndex(dx: 0, width: 300, length: 10), 0);
    });

    test('right edge maps to the last index', () {
      expect(nearestSampleIndex(dx: 300, width: 300, length: 10), 9);
    });

    test('middle offset maps to the middle index', () {
      expect(nearestSampleIndex(dx: 150, width: 300, length: 5), 2);
    });

    test('a single-sample history always selects index 0', () {
      expect(nearestSampleIndex(dx: 0, width: 300, length: 1), 0);
      expect(nearestSampleIndex(dx: 150, width: 300, length: 1), 0);
      expect(nearestSampleIndex(dx: 300, width: 300, length: 1), 0);
    });

    test('an empty history selects nothing', () {
      expect(nearestSampleIndex(dx: 150, width: 300, length: 0), isNull);
    });
  });

  group('EnvChart scrubbing', () {
    testWidgets('a horizontal drag selects a sample and reports it', (tester) async {
      final haptics = _RecordingHaptics();
      EnvChartPoint? selected;
      final points = _points(10);

      await tester.pumpWidget(
        _wrap(EnvChart(points: points, onSelectionChanged: (p) => selected = p), haptics),
      );

      final rect = tester.getRect(find.byType(EnvChart));
      final gesture = await tester.startGesture(rect.centerLeft);
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();

      expect(selected, isNotNull);
      expect(haptics.calls, isNotEmpty);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('selectionClick fires once per distinct sample, not per pointer move', (
      tester,
    ) async {
      final haptics = _RecordingHaptics();
      final points = _points(10); // even spacing over 300px ⇒ ~33.3px per sample.

      await tester.pumpWidget(_wrap(EnvChart(points: points), haptics));

      final rect = tester.getRect(find.byType(EnvChart));
      final gesture = await tester.startGesture(rect.centerLeft);

      // Several small moves that stay within the first sample's bucket must
      // add exactly one haptic call (the initial selection), not one per move.
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump();
      }
      expect(haptics.calls.length, 1);

      // Crossing into the next bucket adds exactly one more.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(haptics.calls.length, 2);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('releasing the drag restores no selection', (tester) async {
      final haptics = _RecordingHaptics();
      EnvChartPoint? selected;
      final points = _points(10);

      await tester.pumpWidget(
        _wrap(EnvChart(points: points, onSelectionChanged: (p) => selected = p), haptics),
      );

      final rect = tester.getRect(find.byType(EnvChart));
      final gesture = await tester.startGesture(rect.centerLeft);
      await gesture.moveBy(const Offset(50, 0));
      await tester.pump();
      expect(selected, isNotNull);

      await gesture.up();
      await tester.pump();
      expect(selected, isNull);
    });

    testWidgets(
      'a vertical drag falls through to an ancestor vertical recognizer, not the chart',
      (tester) async {
        // Mirrors the real chart sheet, which is itself vertically draggable
        // (drag-to-dismiss/resize) — an ancestor GestureDetector with its own
        // vertical drag recognizer competes in the same gesture arena as the
        // chart's HorizontalDragGestureRecognizer.
        final haptics = _RecordingHaptics();
        EnvChartPoint? selected;
        var outerVerticalDragUpdates = 0;
        final points = _points(10);

        await tester.pumpWidget(
          _wrap(
            GestureDetector(
              onVerticalDragUpdate: (_) => outerVerticalDragUpdates++,
              child: EnvChart(points: points, onSelectionChanged: (p) => selected = p),
            ),
            haptics,
          ),
        );

        final rect = tester.getRect(find.byType(EnvChart));
        await tester.dragFrom(rect.center, const Offset(0, 50));
        await tester.pump();

        expect(outerVerticalDragUpdates, greaterThan(0));
        expect(selected, isNull);
        expect(haptics.calls, isEmpty);
      },
    );
  });
}
