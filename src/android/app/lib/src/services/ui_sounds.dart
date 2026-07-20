/// Systematic UI sounds (E8 follow-up, gen-sounds.py), a "second sense"
/// alongside `services/haptics.dart` — additive, never a replacement for the
/// haptic at the same call site. Wraps `audioplayers` behind
/// `Settings.soundAudible` so every audible cue in the app goes through one
/// gate instead of scattered `AudioPlayer`/`AudioPool` calls that would
/// ignore the setting. Each cue belongs to a `SoundClass` the user can
/// silence on its own.
///
/// Grammar mirrors `haptics.dart`'s, mapped onto the WAVs under
/// `assets/audio/ui/`. The dividing line is **navigation vs. change**:
/// moving around the app is a click and nothing else, because it happens
/// too often and too fast for anything with a tail; changing what the
/// hardware is actually doing may occasionally get a droid's opinion.
/// - `blip` — the `selectionClick`/`lightImpact` counterpart: tabs, chips,
///   rows, cards. Uniform pick among the short clicks, no surprises ever.
/// - `confirm` — the "state-echo confirmation" counterpart to
///   `mediumImpact()` fired from `AppState._applyModeUpdate`, i.e. the
///   borgd reporting back that COMMS really went from off to FM. Usually
///   a chirp, at `_droidChance` a burst of droid babble instead. Suppressed
///   for SENTRY submode changes (see `app_state.dart`) since those already
///   get `powerUp`/`powerDown` at the switch itself.
/// - `powerUp`/`powerDown` — the SENTRY arm/disarm switch, mirroring the
///   `heavyImpact`/`mediumImpact` split there but as one sound each way
///   (power-up.wav / power-down.wav).
/// - `pttDown`/`pttSent` — push-to-talk: press-down (ptt-click.wav, next to
///   `mediumImpact()`) and a real network send actually succeeding
///   (ptt-roger.wav) — not release-to-send itself, which is a gesture, not
///   an outcome.
/// - `error` — a failed talkdown send (`_stopAndSend`'s non-2xx/catch
///   branches). Uniform pick among the sad ones.
library;

import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'sound_class.dart';

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

/// Navigation/selection clicks: short only (all well under ~120 ms). Moving
/// through the app happens faster than a long sample can finish, so anything
/// with a tail belongs in [_droids], not here.
const _clicks = ['blip-1', 'blip-2', 'blip-3', 'blip-4', 'blip-5'];

/// State-echo confirmations: a moment worth a beep, roughly one per
/// deliberate change rather than one per tap.
const _chirps = ['chirp-1', 'chirp-2', 'chirp-3', 'chirp-4'];

/// The droid babble — seconds long, full of character, and therefore only
/// ever heard on an actual change, at [_droidChance]. Never on navigation.
const _droids = [
  'blip-6',
  'blip-7',
  'twitter-1',
  'twitter-2',
  'twitter-3',
  'twitter-4',
];

const _sads = ['sad-1', 'sad-2', 'sad-3'];

/// Chance that [PackageUiSounds.confirm] answers with droid babble instead of
/// the usual chirp: rare enough to stay a surprise, common enough that a
/// session with a handful of mode changes has a decent chance of one.
const _droidChance = 0.07;

/// Volume every UI sound plays at — quiet enough to sit under haptics as a
/// "second sense", not a foreground effect.
const _volume = 0.35;

/// Real implementation backed by `package:audioplayers`'s `AudioPool` (one
/// pool per asset, lazily created and cached, `maxPlayers: 3` — cheap and
/// gives low-latency overlapping playback for e.g. rapid chip taps). Gated
/// per `SoundClass` by [audible].
///
/// [player] is the testability seam: production code leaves it at the
/// default (real `AudioPool` playback), tests inject a recording function so
/// they can assert "which asset would have played" without the plugin
/// channel `AudioPool`/`AudioPlayer` need for real playback. [random] is
/// likewise injectable so tests can rig the droid/uniform-pick draws
/// deterministically.
class PackageUiSounds implements UiSounds {
  PackageUiSounds(this.audible, {Random? random, void Function(String asset)? player})
      : _random = random ?? Random() {
    _player = player ?? _defaultPlay;
  }

  /// Asked fresh on every call, so a caller can hand this a closure over
  /// `Settings.soundAudible` and always get the current master + per-class
  /// state without re-creating the service.
  final bool Function(SoundClass) audible;
  final Random _random;
  late final void Function(String asset) _player;
  final Map<String, Future<AudioPool>> _pools = {};

  @override
  void blip() {
    if (!audible(SoundClass.navigation)) return;
    _player(_pick(_clicks));
  }

  @override
  void confirm() {
    if (!audible(SoundClass.confirm)) return;
    final droid = audible(SoundClass.droid) && _random.nextDouble() < _droidChance;
    _player(droid ? _pick(_droids) : _pick(_chirps));
  }

  @override
  void powerUp() {
    if (!audible(SoundClass.sentry)) return;
    _player('power-up');
  }

  @override
  void powerDown() {
    if (!audible(SoundClass.sentry)) return;
    _player('power-down');
  }

  @override
  void pttDown() {
    if (!audible(SoundClass.ptt)) return;
    _player('ptt-click');
  }

  @override
  void pttSent() {
    if (!audible(SoundClass.ptt)) return;
    _player('ptt-roger');
  }

  @override
  void error() {
    if (!audible(SoundClass.error)) return;
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
