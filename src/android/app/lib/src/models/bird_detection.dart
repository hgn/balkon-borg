/// One detection published on `balkon/birds/detections`
/// (`app/lib/src/contract/feeds.dart`) by BirdNET-Go directly, one message
/// per detection. The payload is BirdNET-Go's **native** schema, not yet
/// pinned in `src/shared/README.md` (planned for Pi stage M4), so parsing
/// tolerates several field-name-casing variants rather than assuming one.
class BirdDetection {
  const BirdDetection({
    required this.ts,
    required this.species,
    this.scientific,
    this.confidence,
  });

  factory BirdDetection.fromJson(Map<String, dynamic> json) => BirdDetection(
        ts: _parseTs(json),
        species: (json['CommonName'] ?? json['commonName'] ?? json['common_name'] ?? json['species'] ?? json['Species']) as String? ??
            '', // no field present: leave blank rather than invent a species name.
        scientific: (json['ScientificName'] ?? json['scientificName'] ?? json['scientific_name'] ?? json['scientificname']) as String?,
        confidence: _parseConfidence(json),
      );

  final DateTime ts;
  final String species; // common name; '' if the payload had no usable field.
  final String? scientific; // scientific name, nullable.
  final double? confidence; // normalized to 0..1, nullable.

  static double? _parseConfidence(Map<String, dynamic> json) {
    final raw = (json['Confidence'] ?? json['confidence']) as num?;
    if (raw == null) return null;
    final v = raw.toDouble();
    // BirdNET-Go and other tools disagree on 0..1 vs 0..100; anything above 1
    // is treated as a percentage.
    return v > 1.0 ? v / 100 : v;
  }

  static DateTime _parseTs(Map<String, dynamic> json) {
    final raw = json['Time'] ?? json['time'] ?? json['ts'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    if (raw is num) {
      // Epoch seconds vs. milliseconds: values below ~10^12 are seconds
      // (that threshold is year ~33658 in ms, or ~2001 in seconds — well
      // clear of any real timestamp either unit would produce today).
      final ms = raw < 1000000000000 ? (raw * 1000).round() : raw.round();
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Today's most-detected species, derived from [BirdDetection.ts] entries
/// dated `now` (local calendar day). Tie-break rule (undocumented upstream,
/// so fixed here): the species with the most today-detections wins; ties go
/// to whichever species' most recent detection is later.
class BirdOfDay {
  const BirdOfDay({required this.species, required this.count, required this.lastSeen});

  final String species;
  final int count;
  final DateTime lastSeen;

  static BirdOfDay? fromLog(List<BirdDetection> log, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final todays = log.where(
      (d) => d.ts.year == today.year && d.ts.month == today.month && d.ts.day == today.day,
    );

    final counts = <String, int>{};
    final lastSeen = <String, DateTime>{};
    for (final d in todays) {
      counts[d.species] = (counts[d.species] ?? 0) + 1;
      final prev = lastSeen[d.species];
      if (prev == null || d.ts.isAfter(prev)) lastSeen[d.species] = d.ts;
    }
    if (counts.isEmpty) return null;

    var bestSpecies = '';
    var bestCount = -1;
    DateTime? bestLastSeen;
    for (final species in counts.keys) {
      final count = counts[species]!;
      final seen = lastSeen[species]!;
      final better = count > bestCount || (count == bestCount && seen.isAfter(bestLastSeen!));
      if (better) {
        bestSpecies = species;
        bestCount = count;
        bestLastSeen = seen;
      }
    }
    return BirdOfDay(species: bestSpecies, count: bestCount, lastSeen: bestLastSeen!);
  }
}
