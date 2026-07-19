import 'dart:math' as math;
import 'dart:ui' show Color;

import '../contract/topics.dart';
import '../models/aircraft.dart';
import '../models/bird_detection.dart';
import '../models/borg_event.dart';
import '../models/env_sample.dart';
import '../models/health.dart';
import '../models/mode_state.dart';

/// A fully-populated snapshot of everything `AppState` normally assembles
/// from MQTT messages, produced by [DemoSource] instead (D2 — demo mode).
class DemoSnapshot {
  const DemoSnapshot({
    required this.modes,
    required this.focus,
    required this.health,
    required this.healthSummary,
    required this.events,
    required this.envHistory,
    required this.birdLog,
    required this.wledColor,
    required this.aircraft,
  });

  final Map<MainMode, ModeState> modes;
  final MainMode focus;
  final Map<String, CapabilityHealth> health;
  final String healthSummary;
  final List<BorgEvent> events;
  final List<EnvSample> envHistory;
  final List<BirdDetection> birdLog;
  final Color? wledColor;
  final List<Aircraft> aircraft;
}

/// Builds realistic fake data instead of the real broker (D2 — demo mode).
/// Keeps every screen developable and screenshotable before the Pi broker
/// (M1) exists; stays available afterwards as a toggleable feature.
class DemoSource {
  const DemoSource();

  DemoSnapshot build({DateTime? now}) {
    final ts = now ?? DateTime.now();

    return DemoSnapshot(
      modes: const {
        MainMode.lumen: ModeState(submode: 'info-ticker'),
        MainMode.comms: ModeState(submode: 'off'),
        MainMode.sigint: ModeState(submode: 'adsb'),
        MainMode.sentry: ModeState(submode: 'off'),
      },
      focus: MainMode.lumen,
      health: const {
        'clock': CapabilityHealth(state: HealthState.ok),
        'sdr': CapabilityHealth(state: HealthState.ok),
        'mic': CapabilityHealth(state: HealthState.ok),
        'speaker': CapabilityHealth(state: HealthState.ok),
        'camera': CapabilityHealth(state: HealthState.ok),
        'esp': CapabilityHealth(state: HealthState.ok),
        // Degraded on purpose (D2: "visual variety in the health sheet").
        'wled': CapabilityHealth(state: HealthState.degraded, detail: 'reconnecting'),
      },
      healthSummary: 'demo mode — wled reconnecting',
      events: [
        BorgEvent(
          ts: ts.subtract(const Duration(minutes: 4)),
          category: EventCategory.bird,
          text: 'Kohlmeise detected',
        ),
        BorgEvent(
          ts: ts.subtract(const Duration(minutes: 22)),
          category: EventCategory.aircraft,
          text: 'DLH445 low overflight',
        ),
        BorgEvent(
          ts: ts.subtract(const Duration(hours: 1, minutes: 10)),
          category: EventCategory.tpms,
          text: 'TPMS sensor 3a91 passed',
        ),
        BorgEvent(
          ts: ts.subtract(const Duration(hours: 3, minutes: 5)),
          category: EventCategory.bird,
          text: 'Amsel detected',
        ),
      ],
      envHistory: _buildEnvHistory(ts),
      birdLog: _buildBirdLog(ts),
      // Demo default LUMEN submode is 'info-ticker' → no glow (see below).
      wledColor: colorForLumenSubmode('info-ticker'),
      aircraft: _buildAircraft(),
    );
  }

