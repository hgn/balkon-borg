import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/models/bird_detection.dart';

void main() {
  group('BirdDetection.fromJson', () {
    test('parses PascalCase fields with an ISO timestamp', () {
      final d = BirdDetection.fromJson(const {
        'CommonName': 'Amsel',
        'ScientificName': 'Turdus merula',
        'Confidence': 0.92,
        'Time': '2026-07-16T19:42:00+02:00',
      });
      expect(d.species, 'Amsel');
      expect(d.scientific, 'Turdus merula');
      expect(d.confidence, 0.92);
      expect(d.ts, DateTime.parse('2026-07-16T19:42:00+02:00'));
    });

    test('parses snake_case/camelCase fields with an epoch-seconds timestamp', () {
      final epochSeconds = DateTime.utc(2026, 7, 16, 12).millisecondsSinceEpoch ~/ 1000;
      final d = BirdDetection.fromJson({
        'commonName': 'Kohlmeise',
        'scientificName': 'Parus major',
        'confidence': 0.77,
        'ts': epochSeconds,
      });
      expect(d.species, 'Kohlmeise');
      expect(d.scientific, 'Parus major');
      expect(d.confidence, 0.77);
      expect(d.ts, DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000));
    });

    test('normalizes a 0..100-style confidence to 0..1', () {
      final d = BirdDetection.fromJson(const {'species': 'Elster', 'confidence': 87});
      expect(d.confidence, closeTo(0.87, 1e-9));
    });

    test('tolerates a completely empty payload', () {
      final d = BirdDetection.fromJson(const {});
      expect(d.species, '');
      expect(d.scientific, isNull);
      expect(d.confidence, isNull);
      expect(d.ts, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  group('BirdOfDay.fromLog', () {
    test('picks the species with the most detections today, ignoring yesterday', () {
      final now = DateTime(2026, 7, 16, 20);
      final log = [
        BirdDetection(ts: now.subtract(const Duration(hours: 1)), species: 'Amsel'),
        BirdDetection(ts: now.subtract(const Duration(hours: 2)), species: 'Amsel'),
        BirdDetection(ts: now.subtract(const Duration(hours: 3)), species: 'Amsel'),
        BirdDetection(ts: now.subtract(const Duration(hours: 4)), species: 'Kohlmeise'),
        BirdDetection(ts: now.subtract(const Duration(hours: 5)), species: 'Kohlmeise'),
        // Yesterday: a species that would otherwise win must be excluded.
        BirdDetection(ts: now.subtract(const Duration(days: 1, hours: 1)), species: 'Elster'),
        BirdDetection(ts: now.subtract(const Duration(days: 1, hours: 2)), species: 'Elster'),
        BirdDetection(ts: now.subtract(const Duration(days: 1, hours: 3)), species: 'Elster'),
        BirdDetection(ts: now.subtract(const Duration(days: 1, hours: 4)), species: 'Elster'),
      ];

      final result = BirdOfDay.fromLog(log, now: now);
      expect(result, isNotNull);
      expect(result!.species, 'Amsel');
      expect(result.count, 3);
      expect(result.lastSeen, now.subtract(const Duration(hours: 1)));
    });

    test('returns null when nothing was detected today', () {
      final now = DateTime(2026, 7, 16, 20);
      final log = [
        BirdDetection(ts: now.subtract(const Duration(days: 1)), species: 'Amsel'),
      ];
      expect(BirdOfDay.fromLog(log, now: now), isNull);
    });
  });
}
