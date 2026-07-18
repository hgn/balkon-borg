import '../models/borg_event.dart';

/// Pure diffing logic for the watch-window notification model
/// (`src/shared/README.md` "Notification model — no push server"): given the
/// retained `balkon/event/recent` ring and the timestamp of the last event
/// the app already notified about, decide which entries are new and should
/// raise a local notification. No platform calls here on purpose — this is
/// unit-tested in isolation, the platform-facing side lives in
/// `services/watch_window.dart`.
class EventDiffer {
  const EventDiffer();

  /// First-run cap: a fresh install (or a cleared last-seen marker) has no
  /// baseline, so every entry in the ring (up to ~20, per the contract)
  /// would otherwise look "new" — a notification bomb the moment the watch
  /// window first connects. Decision (documented here, not just in the
  /// implementation plan): cap a first check to the newest
  /// [firstRunNotifyCap] entries; [nextLastSeen] still advances to the
  /// ring's newest timestamp regardless, so the skipped older entries are
  /// never notified retroactively either. Rejected alternative: notify
  /// nothing on first run — rejected because a security event sitting in
  /// the ring right when the app is first installed/reopened after a long
  /// gap is exactly the case the watch window exists for.
  static const firstRunNotifyCap = 3;

  /// Events that should raise a notification: newer than [lastSeen] and in
  /// an enabled category per [isEnabled]; on a first run ([lastSeen] is
  /// `null`) capped to the newest [firstRunNotifyCap] ring entries before
  /// the category filter is applied. `ring` is newest-first, matching the
  /// contract; the result keeps that order.
  List<BorgEvent> diff({
    required List<BorgEvent> ring,
    required DateTime? lastSeen,
    required bool Function(EventCategory category) isEnabled,
  }) {
    final candidates = lastSeen == null
        ? ring.take(firstRunNotifyCap)
        : ring.where((e) => e.ts.isAfter(lastSeen));
    return [for (final e in candidates) if (isEnabled(e.category)) e];
  }

  /// The last-seen timestamp to persist after a check: the newest timestamp
  /// in [ring], or [lastSeen] unchanged if the ring is empty or does not
  /// advance past it. Always the newest *ring* timestamp regardless of
  /// [diff]'s category filter or first-run cap, so an event never gets
  /// notified twice (e.g. after the user later enables a category that was
  /// off when the event first appeared).
  DateTime? nextLastSeen({required List<BorgEvent> ring, required DateTime? lastSeen}) {
    if (ring.isEmpty) return lastSeen;
    final newest = ring.map((e) => e.ts).reduce((a, b) => a.isAfter(b) ? a : b);
    if (lastSeen != null && !newest.isAfter(lastSeen)) return lastSeen;
    return newest;
  }
}
