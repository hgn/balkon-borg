import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

import '../contract/feeds.dart';
import '../contract/topics.dart';
import '../models/bird_detection.dart';
import '../models/borg_event.dart';
import '../models/env_sample.dart';
import '../models/health.dart';
import '../models/mode_state.dart';
import '../models/wled_state.dart';
import '../services/demo_source.dart';
import '../services/haptics.dart';
import '../services/mqtt_service.dart';
import 'settings.dart';

/// Worst-of summary for the header health dot.
enum AggregateHealth { unknown, ok, degraded, bad }

/// Central app state: interprets the MQTT contract into typed state and
/// exposes commands. Renders only what the arbiter echoes back — no
/// optimistic UI (contract convention: the state topic is the ack).
///
/// Feeds from either the real broker (`MqttService`) or `DemoSource`
/// (`Settings.demoMode`, D2); `connect()` picks the source and re-runs
/// whenever the setting flips at runtime.
class AppState extends ChangeNotifier {
  /// [haptics] is injectable (tests pass a recording fake); defaults to the
  /// real `HapticFeedback`-backed implementation, gated by
  /// `Settings.hapticsEnabled`.
  AppState(this._mqtt, this._settings, {Haptics? haptics})
      : _haptics = haptics ?? SystemHaptics(() => _settings.hapticsEnabled) {
    _sub = _mqtt.messages.listen(_onMessage);
    _connSub = _mqtt.connectionChanges.listen((up) {
      connected = up;
      notifyListeners();
    });
    _settings.addListener(_onSettingsChanged);
  }

  final MqttService _mqtt;
  final Settings _settings;
  final Haptics _haptics;
  final DemoSource _demo = const DemoSource();
  StreamSubscription<BorgMessage>? _sub;
  StreamSubscription<bool>? _connSub;
  bool _demoActive = false;

  bool connected = false;
  final Map<MainMode, ModeState> modes = {};
  MainMode? focus;
  final Map<String, CapabilityHealth> health = {};
  String healthSummary = '';
  List<BorgEvent> recentEvents = [];
  List<EnvSample> envHistory = [];
  List<BirdDetection> birdLog = [];

  /// Current WLED light color for the ambient background glow (E9), `null`
  /// while off/unknown. Fed by `wled/balkon/v` (`Feeds.wledState`) in real
  /// mode, by `DemoSource`/the LUMEN-submode demo mutation in demo mode.
  Color? wledColor;

  /// Cap for [birdLog]: BirdNET-Go publishes one message per detection (no
  /// retained ring like `event/recent`), so the app accumulates it itself.
  static const _birdLogCap = 100;

  /// Today's most-detected species (see [BirdOfDay.fromLog] for the
  /// tie-break rule); `null` if nothing was detected today.
  BirdOfDay? get birdOfDay => BirdOfDay.fromLog(birdLog);

  /// Worst-of health summary for the header dot: grey (unknown) while
  /// disconnected or before any health data arrived.
  AggregateHealth get aggregateHealth {
    if (!connected || health.isEmpty) return AggregateHealth.unknown;
    final states = health.values.map((c) => c.state);
    if (states.contains(HealthState.missing)) return AggregateHealth.bad;
    if (states.contains(HealthState.degraded)) return AggregateHealth.degraded;
    return AggregateHealth.ok;
  }

  Future<void> connect() async {
    if (_settings.demoMode) {
      await _mqtt.disconnect();
      _demoActive = true;
      final snapshot = _demo.build();
      modes
        ..clear()
        ..addAll(snapshot.modes);
      focus = snapshot.focus;
      health
        ..clear()
        ..addAll(snapshot.health);
      healthSummary = snapshot.healthSummary;
      recentEvents = snapshot.events;
      envHistory = snapshot.envHistory;
      birdLog = snapshot.birdLog;
      wledColor = snapshot.wledColor;
      connected = true;
      notifyListeners();
      return;
    }
    _demoActive = false;
    connected = await _mqtt.connect(
      host: _settings.host,
      port: _settings.port,
      username: _settings.username,
      password: _settings.password,
    );
    notifyListeners();
  }

