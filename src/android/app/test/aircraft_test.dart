import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/contract/topics.dart';
import 'package:balkon_borg/src/models/aircraft.dart';

void main() {
  group('GreatCircle', () {
    test('distanceKm is ~0 for the same point', () {
      expect(GreatCircle.distanceKm(48.1372, 11.5000, 48.1372, 11.5000), closeTo(0, 1e-6));
    });

    test('destination() round-trips distance and bearing back to the origin', () {
      // Fly 20km due east (90°) from Munich Laim, then check the reverse
      // distance/bearing from home matches.
      final dest = GreatCircle.destination(BorgGeo.homeLat, BorgGeo.homeLon, 90, 20);
      final backDist = GreatCircle.distanceKm(BorgGeo.homeLat, BorgGeo.homeLon, dest.lat, dest.lon);
      final backBearing = GreatCircle.bearingDeg(BorgGeo.homeLat, BorgGeo.homeLon, dest.lat, dest.lon);
      expect(backDist, closeTo(20, 0.05));
      expect(backBearing, closeTo(90, 0.5));
    });

    test('bearingDeg: north/east/south/west sanity', () {
      const lat = 48.1372, lon = 11.5000;
      // ~1km steps in each cardinal direction.
      final north = GreatCircle.destination(lat, lon, 0, 1);
      final east = GreatCircle.destination(lat, lon, 90, 1);
      final south = GreatCircle.destination(lat, lon, 180, 1);
      final west = GreatCircle.destination(lat, lon, 270, 1);

      expect(GreatCircle.bearingDeg(lat, lon, north.lat, north.lon), closeTo(0, 0.5));
      expect(GreatCircle.bearingDeg(lat, lon, east.lat, east.lon), closeTo(90, 0.5));
      expect(GreatCircle.bearingDeg(lat, lon, south.lat, south.lon), closeTo(180, 0.5));
      expect(GreatCircle.bearingDeg(lat, lon, west.lat, west.lon), closeTo(270, 0.5));
    });

    test('destination() stays sane over many steps (no drift blow-up)', () {
      var lat = BorgGeo.homeLat;
      var lon = BorgGeo.homeLon;
      for (var i = 0; i < 50; i++) {
        final d = GreatCircle.destination(lat, lon, 45, 2);
        lat = d.lat;
        lon = d.lon;
      }
      // 50 * 2km along a constant bearing from a fixed start is bounded.
      final dist = GreatCircle.distanceKm(BorgGeo.homeLat, BorgGeo.homeLon, lat, lon);
      expect(dist, lessThan(150));
      expect(dist, greaterThan(50));
      expect(lat.isFinite, isTrue);
      expect(lon.isFinite, isTrue);
    });
  });

  group('Aircraft.fromJson', () {
    test('parses a full payload as-is, no fallback math needed', () {
      final json = jsonDecode(
        '{"hex":"3c6a1f","flight":"DLH1AB","lat":48.2,"lon":11.6,"alt_ft":8000,'
        '"track":190,"gs":220,"dist_km":12.3,"bearing_deg":45}',
      ) as Map<String, dynamic>;
      final a = Aircraft.fromJson(json);

      expect(a.hex, '3c6a1f');
      expect(a.flight, 'DLH1AB');
      expect(a.altFt, 8000);
      expect(a.trackDeg, 190);
      expect(a.groundSpeedKt, 220);
      expect(a.distKm, 12.3);
      expect(a.bearingDeg, 45);
      expect(a.isPlaceable, isTrue);
    });

    test('every field but hex may be missing', () {
      final a = Aircraft.fromJson(const {'hex': '3c6a1f'});
      expect(a.hex, '3c6a1f');
      expect(a.flight, isNull);
      expect(a.lat, isNull);
      expect(a.lon, isNull);
      expect(a.altFt, isNull);
      expect(a.trackDeg, isNull);
      expect(a.groundSpeedKt, isNull);
      expect(a.distKm, isNull);
      expect(a.bearingDeg, isNull);
      expect(a.isPlaceable, isFalse);
    });

    test('missing hex falls back to an empty string rather than throwing', () {
      final a = Aircraft.fromJson(const {'flight': 'DLH1AB'});
      expect(a.hex, '');
      expect(a.flight, 'DLH1AB');
    });

    test('blank flight string is treated as absent', () {
      final a = Aircraft.fromJson(const {'hex': 'abc', 'flight': '   '});
      expect(a.flight, isNull);
    });

    test('falls back to great-circle math when dist_km/bearing_deg are absent but lat/lon are present', () {
      final dest = GreatCircle.destination(BorgGeo.homeLat, BorgGeo.homeLon, 120, 15);
      final json = {'hex': 'abc123', 'lat': dest.lat, 'lon': dest.lon};
      final a = Aircraft.fromJson(json);

      expect(a.distKm, closeTo(15, 0.05));
      expect(a.bearingDeg, closeTo(120, 0.5));
      expect(a.isPlaceable, isTrue);
    });

    test('an explicit dist_km/bearing_deg wins over the lat/lon fallback', () {
      final dest = GreatCircle.destination(BorgGeo.homeLat, BorgGeo.homeLon, 120, 15);
      final json = {
        'hex': 'abc123',
        'lat': dest.lat,
        'lon': dest.lon,
        'dist_km': 999.0,
        'bearing_deg': 1.0,
      };
      final a = Aircraft.fromJson(json);

      expect(a.distKm, 999.0);
      expect(a.bearingDeg, 1.0);
    });

    test('no lat/lon and no dist/bearing leaves the aircraft unplaceable', () {
      final a = Aircraft.fromJson(const {'hex': 'abc123', 'flight': 'RYR1AB'});
      expect(a.isPlaceable, isFalse);
    });
  });

  group('SkySnapshot.fromJson', () {
    test('parses the v1 envelope, nearest first order preserved', () {
      final json = jsonDecode(
        '{"v":1,"ts":"2026-07-19T21:00:00+02:00","aircraft":['
        '{"hex":"a"},{"hex":"b"}]}',
      ) as Map<String, dynamic>;
      final snap = SkySnapshot.fromJson(json);

      expect(snap.aircraft.map((a) => a.hex), ['a', 'b']);
      expect(snap.ts.year, 2026);
    });

    test('an empty sky is an empty list, not a missing message', () {
      final snap = SkySnapshot.fromJson(const {'v': 1, 'ts': '2026-07-19T21:00:00+02:00', 'aircraft': []});
      expect(snap.aircraft, isEmpty);
    });

    test('a missing/malformed aircraft field is tolerated as empty, not a crash', () {
      final snap = SkySnapshot.fromJson(const {'v': 1});
      expect(snap.aircraft, isEmpty);
    });

    test('malformed timestamp falls back to epoch instead of throwing', () {
      final snap = SkySnapshot.fromJson(const {'ts': 'not-a-date', 'aircraft': []});
      expect(snap.ts, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  test('a full 360° sweep of bearings maps back consistently (no branch cut surprises)', () {
    for (var bearing = 0.0; bearing < 360; bearing += 15) {
      final dest = GreatCircle.destination(BorgGeo.homeLat, BorgGeo.homeLon, bearing, 10);
      final back = GreatCircle.bearingDeg(BorgGeo.homeLat, BorgGeo.homeLon, dest.lat, dest.lon);
      final diff = ((back - bearing + 540) % 360 - 180).abs();
      expect(diff, lessThan(0.5), reason: 'bearing $bearing rad=${bearing * math.pi / 180}');
    }
  });
}
