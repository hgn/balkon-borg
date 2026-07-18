import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/contract/stations.dart';

void main() {
  group('Stations', () {
    test('each band default is its first entry', () {
      expect(Stations.defaultFor('dab'), Stations.dab.first.id);
      expect(Stations.defaultFor('fm'), Stations.fm.first.id);
      expect(Stations.defaultFor('airband'), Stations.airband.first.id);
      expect(Stations.defaultFor('shortwave'), isNull);
    });

    test('DAB+ stations have no frequency', () {
      for (final s in Stations.dab) {
        expect(s.freq, isNull, reason: '${s.id} should have no frequency');
      }
    });

    test('FM and airband stations have a frequency', () {
      for (final s in [...Stations.fm, ...Stations.airband]) {
        expect(s.freq, isNotNull, reason: '${s.id} should have a frequency');
      }
    });

    test('ids are unique across all bands', () {
      final ids = [
        for (final s in [...Stations.dab, ...Stations.fm, ...Stations.airband]) s.id,
      ];
      expect(ids.toSet().length, ids.length);
    });

    test('byId resolves a known station and misses an unknown one', () {
      expect(Stations.byId('deutschlandfunk')?.name, 'Deutschlandfunk');
      expect(Stations.byId('bayern-3')?.freq, '97.3');
      expect(Stations.byId('nonexistent'), isNull);
    });
  });
}
