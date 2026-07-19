import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/services/condensation_gate.dart';

void main() {
  group('CondensationGate', () {
    test('starts inactive', () {
      expect(CondensationGate().isActive, isFalse);
    });

    test('turns on at/above the on-threshold', () {
      final gate = CondensationGate();
      expect(gate.update(84.9), isFalse);
      expect(gate.update(85.0), isTrue);
      expect(gate.isActive, isTrue);
    });

    test('stays on through the hysteresis gap, only turns off below the off-threshold', () {
      final gate = CondensationGate();
      gate.update(90.0);
      expect(gate.isActive, isTrue);

      // Dips inside the gap (82..85) — must stay on, that's the whole point
      // of the hysteresis: a sensor hovering at the threshold must not
      // flicker the effect.
      expect(gate.update(83.5), isTrue);
      expect(gate.update(82.0), isTrue); // still not below.

      expect(gate.update(81.9), isFalse);
      expect(gate.isActive, isFalse);
    });

    test('missing data holds the current state either way', () {
      final gate = CondensationGate();
      expect(gate.update(null), isFalse);

      gate.update(90.0);
      expect(gate.update(null), isTrue);
    });

    test('does not turn on again until crossing the on-threshold once off', () {
      final gate = CondensationGate();
      gate.update(90.0);
      gate.update(80.0); // now off.

      expect(gate.update(83.0), isFalse); // inside the gap, still off.
      expect(gate.update(85.0), isTrue);
    });

    test('custom thresholds are respected', () {
      final gate = CondensationGate(onThreshold: 70.0, offThreshold: 65.0);
      expect(gate.update(70.0), isTrue);
      expect(gate.update(66.0), isTrue);
      expect(gate.update(64.9), isFalse);
    });
  });
}
