import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/services/ui_sounds.dart';

/// A `Random` whose draws are scripted instead of pseudo-random, so tests can
/// force `PackageUiSounds` down a specific branch (e.g. the rare droid-babble
/// answer to a state echo) deterministically. Each list cycles if exhausted.
class _RiggedRandom implements Random {
  _RiggedRandom({this.doubles = const [], this.ints = const []});

  final List<double> doubles;
  final List<int> ints;
  int _di = 0;
  int _ii = 0;

  @override
  double nextDouble() => doubles[_di++ % doubles.length];

  @override
  int nextInt(int max) => ints[_ii++ % ints.length];

  @override
  bool nextBool() => false;
}

void main() {
  group('PackageUiSounds selection', () {
    test('blip() picks uniformly among the short clicks', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(
        () => true,
        random: _RiggedRandom(doubles: [0.5], ints: [0, 1, 2, 3, 4]),
        player: calls.add,
      );
      for (var i = 0; i < 5; i++) {
        sounds.blip();
      }
      expect(calls, ['blip-1', 'blip-2', 'blip-3', 'blip-4', 'blip-5']);
    });

    test('blip() never plays a long sample — navigation stays a click', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(() => true, random: Random(42), player: calls.add);
      for (var i = 0; i < 500; i++) {
        sounds.blip();
      }
      expect(calls, hasLength(500));
      // blip-6/7 and the twitters are seconds long and live in the droid
      // pool; a tab tap must never reach them, whatever the draw.
      expect(calls.toSet(), {'blip-1', 'blip-2', 'blip-3', 'blip-4', 'blip-5'});
    });

    test('confirm() picks among the chirps when the droid draw misses', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(
        () => true,
        random: _RiggedRandom(doubles: [0.5], ints: [0, 1, 2, 3]),
        player: calls.add,
      );
      for (var i = 0; i < 4; i++) {
        sounds.confirm();
      }
      expect(calls, ['chirp-1', 'chirp-2', 'chirp-3', 'chirp-4']);
    });

    test('confirm() answers with droid babble when the draw hits', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(
        () => true,
        random: _RiggedRandom(doubles: [0.001], ints: [0, 5]),
        player: calls.add,
      );
      sounds.confirm();
      sounds.confirm();
      expect(calls, ['blip-6', 'twitter-4']);
    });

    test('confirm() stays rare: the droid shows up in a small minority of changes', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(() => true, random: Random(7), player: calls.add);
      for (var i = 0; i < 1000; i++) {
        sounds.confirm();
      }
      final droids = calls.where((c) => !c.startsWith('chirp-')).length;
      expect(droids, greaterThan(20));
      expect(droids, lessThan(140));
    });

    test('error() picks among sad-1..2', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(
        () => true,
        random: _RiggedRandom(ints: [0, 1]),
        player: calls.add,
      );
      sounds.error();
      sounds.error();
      expect(calls, ['sad-1', 'sad-2']);
    });

    test('powerUp/powerDown/pttDown/pttSent play their fixed asset', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(() => true, player: calls.add);
      sounds
        ..powerUp()
        ..powerDown()
        ..pttDown()
        ..pttSent();
      expect(calls, ['power-up', 'power-down', 'ptt-click', 'ptt-roger']);
    });

    test('enabled() == false results in zero player interaction for every method', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(() => false, player: calls.add);
      sounds
        ..blip()
        ..confirm()
        ..powerUp()
        ..powerDown()
        ..pttDown()
        ..pttSent()
        ..error();
      expect(calls, isEmpty);
    });
  });
}
