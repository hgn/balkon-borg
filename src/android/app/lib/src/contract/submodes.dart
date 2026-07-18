/// Submode lists per main mode, mirroring the mode table in
/// `docs/use-cases.md` §"Mode placement (overview)". Single source of truth
/// for every submode picker (Home's bottom sheet, later Radio/Camera); every
/// list starts with an explicit "off" — that's how a main mode is switched
/// off in the contract (`ModeState.isOff`).
library;

import 'topics.dart';

/// One selectable entry in a submode list: the wire value (`submode` field
/// of `balkon/mode/<main>`, `src/shared/README.md`) plus its display label.
class Submode {
  const Submode(this.id, this.label);

  final String id;
  final String label;
}

abstract final class Submodes {
  static const lumen = [
    Submode('off', 'Aus'),
    Submode('ambient', 'Ambient'),
    Submode('full', 'Voll'),
    Submode('cozy', 'Cozy'),
    Submode('distance-auto', 'Distanz-Auto'),
    Submode('info-ticker', 'Info-Ticker'),
    Submode('disco', 'Disco'),
    Submode('strobe', 'Strobe'),
    Submode('police', 'Polizei'),
    Submode('visualiser', 'Visualizer'),
  ];

  static const comms = [
    Submode('off', 'Aus'),
    Submode('fm', 'FM'),
    Submode('dab', 'DAB+'),
    Submode('shortwave', 'Kurzwelle'),
    Submode('airband', 'Flugfunk'),
  ];

  static const sigint = [
    Submode('off', 'Aus'),
    Submode('adsb', 'ADS-B'),
    Submode('ism', 'ISM'),
    Submode('aprs', 'APRS'),
    Submode('radiosonde', 'Radiosonde'),
    Submode('spectrum', 'Spektrum'),
    Submode('captures', 'Aufnahmen'),
  ];

  static const sentry = [
    Submode('off', 'Aus'),
    Submode('armed', 'Scharf'),
  ];

  static List<Submode> forMode(MainMode m) => switch (m) {
        MainMode.lumen => lumen,
        MainMode.comms => comms,
        MainMode.sigint => sigint,
        MainMode.sentry => sentry,
      };

  /// Display label for a wire submode id; falls back to the raw id for
  /// values not in the list (defensive — the arbiter is the source of truth,
  /// a future submode not yet mirrored here should still render as *something*).
  static String labelFor(MainMode m, String id) => forMode(m)
      .firstWhere((s) => s.id == id, orElse: () => Submode(id, id))
      .label;
}
