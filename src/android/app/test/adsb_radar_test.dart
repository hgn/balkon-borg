import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:balkon_borg/src/models/aircraft.dart';
import 'package:balkon_borg/src/services/haptics.dart';
import 'package:balkon_borg/src/services/ui_sounds.dart';
import 'package:balkon_borg/src/theme/balkon_theme.dart';
import 'package:balkon_borg/src/ui/widgets/adsb_radar.dart';

/// Records calls instead of hitting the real platform channels (mirrors
/// `app_state_test.dart`'s recording fakes).
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

Widget _wrap(
  Widget child, {
  Haptics? haptics,
  UiSounds? uiSounds,
  bool disableAnimations = false,
}) =>
    MultiProvider(
      providers: [
        Provider<Haptics>.value(value: haptics ?? const NoopHaptics()),
        Provider<UiSounds>.value(value: uiSounds ?? const NoopUiSounds()),
      ],
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: buildBalkonTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 300, height: 300, child: child),
            ),
          ),
        ),
      ),
    );

const _dlh = Aircraft(
  hex: '3c6a1f',
  flight: 'DLH1AB',
  altFt: 8000,
  trackDeg: 190,
  groundSpeedKt: 220,
  distKm: 30,
  bearingDeg: 10,
);

const _ryr = Aircraft(
  hex: '3c8e77',
  flight: 'RYR2CD',
  altFt: 5000,
  trackDeg: 90,
  groundSpeedKt: 200,
  distKm: 10,
  bearingDeg: 200,
);

