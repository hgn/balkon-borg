/// Payloads of `balkon/health` and `balkon/health/<capability>`
/// (see `src/shared/README.md`).
enum HealthState {
  ok,
  degraded,
  missing,
  disabled;

  static HealthState parse(String? s) => HealthState.values.firstWhere(
        (v) => v.name == s,
        orElse: () => HealthState.missing,
      );
}

class CapabilityHealth {
  const CapabilityHealth({
    required this.state,
    this.detail,
    this.since,
    this.lastOk,
  });

  factory CapabilityHealth.fromJson(Map<String, dynamic> json) =>
      CapabilityHealth(
        state: HealthState.parse(json['state'] as String?),
        detail: json['detail'] as String?,
        since: DateTime.tryParse(json['since'] as String? ?? ''),
        lastOk: DateTime.tryParse(json['last_ok'] as String? ?? ''),
      );

  final HealthState state;
  final String? detail;
  final DateTime? since;
  final DateTime? lastOk;
}
