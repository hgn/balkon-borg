import 'dart:math' as math;

import '../contract/topics.dart';
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
  });

  final Map<MainMode, ModeState> modes;
  final MainMode focus;
  final Map<String, CapabilityHealth> health;
  final String healthSummary;
  final List<BorgEvent> events;
  final List<EnvSample> envHistory;
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
        MainMode.lumen: ModeState(submode: 'ticker'),
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
    );
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
