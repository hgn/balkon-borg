/// Hysteresis state machine for the condensation background wash (E11,
/// implementation-plan.md D6): on above [onThreshold]% relative humidity,
/// off again only below [offThreshold]% — the gap keeps a sensor hovering
/// right at 85% from flickering the effect on and off every sample. Pure
/// logic, no Flutter dependency — unit-testable on its own.
class CondensationGate {
  CondensationGate({this.onThreshold = 85.0, this.offThreshold = 82.0})
      : assert(offThreshold < onThreshold, 'offThreshold must be below onThreshold');

  final double onThreshold;
  final double offThreshold;

  bool _active = false;

  bool get isActive => _active;

  /// Feed the newest humidity sample (`AppState.envHistory.last.h`, or
  /// `null` while there is no data yet). Returns the resulting state.
  /// Missing data holds the current state rather than switching either way
  /// — a momentary gap in the env feed should not itself toggle the effect.
  bool update(double? humidity) {
    if (humidity == null) return _active;
    if (_active) {
      if (humidity < offThreshold) _active = false;
    } else {
      if (humidity >= onThreshold) _active = true;
    }
    return _active;
  }
}
