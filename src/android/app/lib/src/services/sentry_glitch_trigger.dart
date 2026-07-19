import '../models/borg_event.dart';
import 'event_differ.dart';

/// Detects a newly-arrived `security` event in `AppState.recentEvents` — the
/// trigger for the CRT glitch overlay on the camera view (E11,
/// implementation-plan.md D6). Chosen over watching for a SENTRY "alarm"
/// submode because the wire contract only defines `off`/`armed` today
/// (`models/mode_state.dart`); the retained event ring is the signal that
/// already exists and is already the honest "SENTRY reported a person"
/// source (it's what the watch-window notifications key off too).
///
/// Reuses [EventDiffer]'s ring-diffing so this and the watch window never
/// disagree about what counts as "new". Pure logic, no Flutter/platform
/// dependency — unit-testable on its own.
class SentryGlitchTrigger {
  SentryGlitchTrigger({this._differ = const EventDiffer()});

  final EventDiffer _differ;
  DateTime? _lastSeen;
  bool _initialized = false;

  /// Feed every `recentEvents` update through this. The very first call only
  /// establishes the baseline (whatever is already in the ring at that
  /// point) and never fires — mounting the camera screen with a security
  /// event already sitting in history must not itself glitch the view, only
  /// a genuinely new arrival after that should. Returns `true` exactly once
  /// per batch of newly-arrived security events.
  bool check(List<BorgEvent> ring) {
    if (!_initialized) {
      _lastSeen = _differ.nextLastSeen(ring: ring, lastSeen: null);
      _initialized = true;
      return false;
    }
    final newSecurity = _differ.diff(
      ring: ring,
      lastSeen: _lastSeen,
      isEnabled: (c) => c == EventCategory.security,
    );
    _lastSeen = _differ.nextLastSeen(ring: ring, lastSeen: _lastSeen);
    return newSecurity.isNotEmpty;
  }
}
