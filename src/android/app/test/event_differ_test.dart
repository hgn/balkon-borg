import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/models/borg_event.dart';
import 'package:balkon_borg/src/services/event_differ.dart';

void main() {
  const differ = EventDiffer();
  final now = DateTime(2026, 7, 17, 20, 0);

  BorgEvent at(Duration ago, EventCategory category, [String text = 'x']) =>
      BorgEvent(ts: now.subtract(ago), category: category, text: text);

  bool allEnabled(EventCategory _) => true;
  bool onlySecurity(EventCategory c) => c == EventCategory.security;

  group('diff — new-event detection by ts', () {
    test('events newer than lastSeen are included, older ones excluded', () {
      final ring = [
        at(const Duration(minutes: 1), EventCategory.bird), // newer
        at(const Duration(minutes: 5), EventCategory.bird), // == lastSeen boundary below, excluded
        at(const Duration(minutes: 10), EventCategory.bird), // older
      ];
      final lastSeen = now.subtract(const Duration(minutes: 5));

      final result = differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: allEnabled);

      expect(result, hasLength(1));
      expect(result.single.ts, ring[0].ts);
    });

    test('nothing newer than lastSeen yields no notifications', () {
      final ring = [at(const Duration(minutes: 10), EventCategory.bird)];
      final lastSeen = now.subtract(const Duration(minutes: 1));

      expect(differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: allEnabled), isEmpty);
    });
  });

  group('diff — category filtering', () {
    test('only enabled categories are notified', () {
      final ring = [
        at(const Duration(minutes: 1), EventCategory.security),
        at(const Duration(minutes: 2), EventCategory.bird),
        at(const Duration(minutes: 3), EventCategory.aircraft),
      ];
      final lastSeen = now.subtract(const Duration(minutes: 30));

      final result = differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: onlySecurity);

      expect(result, hasLength(1));
      expect(result.single.category, EventCategory.security);
    });

    test('disabling every category yields no notifications even with new events', () {
      final ring = [at(const Duration(minutes: 1), EventCategory.bird)];
      final lastSeen = now.subtract(const Duration(minutes: 30));

      expect(
        differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: (_) => false),
        isEmpty,
      );
    });
  });

  group('diff — empty ring', () {
    test('empty ring never notifies, first run or not', () {
      expect(differ.diff(ring: const [], lastSeen: null, isEnabled: allEnabled), isEmpty);
      expect(
        differ.diff(ring: const [], lastSeen: now, isEnabled: allEnabled),
        isEmpty,
      );
    });
  });

  group('diff — first run must not notification-bomb', () {
    test('a full ~20-entry ring caps at firstRunNotifyCap on first run', () {
      final ring = [for (var i = 0; i < 20; i++) at(Duration(minutes: i), EventCategory.bird)];

      final result = differ.diff(ring: ring, lastSeen: null, isEnabled: allEnabled);

      expect(result.length, EventDiffer.firstRunNotifyCap);
      // Keeps the newest entries (ring is newest-first) and their order.
      expect(result, equals(ring.take(EventDiffer.firstRunNotifyCap)));
    });

    test('first-run cap still respects the category filter', () {
      final ring = [
        for (var i = 0; i < 20; i++) at(Duration(minutes: i), EventCategory.aircraft),
      ];

      expect(differ.diff(ring: ring, lastSeen: null, isEnabled: onlySecurity), isEmpty);
    });
  });

  group('nextLastSeen', () {
    test('advances to the newest ring timestamp', () {
      final ring = [
        at(const Duration(minutes: 1), EventCategory.bird),
        at(const Duration(minutes: 5), EventCategory.bird),
      ];

      final next = differ.nextLastSeen(ring: ring, lastSeen: null);

      expect(next, ring[0].ts); // ring[0] is newest (least "ago").
    });

    test('never regresses past an existing lastSeen', () {
      final lastSeen = now; // newer than anything in the stale ring below.
      final ring = [at(const Duration(hours: 1), EventCategory.bird)];

      expect(differ.nextLastSeen(ring: ring, lastSeen: lastSeen), lastSeen);
    });

    test('empty ring leaves lastSeen unchanged', () {
      expect(differ.nextLastSeen(ring: const [], lastSeen: now), now);
      expect(differ.nextLastSeen(ring: const [], lastSeen: null), isNull);
    });

    test('advances even when the newest entry was filtered out of diff()', () {
      // A storm event arrives while "storm" notifications are off — diff()
      // returns nothing, but nextLastSeen must still move past it so
      // enabling "storm" later doesn't retroactively notify for it.
      final ring = [at(const Duration(minutes: 1), EventCategory.storm)];
      final lastSeen = now.subtract(const Duration(hours: 1));

      final notified = differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: onlySecurity);
      final next = differ.nextLastSeen(ring: ring, lastSeen: lastSeen);

      expect(notified, isEmpty);
      expect(next, ring[0].ts);
    });
  });
}
