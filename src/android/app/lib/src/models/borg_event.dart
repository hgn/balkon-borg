/// One entry of the retained `balkon/event/recent` ring
/// (see `src/shared/README.md`). The watch window diffs this list against the
/// last-seen timestamp to raise local notifications.
enum EventCategory {
  aircraft,
  bird,
  storm,
  security,
  tpms,
  other;

  static EventCategory parse(String? s) => EventCategory.values.firstWhere(
        (v) => v.name == s,
        orElse: () => EventCategory.other,
      );
}

class BorgEvent {
  const BorgEvent({required this.ts, required this.category, required this.text});

  factory BorgEvent.fromJson(Map<String, dynamic> json) => BorgEvent(
        ts: DateTime.tryParse(json['ts'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        category: EventCategory.parse(json['category'] as String?),
        text: json['text'] as String? ?? '',
      );

  final DateTime ts;
  final EventCategory category;
  final String text;
}
