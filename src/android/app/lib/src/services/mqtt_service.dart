import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../contract/topics.dart';

/// A raw MQTT message from the broker.
typedef BorgMessage = ({String topic, String payload});

/// Thin wrapper around mqtt_client: plain MQTT (no TLS, project decision),
/// auto-reconnect, one broadcast stream of all `balkon/#` messages.
/// Interpretation of payloads lives in AppState, not here.
class MqttService {
  MqttService();

  MqttServerClient? _client;
  final _messages = StreamController<BorgMessage>.broadcast();
  final _connected = StreamController<bool>.broadcast();

  Stream<BorgMessage> get messages => _messages.stream;
  Stream<bool> get connectionChanges => _connected.stream;
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    await disconnect();

    final client = MqttServerClient.withPort(
        host, 'balkon-borg-app-${DateTime.now().millisecondsSinceEpoch}', port)
      ..keepAlivePeriod = 30
      ..autoReconnect = true
      ..resubscribeOnAutoReconnect = true;
    client.onConnected = () => _connected.add(true);
    client.onDisconnected = () => _connected.add(false);
    client.onAutoReconnected = () => _connected.add(true);
    _client = client;

    try {
      final status = await client.connect(username, password);
      if (status?.state != MqttConnectionState.connected) return false;
    } on Exception {
      client.disconnect();
      return false;
    }

    client.subscribe(Topics.subscription, MqttQos.atLeastOnce);
    client.updates?.listen(_onUpdates);
    return true;
  }

  void _onUpdates(List<MqttReceivedMessage<MqttMessage>> batch) {
    for (final rec in batch) {
      final msg = rec.payload;
      if (msg is! MqttPublishMessage) continue;
      final payload =
          MqttPublishPayload.bytesToStringAsString(msg.payload.message);
      _messages.add((topic: rec.topic, payload: payload));
    }
  }

  /// Publish a JSON command (QoS 1, not retained; the state echo is the ack).
  void publishJson(String topic, Map<String, dynamic> body) {
    final client = _client;
    if (client == null || !isConnected) return;
    final builder = MqttClientPayloadBuilder()
      ..addUTF8String(jsonEncode({'v': 1, ...body}));
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  Future<void> disconnect() async {
    _client?.disconnect();
    _client = null;
  }
}
