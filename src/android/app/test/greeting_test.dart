import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/services/greeting.dart';

/// Renders a `{n}`-templated greeting the same way `GreetingEngine` does,
/// so tests can build expected-output sets from the (deliberately
/// duplicated, spec-literal) template pools below without reaching into
/// the library's private classes.
String _render(String template, [String? name]) =>
    template.replaceFirst('{n}', name == null ? '' : ', $name');

const _morningTemplates = [
  'Guten Morgen{n}.',
  'Erst Kaffee, dann Kollektiv.',
  'Systeme hochgefahren{n}.',
  'Der Balkon wartet schon.',
];

const _dayTemplates = [
  'Guten Tag{n}.',
  'Alle Systeme nominal.',
  'Servus beinand.',
  'Beste Zeit für frische Luft.',
];

const _eveningTemplates = [
  'Guten Abend{n}.',
  'Der Abend gehört dem Balkon.',
  'Zeit für die Terrasse{n}.',
  'Feierabend{n}?',
];

const _nightTemplates = [
  'Hallo, Nachteule.',
  'Noch wach{n}?',
  'Regenerationszyklus empfohlen.',
  'Die Vögel schlafen schon.',
];

const _genericTemplates = [
  'Wieder im Kollektiv.',
  "Was gibt's Neues{n}?",
  "Wie läuft's{n}?",
  'Zurück am Balkon{n}?',
];

const _mondayText = 'Montag. Widerstand ist zwecklos.';
const _fridayTemplates = ['Endlich Freitag{n}.', 'Das Freitagsgefühl.'];
const _saturdayTemplates = ['Schönen Samstag{n}.', 'Willkommen im Wochenende{n}.'];
const _sundayTemplates = ['Sonntags-Session{n}?', 'Schönen Sonntag{n}.'];

Set<String> _rendered(List<String> templates, [String? name]) =>
    {for (final t in templates) _render(t, name)};

/// A stub `Random` whose `nextInt` always returns [value] — used to force
/// `GreetingEngine`'s single weighted draw (`_random.nextInt(total)`) to a
/// known cumulative-weight slot, so a specific pool template comes out
/// deterministically instead of depending on real randomness.
class _FixedRandom implements Random {
  const _FixedRandom(this.value);
  final int value;

  @override
  int nextInt(int max) => value;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}

// Reference dates (2026): Mon 07-13, Tue 07-14, Fri 07-17, Sat 07-18, Sun 07-19.
DateTime _mon(int h, int m) => DateTime(2026, 7, 13, h, m);
DateTime _tue(int h, int m) => DateTime(2026, 7, 14, h, m);
DateTime _fri(int h, int m) => DateTime(2026, 7, 17, h, m);
DateTime _sat(int h, int m) => DateTime(2026, 7, 18, h, m);
DateTime _sun(int h, int m) => DateTime(2026, 7, 19, h, m);

