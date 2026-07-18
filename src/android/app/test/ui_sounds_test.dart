import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:balkon_borg/src/services/ui_sounds.dart';

/// A `Random` whose draws are scripted instead of pseudo-random, so tests can
/// force `PackageUiSounds` down a specific branch (e.g. the ~2% blip easter
/// egg) deterministically. Each list cycles if exhausted.
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
    test('blip() picks uniformly among blip-1..5 outside the easter egg', () {
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

    test('blip() stays within blip-1..5 / twitter-1..2 over many draws with a real Random', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(() => true, random: Random(42), player: calls.add);
      for (var i = 0; i < 300; i++) {
        sounds.blip();
      }
      expect(calls, isNotEmpty);
      expect(calls.any((c) => c.startsWith('blip-')), isTrue);
      expect(
        calls.every((c) => c.startsWith('blip-') || c.startsWith('twitter-')),
        isTrue,
      );
    });

    test('blip() easter-egg branch is reachable and picks among twitter-1..2', () {
      final calls = <String>[];
      // First draw (< 0.02) forces the easter-egg branch; second draw picks
      // within twitter-1/2.
      final egg1 = PackageUiSounds(
        () => true,
        random: _RiggedRandom(doubles: [0.001], ints: [0]),
        player: calls.add,
      );
      egg1.blip();
      final egg2 = PackageUiSounds(
        () => true,
        random: _RiggedRandom(doubles: [0.001], ints: [1]),
        player: calls.add,
      );
      egg2.blip();

      expect(calls, ['twitter-1', 'twitter-2']);
    });

    test('confirm() picks among chirp-1..3', () {
      final calls = <String>[];
      final sounds = PackageUiSounds(
        () => true,
        random: _RiggedRandom(ints: [0, 1, 2]),
        player: calls.add,
      );
      for (var i = 0; i < 3; i++) {
        sounds.confirm();
      }
      expect(calls, ['chirp-1', 'chirp-2', 'chirp-3']);
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