  /// Plausible EDDM-approach traffic (E10): five aircraft around the
  /// balcony, spread across the altitude/distance ranges real ADS-B would
  /// show — a couple of jets low and slow on final into Munich, one climbing
  /// out, one crossing at cruise. `lat`/`lon` are derived from `bearingDeg`/
  /// `distKm` via [GreatCircle.destination] rather than picked separately,
  /// so the two stay consistent with each other (and with what a real
  /// `fromJson` payload implies) from the first frame.
  List<Aircraft> _buildAircraft() {
    Aircraft make({
      required String hex,
      required String flight,
      required double bearingDeg,
      required double distKm,
      required double altFt,
      required double trackDeg,
      required double groundSpeedKt,
    }) {
      final pos = GreatCircle.destination(BorgGeo.homeLat, BorgGeo.homeLon, bearingDeg, distKm);
      return Aircraft(
        hex: hex,
        flight: flight,
        lat: pos.lat,
        lon: pos.lon,
        altFt: altFt,
        trackDeg: trackDeg,
        groundSpeedKt: groundSpeedKt,
        distKm: distKm,
        bearingDeg: bearingDeg,
      );
    }

    return [
      // Short final, low and slow — about to land south-west of the balcony.
      make(
        hex: '3c6a1f',
        flight: 'DLH9CJ',
        bearingDeg: 150,
        distKm: 6.5,
        altFt: 2400,
        trackDeg: 330,
        groundSpeedKt: 140,
      ),
      // Mid final, descending from the north.
      make(
        hex: '3c4b02',
        flight: 'EJU2371',
        bearingDeg: 8,
        distKm: 18,
        altFt: 5200,
        trackDeg: 187,
        groundSpeedKt: 210,
      ),
      // Further out on approach, from the west.
      make(
        hex: '3c8e77',
        flight: 'RYR74HB',
        bearingDeg: 245,
        distKm: 24,
        altFt: 9800,
        trackDeg: 65,
        groundSpeedKt: 260,
      ),
      // Just beyond the outer ring — clamped-blip demo traffic.
      make(
        hex: '3c1d90',
        flight: 'DLH441',
        bearingDeg: 300,
        distKm: 39,
        altFt: 15000,
        trackDeg: 120,
        groundSpeedKt: 320,
      ),
      // High cruise overflight, no relation to Munich approach traffic.
      make(
        hex: '4baa3c',
        flight: 'EJU55TT',
        bearingDeg: 95,
        distKm: 33,
        altFt: 37000,
        trackDeg: 275,
        groundSpeedKt: 460,
      ),
    ];
  }

  /// Advances every aircraft's position along its own track for [dt] of
  /// simulated flight time (kt → km/h via the 1.852 nm/km factor), then
  /// recomputes `distKm`/`bearingDeg` from the new position — the same
  /// [GreatCircle] math a real payload's fallback would use, so demo traffic
  /// behaves exactly like the real feed would once it moves. Aircraft
  /// missing the fields needed to move (no lat/lon/track/speed) pass through
  /// unchanged rather than being dropped.
  List<Aircraft> advanceAircraft(List<Aircraft> current, Duration dt) =>
      [for (final a in current) _advanceOne(a, dt)];

  Aircraft _advanceOne(Aircraft a, Duration dt) {
    if (a.lat == null || a.lon == null || a.trackDeg == null || a.groundSpeedKt == null) {
      return a;
    }
    final hours = dt.inMicroseconds / (Duration.microsecondsPerHour);
    final distanceKm = a.groundSpeedKt! * 1.852 * hours;
    final dest = GreatCircle.destination(a.lat!, a.lon!, a.trackDeg!, distanceKm);
    return a.copyWith(
      lat: dest.lat,
      lon: dest.lon,
      distKm: GreatCircle.distanceKm(BorgGeo.homeLat, BorgGeo.homeLon, dest.lat, dest.lon),
      bearingDeg: GreatCircle.bearingDeg(BorgGeo.homeLat, BorgGeo.homeLon, dest.lat, dest.lon),
    );
  }

  /// Plausible WLED glow color for a LUMEN submode (E9 — implementation-
  /// plan.md), standing in for `wled/balkon/v` while there's no real WLED to
  /// echo it back. Judgment call, not from `design/tokens.json`: WLED picks
  /// its own color independently of the app's brand palette, so these are
  /// scene-appropriate guesses, not the LUMEN/COMMS/SIGINT/SENTRY semantic
  /// colors. `off` and `info-ticker` stay `null` — a ticker doesn't imply a
  /// stable ambient color, and `off` obviously has no light to glow.
  Color? colorForLumenSubmode(String submode) => switch (submode) {
        'ambient' => const Color(0xFFFFB066), // warm white-orange
        'cozy' => const Color(0xFFFF8A3D), // warmer orange, fireplace-like
        'full' => const Color(0xFFFFEAC2), // bright warm white
        'distance-auto' => const Color(0xFFFFD9A0), // soft auto warm white
        'disco' => const Color(0xFFB33BFF), // violet
        'strobe' => const Color(0xFFFFFFFF), // white flash
        'police' => const Color(0xFF3B82F6), // blue
        'visualiser' => const Color(0xFF35E6FF), // cyan, music-reactive
        _ => null, // 'off', 'info-ticker', unknown.
      };

