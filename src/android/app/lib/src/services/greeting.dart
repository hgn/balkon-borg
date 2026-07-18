import 'dart:math';

/// Rotating home-screen greeting, modeled on claude.ai's greeting system: a
/// handful of weighted template pools (time-of-day, weekday specials,
/// generic filler), one weighted-random draw per app session, then a plain
/// name substitution on every subsequent call (see [greet]).
///
/// Pure and `DateTime`/`Random`-injectable so the whole thing is
/// unit-testable without a widget tree.
class GreetingEngine {
  GreetingEngine({DateTime? now, Random? random})
      : _now = now ?? DateTime.now(),
        _random = random ?? Random();

  final DateTime _now;
  final Random _random;

  /// The weighted draw happens once, memoized here on first [greet] call.
  /// The shared app-level [greetingEngine] instance is what makes this
  /// survive rebuilds and tab switches (not just repeated calls on one
  /// instance) — see its doc comment at the bottom of this file.
  _GreetingTemplate? _drawn;

  /// The greeting line for [name] (optional; empty/whitespace-only is
  /// treated as absent). The template is drawn once and cached; only the
  /// name substitution happens again on each call, so a name entered after
  /// the first draw still shows up without re-rolling the chosen line.
  String greet({String? name}) {
    final template = _drawn ??= _draw();
    final trimmed = name?.trim();
    return template.render(trimmed == null || trimmed.isEmpty ? null : trimmed);
  }

  _GreetingTemplate _draw() {
    final candidates = _weightedCandidates();
    final total = candidates.fold<int>(0, (sum, c) => sum + c.weight);
    var roll = _random.nextInt(total);
    for (final c in candidates) {
      if (roll < c.weight) return c.template;
      roll -= c.weight;
    }
    return candidates.last.template; // unreachable: roll < total by construction.
  }

  /// Base weight ~3 for the time-of-day pool, ~2 for the matching weekday
  /// special (only drawn on its day), ~1 for the generic filler. Night owl
  /// hours deliberately skip weekday specials entirely — nobody gets a
  /// "Montag. Widerstand ist zwecklos." at 3am.
  List<_Weighted> _weightedCandidates() {
    final bucket = _bucketFor(_now);
    if (bucket == _TimeBucket.night) {
      return [..._weight(_night, 3), ..._weight(_generic, 1)];
    }
    final specials = _weekdaySpecials(_now.weekday);
    return [
      ..._weight(_poolFor(bucket), 3),
      if (specials != null) ..._weight(specials, 2),
      ..._weight(_generic, 1),
    ];
  }

  static List<_Weighted> _weight(List<_GreetingTemplate> pool, int weight) =>
      [for (final t in pool) _Weighted(t, weight)];

  static List<_GreetingTemplate> _poolFor(_TimeBucket bucket) => switch (bucket) {
        _TimeBucket.morning => _morning,
        _TimeBucket.day => _day,
        _TimeBucket.evening => _evening,
        _TimeBucket.night => _night,
      };

  static List<_GreetingTemplate>? _weekdaySpecials(int weekday) => switch (weekday) {
        DateTime.monday => _monday,
        DateTime.friday => _friday,
        DateTime.saturday => _saturday,
        DateTime.sunday => _sunday,
        _ => null,
      };

  /// Boundaries: morning 5:00–11:00, day 11:00–18:00, evening 18:00–20:30,
  /// night 20:30–5:00. The evening/night split falls on a half hour, so
  /// this works on minute-of-day, not just the hour.
  static _TimeBucket _bucketFor(DateTime t) {
    final minuteOfDay = t.hour * 60 + t.minute;
    if (minuteOfDay >= 5 * 60 && minuteOfDay < 11 * 60) return _TimeBucket.morning;
    if (minuteOfDay >= 11 * 60 && minuteOfDay < 18 * 60) return _TimeBucket.day;
    if (minuteOfDay >= 18 * 60 && minuteOfDay < 20 * 60 + 30) return _TimeBucket.evening;
    return _TimeBucket.night;
  }
}

enum _TimeBucket { morning, day, evening, night }

/// One candidate in the weighted draw: a template paired with its pool's
/// relative weight.
class _Weighted {
  const _Weighted(this.template, this.weight);
  final _GreetingTemplate template;
  final int weight;
}

/// A single greeting line. `{n}` marks a name slot: with a name it renders
/// as `, Name` spliced in right before the punctuation; without one it
/// disappears, leaving the plain sentence. Templates without `{n}` never
/// mention a name either way.
class _GreetingTemplate {
  const _GreetingTemplate(this._raw);
  final String _raw;

  String render(String? name) => _raw.replaceFirst('{n}', name == null ? '' : ', $name');
}

const _morning = [
  _GreetingTemplate('Guten Morgen{n}.'),
  _GreetingTemplate('Erst Kaffee, dann Kollektiv.'),
  _GreetingTemplate('Systeme hochgefahren{n}.'),
  _GreetingTemplate('Der Balkon wartet schon.'),
];

const _day = [
  _GreetingTemplate('Guten Tag{n}.'),
  _GreetingTemplate('Alle Systeme nominal.'),
  _GreetingTemplate('Servus beinand.'),
  _GreetingTemplate('Beste Zeit für frische Luft.'),
];

const _evening = [
  _GreetingTemplate('Guten Abend{n}.'),
  _GreetingTemplate('Der Abend gehört dem Balkon.'),
  _GreetingTemplate('Zeit für die Terrasse{n}.'),
  _GreetingTemplate('Feierabend{n}?'),
];

const _night = [
  _GreetingTemplate('Hallo, Nachteule.'),
  _GreetingTemplate('Noch wach{n}?'),
  _GreetingTemplate('Regenerationszyklus empfohlen.'),
  _GreetingTemplate('Die Vögel schlafen schon.'),
];

const _generic = [
  _GreetingTemplate('Wieder im Kollektiv.'),
  _GreetingTemplate("Was gibt's Neues{n}?"),
  _GreetingTemplate("Wie läuft's{n}?"),
  _GreetingTemplate('Zurück am Balkon{n}?'),
];

const _monday = [
  _GreetingTemplate('Montag. Widerstand ist zwecklos.'),
];

const _friday = [
  _GreetingTemplate('Endlich Freitag{n}.'),
  _GreetingTemplate('Das Freitagsgefühl.'),
];

const _saturday = [
  _GreetingTemplate('Schönen Samstag{n}.'),
  _GreetingTemplate('Willkommen im Wochenende{n}.'),
];

const _sunday = [
  _GreetingTemplate('Sonntags-Session{n}?'),
  _GreetingTemplate('Schönen Sonntag{n}.'),
];

/// Shared app-level instance: the greeting draw happens once for the whole
/// app session (memoized in [GreetingEngine.greet]). `HomeScreen` reads
/// this singleton rather than owning its own engine so the greeting
/// survives tab switches and rebuilds alike, not just repeated builds of
/// the same widget instance.
final greetingEngine = GreetingEngine();
