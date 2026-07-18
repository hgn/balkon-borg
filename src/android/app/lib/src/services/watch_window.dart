import 'dart:async';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contract/topics.dart';
import '../models/borg_event.dart';
import '../state/settings.dart';
import 'event_differ.dart';
import 'local_notifications.dart';
import 'mqtt_service.dart';

/// The self-wake watch-window model (`src/shared/README.md` "Notification
/// model — no push server"): any app use arms a 6 h window; while armed, a
/// foreground service wakes up every `Settings.checkInterval`, connects to
/// MQTT just long enough to read the retained `balkon/event/recent` ring,
/// diffs it with [EventDiffer], and raises local notifications for newly
/// arrived events in enabled categories. After 6 h without a re-arm the
/// service stops itself — zero background work until the next app use.
///
/// Split from `AppState`/UI on purpose: `WatchWindowTaskHandler` below runs
/// in `flutter_foreground_task`'s background isolate, which does not share
/// memory (or a `BuildContext`/`Provider` tree) with the main isolate. It
/// re-derives everything it needs (`Settings`, a fresh `MqttService`) from
/// `SharedPreferences`/the broker itself instead.
enum WatchWindowArmResult { armed, demoMode, permissionDenied, failed }

const _serviceId = 4242;
const _stopButtonId = 'stop';
const _lastSeenKey = 'watch_window_last_seen_ms';

class WatchWindowService {
  const WatchWindowService();

  /// Arms (or re-arms, extending back to the full 6 h) the watch window.
  /// In demo mode this is a documented no-op (E6 scope: "there is no real
  /// broker") — callers show a hint instead of pretending to watch nothing.
  Future<WatchWindowArmResult> arm(Settings settings) async {
    if (settings.demoMode) return WatchWindowArmResult.demoMode;

    try {
      FlutterForegroundTask.initCommunicationPort();

      var permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        permission = await FlutterForegroundTask.requestNotificationPermission();
      }
      if (permission != NotificationPermission.granted) {
        return WatchWindowArmResult.permissionDenied;
      }

      final until = DateTime.now().add(Settings.watchWindow);
      await settings.setWatchWindowArmedUntil(until);

      final taskOptions = ForegroundTaskOptions(
        // 30 s (or whatever the user picked) via a foreground-service repeat
        // timer is the honest choice here: Android foreground services keep
        // running (and their timers keep firing close to on-schedule) while
        // the process is alive, which is exactly what this needs for a
        // bounded 6 h window. AlarmManager-based exact scheduling would add
        // real complexity (exact-alarm permission, doze/battery-optimization
        // edge cases) for a check interval this short — not worth it here.
        eventAction: ForegroundTaskEventAction.repeat(settings.checkInterval.inMilliseconds),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      );

      // `init` just (re)sets the static options the plugin reads from at
      // start/update time — cheap and safe to call on every arm, so a
      // changed check interval always takes effect whether this call starts
      // a fresh service or (the common case: app resume within an existing
      // window) updates the one already running.
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'watch_window',
          channelName: 'Watch-Window',
          channelDescription: 'Zeigt an, wenn Balkon-Borg im Hintergrund auf Ereignisse achtet.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: taskOptions,
      );

      final running = await FlutterForegroundTask.isRunningService;
      final result = running
          ? await FlutterForegroundTask.updateService(
              notificationText: _notificationText(until),
              foregroundTaskOptions: taskOptions,
            )
          : await FlutterForegroundTask.startService(
              serviceId: _serviceId,
              notificationTitle: 'Borg wacht',
              notificationText: _notificationText(until),
              notificationButtons: const [
                NotificationButton(id: _stopButtonId, text: 'Beenden'),
              ],
              callback: startWatchWindowTask,
            );

      return result is ServiceRequestSuccess
          ? WatchWindowArmResult.armed
          : WatchWindowArmResult.failed;
    } on Exception {
      return WatchWindowArmResult.failed;
    }
  }

  /// Explicit disarm (not currently wired to any UI action beyond the
  /// notification's own "Beenden" button, which the task handler handles
  /// itself — kept here too since a manual settings action is a natural
  /// follow-up and this is the one place that knows how).
  Future<void> disarm(Settings settings) async {
    await settings.setWatchWindowArmedUntil(null);
    try {
      await FlutterForegroundTask.stopService();
    } on Exception {
      // Not running — fine, that's the desired end state either way.
    }
  }

  static String _notificationText(DateTime until) => 'bis ${_hhmm(until)}';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Entry point for the background isolate (must be top-level, per
/// flutter_foreground_task's contract).
@pragma('vm:entry-point')
void startWatchWindowTask() {
  FlutterForegroundTask.setTaskHandler(WatchWindowTaskHandler());
}

/// Runs entirely in the foreground-task background isolate: no
/// `BuildContext`, no `Provider`, no shared Dart state with the app's main
/// isolate — everything is re-read from `SharedPreferences`/MQTT each tick.
class WatchWindowTaskHandler extends TaskHandler {
  MqttService? _mqtt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_check(timestamp));
  }

  Future<void> _check(DateTime timestamp) async {
    final settings = await Settings.load();
    final armedUntil = settings.watchWindowArmedUntil;
    if (armedUntil == null || timestamp.isAfter(armedUntil) || settings.demoMode) {
      await FlutterForegroundTask.stopService();
      return;
    }

    final mqtt = _mqtt ??= MqttService();
    try {
      final connected = await mqtt.connect(
        host: settings.host,
        port: settings.port,
        username: settings.username,
        password: settings.password,
      );
      if (!connected) return;

      final ring = await _readEventRing(mqtt);
      if (ring == null) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSeenMs = prefs.getInt(_lastSeenKey);
      final lastSeen = lastSeenMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSeenMs);

      const differ = EventDiffer();
      final toNotify = differ.diff(ring: ring, lastSeen: lastSeen, isEnabled: settings.notify);
      // Oldest-of-the-new first, so a burst of events shows up in the
      // notification shade in the order they happened.
      for (final event in toNotify.reversed) {
        await EventNotifications.show(event);
      }

      final next = differ.nextLastSeen(ring: ring, lastSeen: lastSeen);
      if (next != null && next != lastSeen) {
        await prefs.setInt(_lastSeenKey, next.millisecondsSinceEpoch);
      }
    } finally {
      await mqtt.disconnect();
    }
  }

  /// Connects just long enough to catch the retained `balkon/event/recent`
  /// message, then returns. `null` on timeout (broker reachable but the
  /// retained message never arrived — treated the same as "nothing new").
  Future<List<BorgEvent>?> _readEventRing(MqttService mqtt) async {
    final completer = Completer<String?>();
    final sub = mqtt.messages.listen((msg) {
      if (msg.topic == Topics.eventRecent && !completer.isCompleted) {
        completer.complete(msg.payload);
      }
    });
    final payload = await completer.future
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    await sub.cancel();
    if (payload == null) return null;

    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    return BorgEvent.tryParseRing(decoded) ?? const <BorgEvent>[];
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _mqtt?.disconnect();
    final settings = await Settings.load();
    await settings.setWatchWindowArmedUntil(null);
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == _stopButtonId) {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