  /// ~2 days of plausible Munich-balcony bird detections, newest first
  /// (matches the accumulation order `AppState` uses for the real feed).
  /// Deliberately skewed so today's log has one clear winner for
  /// "Vogel des Tages": **Amsel, count=5, last seen 12 min before `now`** —
  /// the widget test (`log_screen_test.dart`) asserts against these exact
  /// values. Today's other species stay at 1-2 detections each so the lead
  /// is unambiguous. "Today" is relative to `now`/build time (like the rest
  /// of `DemoSource`), so this assumes tests don't run within a few hours of
  /// local midnight, same as the existing `events` demo data.
  List<BirdDetection> _buildBirdLog(DateTime now) {
    BirdDetection at(Duration ago, String species, String? scientific, double confidence) =>
        BirdDetection(ts: now.subtract(ago), species: species, scientific: scientific, confidence: confidence);

    return [
      // Today — Amsel leads clearly (5 vs. 1-2 for everyone else).
      at(const Duration(minutes: 12), 'Amsel', 'Turdus merula', 0.94),
      at(const Duration(minutes: 35), 'Kohlmeise', 'Parus major', 0.90),
      at(const Duration(hours: 1, minutes: 5), 'Amsel', 'Turdus merula', 0.91),
      at(const Duration(hours: 1, minutes: 50), 'Rotkehlchen', 'Erithacus rubecula', 0.85),
      at(const Duration(hours: 2, minutes: 40), 'Amsel', 'Turdus merula', 0.88),
      at(const Duration(hours: 3, minutes: 5), 'Haussperling', 'Passer domesticus', 0.68),
      at(const Duration(hours: 4, minutes: 15), 'Amsel', 'Turdus merula', 0.83),
      at(const Duration(hours: 5, minutes: 20), 'Kohlmeise', 'Parus major', 0.76),
      at(const Duration(hours: 6, minutes: 50), 'Amsel', 'Turdus merula', 0.79),
      at(const Duration(hours: 7, minutes: 30), 'Elster', 'Pica pica', 0.95),
      // Yesterday — excluded from "Vogel des Tages", kept for log-scroll variety.
      at(const Duration(days: 1, hours: 2), 'Blaumeise', 'Cyanistes caeruleus', 0.72),
      at(const Duration(days: 1, hours: 3), 'Buchfink', 'Fringilla coelebs', 0.81),
      at(const Duration(days: 1, hours: 5), 'Mauersegler', 'Apus apus', 0.65),
      at(const Duration(days: 1, hours: 6), 'Amsel', 'Turdus merula', 0.90),
      at(const Duration(days: 1, hours: 8), 'Kohlmeise', 'Parus major', 0.60),
      at(const Duration(days: 1, hours: 10), 'Elster', 'Pica pica', 0.93),
      at(const Duration(days: 1, hours: 20), 'Rotkehlchen', 'Erithacus rubecula', 0.55),
      at(const Duration(days: 1, hours: 22), 'Haussperling', 'Passer domesticus', 0.98),
    ];
  }

  /// ~24h of plausible temperature/humidity/pressure samples (1/hour), a
  /// mild diurnal curve rather than flat lines — matches the
  /// `balkon/env/recent` shape (`src/shared/README.md`).
  List<EnvSample> _buildEnvHistory(DateTime now) {
    return [
      for (var h = 24; h >= 0; h--)
        () {
          final phase = (24 - h) / 24 * 2 * math.pi - math.pi / 2;
          return EnvSample(
            ts: now.subtract(Duration(hours: h)),
            t: 17.5 + 4.5 * math.sin(phase),
            h: 58 - 12 * math.sin(phase),
            p: 1012 + 3 * math.sin(phase / 2),
          );
        }(),
    ];
  }
}
