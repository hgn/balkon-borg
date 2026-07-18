/// Systematic UI sounds (E8 follow-up, gen-sounds.py), a "second sense"
/// alongside `services/haptics.dart` — additive, never a replacement for the
/// haptic at the same call site. Wraps `audioplayers` behind
/// `Settings.uiSoundsEnabled` so every audible cue in the app goes through
/// one gate instead of scattered `AudioPlayer`/`AudioPool` calls that would
/// ignore the setting.
///
/// Grammar mirrors `haptics.dart`'s (gen-sounds.py's docstring: "Sound
/// grammar mirrors the haptics grammar"), mapped onto the 16 WAVs under
/// `assets/audio/ui/`:
/// - `blip` — the `selectionClick`/`lightImpact` counterpart: picking one
///   option, a plain confirmatory tap. Uniform pick among blip-1..5, with a
///   ~2% "excited babble" easter egg (twitter-1/2, gen-sounds.py) instead —
///   the droid getting overly enthusiastic about a routine tap.
/// - `confirm` — the "state-echo confirmation" counterpart to
///   `mediumImpact()` fired from `AppState._applyModeUpdate`. Uniform pick
///   among chirp-1..3. Suppressed for SENTRY submode changes (see
///   `app_state.dart`) since those already get `powerUp`/`powerDown` at the
///   switch itself — playing `confirm` too would double up.
/// - `powerUp`/`powerDown` — the SENTRY arm/disarm switch, mirroring the
///   `heavyImpact`/`mediumImpact` split there but as one sound each way
///   (power-up.wav / power-down.wav).
/// - `pttDown`/`pttSent` — push-to-talk: press-down (ptt-click.wav, next to
///   `mediumImpact()`) and a real network send actually succeeding
///   (ptt-roger.wav) — not release-to-send itself, which is a gesture, not
///   an outcome.
/// - `error` — a failed talkdown send (`_stopAndSend`'s non-2xx/catch
///   branches). Uniform pick among sad-1..2.
library;

import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

abstract class UiSounds {
  void blip();
  void confirm();
  void powerUp();
  void powerDown();
  void pttDown();
  void pttSent();
  void error();
}

/// No-op implementation: satisfies the `Provider<UiSounds>` widget tests
/// need without touching any platform channel or asserting on call counts —
/// tests that actually want to assert on sound calls use their own
/// recording fake instead (see e.g. `test/app_state_test.dart`,
/// `test/shell_test.dart`).
class NoopUiSounds implements UiSounds {
  const NoopUiSounds();

  @override
  void blip() {}

  @override
  void confirm() {}

  @override
  void powerUp() {}

  @override
  void powerDown() {}

  @override
  void pttDown() {}

  @override
  void pttSent() {}

  @override
  void error() {}
}

const _blips = ['blip-1', 'blip-2', 'blip-3', 'blip-4', 'blip-5'];
const _chirps = ['chirp-1', 'chirp-2', 'chirp-3'];
const _twitters = ['twitter-1', 'twitter-2'];
const _sads = ['sad-1', 'sad-2'];

/// Chance that [PackageUiSounds.blip] plays a `twitter-*` easter egg instead
/// of a plain `blip-*`.
const _easterEggChance = 0.02;

/// Volume every UI sound plays at — quiet enough to sit under haptics as a
/// "second sense", not a foreground effect.
const _volume = 0.35;

/// Real implementation backed by `package:audioplayers`'s `AudioPool` (one
/// pool per asset, lazily created and cached, `maxPlayers: 3` — cheap and
/// gives low-latency overlapping playback for e.g. rapid chip taps). Gated
/// by [enabled] — evaluated fresh on every call so callers can hand this a
/// closure over `Settings.uiSoundsEnabled` and always get the current value.
///
/// [player] is the testability seam: production code leaves it at the
/// default (real `AudioPool` playback), tests inject a recording function so
/// they can assert "which asset would have played" without the plugin
/// channel `AudioPool`/`AudioPlayer` need for real playback. [random] is
/// likewise injectable so tests can rig the blip/easter-egg/uniform-pick
/// draws deterministically.
class PackageUiSounds implements UiSounds {
  PackageUiSounds(this.enabled, {Random? random, void Function(String asset)? player})
      : _random = random ?? Random() {
    _player = player ?? _defaultPlay;
  }

  final bool Function() enabled;
  final Random _random;
  late final void Function(String asset) _player;
  final Map<String, Future<AudioPool>> _pools = {};

  @override
  void blip() {
    if (!enabled()) return;
    if (_random.nextDouble() < _easterEggChance) {
      _player(_pick(_twitters));
    } else {
      _player(_pick(_blips));
    }
  }

  @override
  void confirm() {
    if (!enabled()) return;
    _player(_pick(_chirps));
  }

  @override
  void powerUp() {
    if (!enabled()) return;
    _player('power-up');
  }

  @override
  void powerDown() {
    if (!enabled()) return;
    _player('power-down');
  }

  @override
  void pttDown() {
    if (!enabled()) return;
    _player('ptt-click');
  }

  @override
  void pttSent() {
    if (!enabled()) return;
    _player('ptt-roger');
  }

  @override
  void error() {
    if (!enabled()) return;
    _player(_pick(_sads));
  }

  String _pick(List<String> names) => names[_random.nextInt(names.length)];

  /// Fire-and-forget default [_player]: hands off to the async pool lookup
  /// and never lets a playback failure surface to the caller.
  void _defaultPlay(String assetName) {
    unawaited(_playViaPool(assetName));
  }

  Future<void> _playViaPool(String assetName) async {
    try {
      final pool = await _pools.putIfAbsent(
        assetName,
        () => AudioPool.create(
          source: AssetSource('audio/ui/$assetName.wav'),
          maxPlayers: 3,
        ),
      );
      await pool.start(volume: _volume);
    } catch (_) {
      // Any playback failure (missing plugin on host, decode error, missing
      // asset, etc.) is silently ignored — UI sounds must never crash or
      // block the interaction they're attached to.
    }
  }
}
