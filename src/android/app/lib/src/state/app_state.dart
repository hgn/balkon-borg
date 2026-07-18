import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../contract/topics.dart';
import '../models/borg_event.dart';
import '../models/health.dart';
import '../models/mode_state.dart';
import '../services/mqtt_service.dart';
import 'settings.dart';

/// Central app state: interprets the MQTT contract into typed state and
/// exposes commands. Renders only what the arbiter echoes back — no
/// optimistic UI (contract convention: the state topic is the ack).
class AppState extends ChangeNotifier {
  AppState(this._mqtt, this._settings) {
    _sub = _mqtt.messages.listen(_onMessage);
    _connSub = _mqtt.connectionChanges.listen((up) {
      connected = up;
      notifyListeners();
    });
  }

  final MqttService _mqtt;
  final Settings _settings;
  StreamSubscription<BorgMessage>? _sub;
  StreamSubscription<bool>? _connSub;

  bool connected = false;
  final Map<MainMode, ModeState> modes = {};
  MainMode? focus;
  final Map<String, CapabilityHealth> health = {};
  String healthSummary = '';
  List<BorgEvent> recentEvents = [];

  Future<void> connect() async {
    connected = await _mqtt.connect(
      host: _settings.host,
      port: _settings.port,
      username: _settings.username,
      password: _settings.password,
    );
    notifyListeners();
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
    _mqtt.disconnect();
    super.dispose();
  }
}
