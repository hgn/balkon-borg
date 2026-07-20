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

  /// SENTRY submode values that count as "armed" for the subtle red border
  /// (components.md "Mode-Card" / "SENTRY-Karte") and the SENTRY switch
  /// position (Camera screen). Only `armed` exists in the contract today
  /// (see `sentry` above); `grace`/`alarm` are named here as a forward-
  /// looking extension of the same armed family (docs/use-cases.md §U11
  /// lifecycle: off · arming · armed · grace · alarm) so both call sites
  /// don't need a follow-up change if/when borgd starts sending them.
  static const sentryArmedSubmodes = {'armed', 'grace', 'alarm'};

  static List<Submode> forMode(MainMode m) => switch (m) {
        MainMode.lumen => lumen,
        MainMode.comms => comms,
        MainMode.sigint => sigint,
        MainMode.sentry => sentry,
      };

  /// The actual programs of a mode, without the `off` entry: what the mode
  /// does *when it runs*. Off is a power state one level above these and is
  /// offered as a switch, not as a list row (user call 2026-07-19).
  static List<Submode> programsFor(MainMode m) =>
      forMode(m).where((s) => s.id != 'off').toList(growable: false);

  /// Display label for a wire submode id; falls back to the raw id for
  /// values not in the list (defensive — borgd is the source of truth,
  /// a future submode not yet mirrored here should still render as *something*).
  static String labelFor(MainMode m, String id) => forMode(m)
      .firstWhere((s) => s.id == id, orElse: () => Submode(id, id))
      .label;
}
