import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/contract/submodes.dart';
import 'package:balkon_borg/src/contract/topics.dart';

void main() {
  group('Submodes', () {
    test('every main mode has a list starting with an explicit "off"', () {
      for (final m in MainMode.values) {
        final list = Submodes.forMode(m);
        expect(list, isNotEmpty);
        expect(list.first.id, 'off');
      }
    });

    test('matches the mode table in docs/use-cases.md', () {
      expect(
        Submodes.lumen.map((s) => s.id),
        [
          'off',
          'ambient',
          'full',
          'cozy',
          'distance-auto',
          'info-ticker',
          'disco',
          'strobe',
          'police',
          'visualiser',
        ],
      );
      expect(Submodes.comms.map((s) => s.id), ['off', 'fm', 'dab', 'shortwave', 'airband']);
      expect(
        Submodes.sigint.map((s) => s.id),
        ['off', 'adsb', 'ism', 'aprs', 'radiosonde', 'spectrum', 'captures'],
      );
      expect(Submodes.sentry.map((s) => s.id), ['off', 'armed']);
    });

    test('labelFor() resolves known ids and falls back to the raw id', () {
      expect(Submodes.labelFor(MainMode.comms, 'dab'), 'DAB+');
      expect(Submodes.labelFor(MainMode.sentry, 'off'), 'Aus');
      expect(Submodes.labelFor(MainMode.lumen, 'not-a-real-submode'), 'not-a-real-submode');
    });
  });
}
