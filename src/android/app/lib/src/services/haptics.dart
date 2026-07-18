/// Systematic haptics helper (E8, implementation-plan.md), wrapping
/// `HapticFeedback` behind `Settings.hapticsEnabled` so every tactile cue in
/// the app goes through one gate instead of scattered `HapticFeedback.*`
/// calls that would ignore the setting.
///
/// Grammar (which intensity for which interaction — motion.md's spirit,
/// applied to touch instead of visuals):
/// - `selectionClick` — picking one option among several: band/SIGINT chips,
///   effect chips, interval chips, bottom-nav tab switches.
/// - `lightImpact` — a plain confirmatory tap that doesn't change a mode:
///   mode-card taps (opens the submode sheet), sheet row taps, stat-tile
///   taps, theme toggle.
/// - `mediumImpact` — a state-changing press: PTT press-down, the SENTRY
///   switch toggle, and the "state-echo confirmation" fired from
///   `AppState` when an incoming/demo `ModeState` update actually changes
///   something (as opposed to a retained-message republish of the same
///   value — see `AppState._applyModeUpdate`).
/// - `heavyImpact` — the two deliberate, consequential actions: arming
///   SENTRY (distinct from the toggle's own `mediumImpact` — arming is the
///   moment the system actually goes armed) and PTT release-to-send.
library;

import 'package:flutter/services.dart';

/// Injectable so tests can record calls instead of hitting the platform
/// channel `HapticFeedback` talks to.
abstract class Haptics {
  void selectionClick();
  void lightImpact();
  void mediumImpact();
  void heavyImpact();
}

/// No-op implementation: satisfies the `Provider<Haptics>` widget tests
/// need without touching any platform channel or asserting on call counts —
/// tests that actually want to assert on haptic calls use their own
/// recording fake instead (see e.g. `test/app_state_test.dart`).
class NoopHaptics implements Haptics {
  const NoopHaptics();

  @override
  void selectionClick() {}

  @override
  void lightImpact() {}

  @override
  void mediumImpact() {}

  @override
  void heavyImpact() {}
}

/// Real implementation backed by `package:flutter/services.dart`. Gated by
/// [enabled] — evaluated fresh on every call so callers can hand this a
/// closure over `Settings.hapticsEnabled` and always get the current value.
class SystemHaptics implements Haptics {
  const SystemHaptics(this.enabled);

  final bool Function() enabled;

  @override
  void selectionClick() {
    if (enabled()) HapticFeedback.selectionClick();
  }

  @override
  void lightImpact() {
    if (enabled()) HapticFeedback.lightImpact();
  }

  @override
  void mediumImpact() {
    if (enabled()) HapticFeedback.mediumImpact();
  }

  @override
  void heavyImpact() {
    if (enabled()) HapticFeedback.heavyImpact();
  }
}