  void _onSettingsChanged() {
    if (_settings.demoMode != _demoActive) {
      connect();
    }
  }

  void _onMessage(BorgMessage msg) {
    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(msg.payload);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } on FormatException {
      return; // Non-JSON payloads (ESPHome plain numbers) are not ours here.
    }

    final topic = msg.topic;
    for (final m in MainMode.values) {
      if (topic == Topics.mode(m)) {
        _applyModeUpdate(m, ModeState.fromJson(json));
        notifyListeners();
        return;
      }
    }
    if (topic == Topics.modeFocus) {
      final f = json['focus'] as String?;
      focus = MainMode.values.where((m) => m.name == f).firstOrNull;
    } else if (topic == Topics.health) {
      healthSummary = json['summary'] as String? ?? '';
    } else if (topic.startsWith(Topics.healthPrefix)) {
      health[topic.substring(Topics.healthPrefix.length)] =
          CapabilityHealth.fromJson(json);
    } else if (topic == Topics.eventRecent) {
      final parsed = BorgEvent.tryParseRing(json);
      if (parsed != null) recentEvents = parsed;
    } else if (topic == Topics.envRecent) {
      final list = json['samples'];
      if (list is List) {
        envHistory = [
          for (final e in list)
            if (e is Map<String, dynamic>) EnvSample.fromJson(e),
        ];
      }
    } else if (topic == Feeds.birdDetections) {
      // BirdNET-Go publishes one detection per message, not a batch/ring
      // like `event/recent` — accumulate locally, newest first, capped.
      birdLog = [BirdDetection.fromJson(json), ...birdLog];
      if (birdLog.length > _birdLogCap) {
        birdLog = birdLog.sublist(0, _birdLogCap);
      }
    } else if (topic == Feeds.wledState) {
      wledColor = parseWledColor(json);
    } else {
      return;
    }
    notifyListeners();
  }

  // Commands — fire-and-forget; the retained state echo updates the UI. In
  // demo mode there is no arbiter to echo the state topic back, so the
  // change is additionally applied straight to local state (E2) — real mode
  // relies solely on the echo, no optimistic UI (contract convention).
  void setSubmode(MainMode m, String submode, {String? chan}) {
    _mqtt.publishJson(Topics.cmdMode(m), {
      'submode': submode,
      'chan': ?chan,
    });
    if (_demoActive) {
      _applyModeUpdate(
        m,
        ModeState(submode: submode, chan: chan, pinned: modes[m]?.pinned ?? false),
      );
      // No real WLED to echo `wled/balkon/v` back in demo mode — mirror the
      // LUMEN submode into a plausible glow color ourselves (E9).
      if (m == MainMode.lumen) wledColor = _demo.colorForLumenSubmode(submode);
      notifyListeners();
    }
  }

  /// Applies an incoming/demo [ModeState] for [m], firing the "state-echo
  /// confirmation" haptic (E8, implementation-plan.md) iff the submode or
  /// channel actually changed — a retained message republishing the same
  /// value stays silent, and so does the *initial* population (`prev ==
  /// null`): on connect the broker delivers four retained mode messages at
  /// once, and buzzing four times on app start is startup noise, not a
  /// confirmation of anything the user did. Compares old vs new *before*
  /// mutating, per spec.
  void _applyModeUpdate(MainMode m, ModeState next) {
    final prev = modes[m];
    final changed =
        prev != null && (prev.submode != next.submode || prev.chan != next.chan);
    modes[m] = next;
    if (changed) _haptics.mediumImpact();
  }

  void setFocus(MainMode m) =>
      _mqtt.publishJson(Topics.cmdFocus, {'focus': m.name});

  void setBrightness(int value) =>
      _mqtt.publishJson(Topics.cmdBrightness, {'value': value.clamp(0, 255)});

  void setVolume(int value) =>
      _mqtt.publishJson(Topics.cmdVolume, {'value': value.clamp(0, 100)});

  @override
  void dispose() {
    _sub?.cancel();
    _connSub?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _mqtt.disconnect();
    super.dispose();
  }
}
