/// One sample of the retained `balkon/env/recent` ring
/// (see `src/shared/README.md`): temperature (°C), humidity (%), pressure (hPa).
class EnvSample {
  const EnvSample({
    required this.ts,
    required this.t,
    required this.h,
    required this.p,
  });

  factory EnvSample.fromJson(Map<String, dynamic> json) => EnvSample(
        ts: DateTime.tryParse(json['ts'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        t: (json['t'] as num?)?.toDouble() ?? 0,
        h: (json['h'] as num?)?.toDouble() ?? 0,
        p: (json['p'] as num?)?.toDouble() ?? 0,
      );

  final DateTime ts;
  final double t;
  final double h;
  final double p;
}
