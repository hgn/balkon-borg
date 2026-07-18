/// Payload of `balkon/mode/<main>` (see `src/shared/README.md`).
class ModeState {
  const ModeState({
    required this.submode,
    this.chan,
    this.pinned = false,
    this.since,
  });

  factory ModeState.fromJson(Map<String, dynamic> json) => ModeState(
        submode: json['submode'] as String? ?? 'off',
        chan: json['chan'] as String?,
        pinned: json['pinned'] as bool? ?? false,
        since: DateTime.tryParse(json['since'] as String? ?? ''),
      );

  final String submode;
  final String? chan;
  final bool pinned;
  final DateTime? since;

  bool get isOff => submode == 'off';
}
