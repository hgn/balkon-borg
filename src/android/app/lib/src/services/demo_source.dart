import 'dart:math' as math;

import '../contract/topics.dart';
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
  });

  final Map<MainMode, ModeState> modes;
  final MainMode focus;
  final Map<String, CapabilityHealth> health;
  final String healthSummary;
  final List<BorgEvent> events;
  final List<EnvSample> envHistory;
  final List<BirdDetection> birdLog;
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
    );
  }

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
