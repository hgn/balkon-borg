import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../contract/topics.dart';
import '../models/borg_event.dart';
import '../models/env_sample.dart';
import '../models/health.dart';
import '../models/mode_state.dart';
import '../services/demo_source.dart';
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
  AppState(this._mqtt, this._settings) {
    _sub = _mqtt.messages.listen(_onMessage);
    _connSub = _mqtt.connectionChanges.listen((up) {
      connected = up;
      notifyListeners();
    });
    _settings.addListener(_onSettingsChanged);
  }

  final MqttService _mqtt;
  final Settings _settings;
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
        modes[m] = ModeState.fromJson(json);
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
      final list = json['events'];
      if (list is List) {
        recentEvents = [
          for (final e in list)
            if (e is Map<String, dynamic>) BorgEvent.fromJson(e),
        ];
      }
    } else if (topic == Topics.envRecent) {
      final list = json['samples'];
      if (list is List) {
        envHistory = [
          for (final e in list)
            if (e is Map<String, dynamic>) EnvSample.fromJson(e),
        ];
      }
    } else {
      return;
    }
    notifyListeners();
  }

  // Commands — fire-and-forget; the retained state echo updates the UI.
  void setSubmode(MainMode m, String submode, {String? chan}) =>
      _mqtt.publishJson(Topics.cmdMode(m), {
        'submode': submode,
        'chan': ?chan,
      });

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
