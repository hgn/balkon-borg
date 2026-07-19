/// One aircraft of the retained `balkon/adsb/aircraft` sky snapshot
/// (`src/shared/README.md`, `contract/topics.dart`'s `Topics.adsbAircraft`).
/// The arbiter computes `dist_km`/`bearing_deg` relative to the balcony; a
/// client that gets neither (or only one) falls back to its own
/// [GreatCircle] math on `lat`/`lon`, per the contract.
library;

import 'dart:math' as math;

import '../contract/topics.dart';

/// Great-circle helpers on a spherical-Earth approximation (mean radius),
/// plenty accurate for a balcony-scale radar picture.
abstract final class GreatCircle {
  static const _earthRadiusKm = 6371.0;

  static double _deg2rad(double deg) => deg * math.pi / 180;
  static double _rad2deg(double rad) => rad * 180 / math.pi;

  /// Haversine distance between two lat/lon points, in km.
  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _deg2rad(lat1);
    final phi2 = _deg2rad(lat2);
    final dPhi = _deg2rad(lat2 - lat1);
    final dLambda = _deg2rad(lon2 - lon1);
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  /// Initial bearing (0..360, 0 = north, clockwise) from point 1 to point 2.
  static double bearingDeg(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = _deg2rad(lat1);
    final phi2 = _deg2rad(lat2);
    final dLambda = _deg2rad(lon2 - lon1);
    final y = math.sin(dLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
    return (_rad2deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Destination point [distanceKm] out from (lat, lon) along [bearingDeg].
  /// Used by `DemoSource` to advance simulated tracks.
  static ({double lat, double lon}) destination(
    double lat,
    double lon,
    double bearingDeg,
    double distanceKm,
  ) {
    final delta = distanceKm / _earthRadiusKm;
    final theta = _deg2rad(bearingDeg);
    final phi1 = _deg2rad(lat);
    final lambda1 = _deg2rad(lon);

    final phi2 = math.asin(
      math.sin(phi1) * math.cos(delta) + math.cos(phi1) * math.sin(delta) * math.cos(theta),
    );
    final lambda2 = lambda1 +
        math.atan2(
          math.sin(theta) * math.sin(delta) * math.cos(phi1),
          math.cos(delta) - math.sin(phi1) * math.sin(phi2),
        );
    return (lat: _rad2deg(phi2), lon: _rad2deg(lambda2));
  }
}

class Aircraft {
  const Aircraft({
    required this.hex,
    this.flight,
    this.lat,
    this.lon,
    this.altFt,
    this.trackDeg,
    this.groundSpeedKt,
    this.distKm,
    this.bearingDeg,
  });

  final String hex;
  final String? flight;
  final double? lat;
  final double? lon;
  final double? altFt;
  final double? trackDeg;
  final double? groundSpeedKt;
  final double? distKm;
  final double? bearingDeg;

  /// True if this aircraft can be placed on the radar (bearing + distance
  /// known, either from the payload or the [GreatCircle] fallback below).
  bool get isPlaceable => distKm != null && bearingDeg != null;

  factory Aircraft.fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    var distKm = (json['dist_km'] as num?)?.toDouble();
    var bearingDeg = (json['bearing_deg'] as num?)?.toDouble();
    if ((distKm == null || bearingDeg == null) && lat != null && lon != null) {
      distKm ??= GreatCircle.distanceKm(BorgGeo.homeLat, BorgGeo.homeLon, lat, lon);
      bearingDeg ??= GreatCircle.bearingDeg(BorgGeo.homeLat, BorgGeo.homeLon, lat, lon);
    }
    return Aircraft(
      hex: json['hex'] as String? ?? '',
      flight: (json['flight'] as String?)?.trim().isEmpty ?? true ? null : (json['flight'] as String).trim(),
      lat: lat,
      lon: lon,
      altFt: (json['alt_ft'] as num?)?.toDouble(),
      trackDeg: (json['track'] as num?)?.toDouble(),
      groundSpeedKt: (json['gs'] as num?)?.toDouble(),
      distKm: distKm,
      bearingDeg: bearingDeg,
    );
  }

  Aircraft copyWith({
    double? lat,
    double? lon,
    double? distKm,
    double? bearingDeg,
  }) =>
      Aircraft(
        hex: hex,
        flight: flight,
        lat: lat ?? this.lat,
        lon: lon ?? this.lon,
        altFt: altFt,
        trackDeg: trackDeg,
        groundSpeedKt: groundSpeedKt,
        distKm: distKm ?? this.distKm,
        bearingDeg: bearingDeg ?? this.bearingDeg,
      );
}

/// The `{"v":1,"ts":…,"aircraft":[…]}` envelope on `Topics.adsbAircraft`.
/// An empty sky is an empty `aircraft` list per the contract, not a missing
/// message — [fromJson] reflects that: a missing/malformed `aircraft` field
/// still yields an empty list rather than throwing.
class SkySnapshot {
  const SkySnapshot({required this.ts, required this.aircraft});

  factory SkySnapshot.fromJson(Map<String, dynamic> json) {
    final list = json['aircraft'];
    return SkySnapshot(
      ts: _parseTs(json['ts']),
      aircraft: [
        for (final e in (list is List ? list : const []))
          if (e is Map<String, dynamic>) Aircraft.fromJson(e),
      ],
    );
  }

  final DateTime ts;
  final List<Aircraft> aircraft;

  static DateTime _parseTs(Object? raw) {
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    if (raw is num) {
      final ms = raw < 1000000000000 ? (raw * 1000).round() : raw.round();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
