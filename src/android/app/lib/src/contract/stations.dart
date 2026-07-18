/// Station presets for the COMMS bands (docs/use-cases.md §U10 "Radio").
/// App constants for now (implementation-plan.md D-notes): these lists are
/// not part of the wire contract, just UI convenience data. `Station.id` is
/// what gets sent as the `chan` value in `AppState.setSubmode`.
library;

/// One preset entry in a band's station list.
class Station {
  const Station(this.id, this.name, this.freq);

  /// Wire value (`chan` field of `balkon/cmd/mode/comms`).
  final String id;
  final String name;

  /// Display frequency, e.g. "97.3" (MHz for FM/airband); null when the band
  /// has no frequency to show (DAB+ tunes by ensemble/service, not by MHz).
  final String? freq;
}

abstract final class Stations {
  static const dab = [
    Station('deutschlandfunk', 'Deutschlandfunk', null),
    Station('ego-fm', 'egoFM', null),
    Station('br-klassik', 'BR-Klassik', null),
  ];

  static const fm = [
    Station('bayern-3', 'Bayern 3', '97.3'),
    Station('antenne-bayern', 'Antenne Bayern', '101.3'),
    Station('gong', 'Gong', '96.3'),
    Station('energy', 'Energy', '93.3'),
    Station('charivari', 'Charivari', '95.5'),
  ];

  static const airband = [
    Station('approach', 'Approach', '127.95'),
    Station('atis', 'ATIS', '123.13'),
    Station('director', 'Director', '118.82'),
    Station('tower', 'Tower', '118.7'),
  ];

  /// Preset list for a COMMS submode id; empty for bands with no presets
  /// (`shortwave` — free tuning, handled in the UI layer, not as data).
  static List<Station> forBand(String submode) => switch (submode) {
        'dab' => dab,
        'fm' => fm,
        'airband' => airband,
        _ => const [],
      };

  /// Default (first) station id for a band, or null when the band has no
  /// presets (`shortwave`).
  static String? defaultFor(String submode) {
    final list = forBand(submode);
    return list.isEmpty ? null : list.first.id;
  }

  /// Looks up a station by id across every band; null if not found (e.g. a
  /// shortwave `chan` or no `chan` at all).
  static Station? byId(String id) {
    for (final s in [...dab, ...fm, ...airband]) {
      if (s.id == id) return s;
    }
    return null;
  }
}