void main() {
  group('time bucketing', () {
    // Property check: draw with several different real (unseeded) rolls on
    // a weekday with no specials (Tuesday) and confirm every draw lands in
    // the expected pool ∪ generic, never in a neighboring bucket's pool.
    void expectBucket(
      String label,
      DateTime now,
      List<String> ownTemplates,
      List<List<String>> otherPools,
    ) {
      test(label, () {
        final own = _rendered(ownTemplates)..addAll(_rendered(_genericTemplates));
        final forbidden = <String>{for (final p in otherPools) ..._rendered(p)};

        for (var seed = 0; seed < 20; seed++) {
          final engine = GreetingEngine(now: now, random: Random(seed));
          final result = engine.greet();
          expect(own, contains(result), reason: 'seed $seed -> "$result"');
          expect(forbidden, isNot(contains(result)), reason: 'seed $seed -> "$result"');
        }
      });
    }

    expectBucket('4:59 is still night', _tue(4, 59), _nightTemplates,
        [_morningTemplates, _dayTemplates, _eveningTemplates]);
    expectBucket('5:00 rolls into morning', _tue(5, 0), _morningTemplates,
        [_nightTemplates, _dayTemplates, _eveningTemplates]);
    expectBucket('10:59 is still morning', _tue(10, 59), _morningTemplates,
        [_nightTemplates, _dayTemplates, _eveningTemplates]);
    expectBucket('11:00 rolls into day', _tue(11, 0), _dayTemplates,
        [_nightTemplates, _morningTemplates, _eveningTemplates]);
    expectBucket('17:59 is still day', _tue(17, 59), _dayTemplates,
        [_nightTemplates, _morningTemplates, _eveningTemplates]);
    expectBucket('18:00 rolls into evening', _tue(18, 0), _eveningTemplates,
        [_nightTemplates, _morningTemplates, _dayTemplates]);
    expectBucket('20:29 is still evening', _tue(20, 29), _eveningTemplates,
        [_nightTemplates, _morningTemplates, _dayTemplates]);
    expectBucket('20:30 rolls into night', _tue(20, 30), _nightTemplates,
        [_morningTemplates, _dayTemplates, _eveningTemplates]);
  });

  group('name insertion', () {
    test('"…{n}." form: with and without a name', () {
      // roll 0 -> first candidate in the weighted list for a non-night
      // bucket with no weekday special is always the time pool's first
      // entry: morningTemplates[0].
      final withName =
          GreetingEngine(now: _tue(8, 0), random: const _FixedRandom(0)).greet(name: 'Hagen');
      final withoutName =
          GreetingEngine(now: _tue(8, 0), random: const _FixedRandom(0)).greet();

      expect(withoutName, 'Guten Morgen.');
      expect(withName, 'Guten Morgen, Hagen.');
    });

    test('"…{n}?" form: with and without a name', () {
      // Night bucket candidate order: night pool (4 templates, weight 3
      // each) then generic (weight 1 each) — roll 3 lands on the second
      // night template, nightTemplates[1] == 'Noch wach{n}?'.
      final engineNoName = GreetingEngine(now: _tue(21, 0), random: const _FixedRandom(3));
      final engineWithName = GreetingEngine(now: _tue(21, 0), random: const _FixedRandom(3));

      expect(engineNoName.greet(), 'Noch wach?');
      expect(engineWithName.greet(name: 'Hagen'), 'Noch wach, Hagen?');
    });

    test('an empty or whitespace-only name renders as absent', () {
      final engine = GreetingEngine(now: _tue(8, 0), random: const _FixedRandom(0));
      expect(engine.greet(name: '   '), 'Guten Morgen.');
    });
  });

  group('weekday specials', () {
    test('Monday special is reachable only on Monday', () {
      // Day-pool candidate order: day pool (4 × weight 3, rolls 0-11),
      // then the Monday special (weight 2, rolls 12-13), then generic.
      final onMonday = GreetingEngine(now: _mon(12, 0), random: const _FixedRandom(12)).greet();
      expect(onMonday, _mondayText);

      // Same roll on a non-special weekday (Tuesday has no special pool
      // inserted, so the candidate list is shorter) never yields it, and
      // no roll across the full range does either.
      for (var roll = 0; roll < 16; roll++) {
        final onTuesday = GreetingEngine(now: _tue(12, 0), random: _FixedRandom(roll)).greet();
        expect(onTuesday, isNot(_mondayText));
      }
    });

    test('Friday specials only appear on Friday', () {
      final fridayOutcomes = <String>{};
      for (var roll = 0; roll < 18; roll++) {
        fridayOutcomes.add(GreetingEngine(now: _fri(12, 0), random: _FixedRandom(roll)).greet());
      }
      expect(fridayOutcomes, containsAll(_rendered(_fridayTemplates)));

      for (var roll = 0; roll < 16; roll++) {
        final onMonday = GreetingEngine(now: _mon(12, 0), random: _FixedRandom(roll)).greet();
        expect(_rendered(_fridayTemplates), isNot(contains(onMonday)));
      }
    });

    test('weekend specials (Sat/Sun) only appear on their own day', () {
      final saturdayOutcomes = <String>{};
      for (var roll = 0; roll < 18; roll++) {
        saturdayOutcomes.add(GreetingEngine(now: _sat(12, 0), random: _FixedRandom(roll)).greet());
      }
      expect(saturdayOutcomes, containsAll(_rendered(_saturdayTemplates)));
      expect(saturdayOutcomes.intersection(_rendered(_sundayTemplates)), isEmpty);

      final sundayOutcomes = <String>{};
      for (var roll = 0; roll < 18; roll++) {
        sundayOutcomes.add(GreetingEngine(now: _sun(12, 0), random: _FixedRandom(roll)).greet());
      }
      expect(sundayOutcomes, containsAll(_rendered(_sundayTemplates)));
      expect(sundayOutcomes.intersection(_rendered(_saturdayTemplates)), isEmpty);
    });

    test('night hours never draw a weekday special, even on Monday', () {
      for (var roll = 0; roll < 16; roll++) {
        final result = GreetingEngine(now: _mon(21, 0), random: _FixedRandom(roll)).greet();
        expect(result, isNot(_mondayText));
      }
    });
  });

  group('deterministic draw', () {
    test('the same engine returns the same greeting on repeated calls (memoized)', () {
      // roll 0 -> morningTemplates[0] ('Guten Morgen{n}.', see the name-
      // insertion group above), so a name given only on the later call
      // still proves the *template* didn't get re-rolled in between.
      final engine = GreetingEngine(now: _tue(8, 0), random: const _FixedRandom(0));
      final first = engine.greet();
      final second = engine.greet();
      final third = engine.greet(name: 'Hagen');

      expect(second, first);
      expect(third, isNot(first)); // name insertion changed the rendering...
      expect(third.replaceAll(', Hagen', ''), first); // ...but the underlying template didn't.
    });

    test('two engines with the same seed and time draw the same template', () {
      final a = GreetingEngine(now: _tue(9, 0), random: Random(1234));
      final b = GreetingEngine(now: _tue(9, 0), random: Random(1234));

      expect(a.greet(), b.greet());
    });
  });
}