void main() {
  group('RadarGeometry', () {
    test('forSize centers on the given size and shrinks the radius by edgePadding', () {
      final g = RadarGeometry.forSize(const Size(300, 300), edgePadding: 26);
      expect(g.center, const Offset(150, 150));
      expect(g.radius, 124);
    });

    test('north/east/south/west bearings land in the expected screen quadrant', () {
      final g = RadarGeometry.forSize(const Size(300, 300));
      const maxRangeKm = 50.0;

      final north = g.blipOffset(bearingDeg: 0, distanceKm: 25, maxRangeKm: maxRangeKm);
      final east = g.blipOffset(bearingDeg: 90, distanceKm: 25, maxRangeKm: maxRangeKm);
      final south = g.blipOffset(bearingDeg: 180, distanceKm: 25, maxRangeKm: maxRangeKm);
      final west = g.blipOffset(bearingDeg: 270, distanceKm: 25, maxRangeKm: maxRangeKm);

      expect(north.offset.dx, closeTo(g.center.dx, 0.5));
      expect(north.offset.dy, lessThan(g.center.dy)); // north = up = smaller y.
      expect(east.offset.dx, greaterThan(g.center.dx));
      expect(east.offset.dy, closeTo(g.center.dy, 0.5));
      expect(south.offset.dx, closeTo(g.center.dx, 0.5));
      expect(south.offset.dy, greaterThan(g.center.dy));
      expect(west.offset.dx, lessThan(g.center.dx));
      expect(west.offset.dy, closeTo(g.center.dy, 0.5));

      for (final p in [north, east, south, west]) {
        expect(p.clamped, isFalse);
        expect((p.offset - g.center).distance, closeTo(g.radius * 0.5, 0.5));
      }
    });

    test('distance beyond maxRangeKm clamps just inside the outer ring', () {
      final g = RadarGeometry.forSize(const Size(300, 300));
      final placement = g.blipOffset(bearingDeg: 45, distanceKm: 500, maxRangeKm: 50);

      expect(placement.clamped, isTrue);
      expect((placement.offset - g.center).distance, closeTo(g.radius * 0.94, 0.5));
      expect((placement.offset - g.center).distance, lessThan(g.radius));
    });

    test('distance exactly at maxRangeKm is not clamped', () {
      final g = RadarGeometry.forSize(const Size(300, 300));
      final placement = g.blipOffset(bearingDeg: 45, distanceKm: 50, maxRangeKm: 50);

      expect(placement.clamped, isFalse);
      expect((placement.offset - g.center).distance, closeTo(g.radius, 0.5));
    });

    test('zero distance places the blip at the center', () {
      final g = RadarGeometry.forSize(const Size(300, 300));
      final placement = g.blipOffset(bearingDeg: 123, distanceKm: 0, maxRangeKm: 50);
      expect((placement.offset - g.center).distance, closeTo(0, 0.5));
    });
  });

  group('blipPersistence', () {
    test('peaks at 1.0 the instant the sweep passes the blip', () {
      expect(blipPersistence(bearingDeg: 90, sweepDeg: 90), closeTo(1.0, 1e-9));
    });

    test('decays to roughly the midpoint halfway through the revolution', () {
      final v = blipPersistence(bearingDeg: 0, sweepDeg: 180, minBrightness: 0.0);
      expect(v, closeTo(0.5, 1e-9));
    });

    test('floors at minBrightness just before the sweep comes back around', () {
      final v = blipPersistence(bearingDeg: 10, sweepDeg: 9.999, minBrightness: 0.15);
      expect(v, closeTo(0.15, 0.01));
    });

    test('wraps correctly across the 0/360 boundary', () {
      final a = blipPersistence(bearingDeg: 350, sweepDeg: 10, minBrightness: 0.0);
      final b = blipPersistence(bearingDeg: 10, sweepDeg: 30, minBrightness: 0.0);
      expect(a, closeTo(b, 1e-9)); // both "20° past the beam" in wrap-around terms.
    });
  });

  group('AdsbRadar widget', () {
    testWidgets('empty sky shows the placeholder line and no callout', (tester) async {
      await tester.pumpWidget(_wrap(const AdsbRadar(aircraft: [])));
      await tester.pump();

      expect(find.text('keine Flugzeuge in Reichweite'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('populated sky labels the nearest aircraft by default', (tester) async {
      await tester.pumpWidget(_wrap(const AdsbRadar(aircraft: [_dlh, _ryr])));
      await tester.pump();

      expect(find.text('keine Flugzeuge in Reichweite'), findsNothing);
      expect(find.text('RYR2CD'), findsOneWidget); // nearer (10km vs 30km).
      expect(find.textContaining('10.0 km'), findsOneWidget);
      expect(find.text('DLH1AB'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping a blip moves the label there and fires selection feedback', (tester) async {
      final haptics = _RecordingHaptics();
      final uiSounds = _RecordingUiSounds();
      await tester.pumpWidget(
        _wrap(const AdsbRadar(aircraft: [_dlh, _ryr]), haptics: haptics, uiSounds: uiSounds),
      );
      await tester.pump();

      // Default label is the nearest (RYR2CD); tap DLH1AB's blip instead.
      final topLeft = tester.getTopLeft(find.byType(AdsbRadar));
      final geometry = RadarGeometry.forSize(const Size(300, 300));
      final placement =
          geometry.blipOffset(bearingDeg: _dlh.bearingDeg!, distanceKm: _dlh.distKm!, maxRangeKm: 50);

      await tester.tapAt(topLeft + placement.offset);
      await tester.pump();

      expect(find.text('DLH1AB'), findsOneWidget);
      expect(find.text('RYR2CD'), findsNothing);
      expect(haptics.calls, ['selectionClick']);
      expect(uiSounds.calls, ['blip']);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tap far from any blip is ignored', (tester) async {
      final haptics = _RecordingHaptics();
      await tester.pumpWidget(_wrap(const AdsbRadar(aircraft: [_dlh, _ryr]), haptics: haptics));
      await tester.pump();

      final topLeft = tester.getTopLeft(find.byType(AdsbRadar));
      await tester.tapAt(topLeft + const Offset(2, 2)); // corner, far from center traffic.
      await tester.pump();

      expect(find.text('RYR2CD'), findsOneWidget); // selection unchanged (still nearest).
      expect(haptics.calls, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('disableAnimations renders a static frame without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const AdsbRadar(aircraft: [_dlh, _ryr]), disableAnimations: true));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('RYR2CD'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  test('bearingToCanvasAngle: north points straight up in canvas terms', () {
    final angle = RadarGeometry.bearingToCanvasAngle(0);
    expect(math.cos(angle), closeTo(0, 1e-9));
    expect(math.sin(angle), closeTo(-1, 1e-9)); // canvas +y is down, so "up" is negative sin.
  });
}
