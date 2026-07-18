import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/borg_event.dart';

/// Thin wrapper around `flutter_local_notifications` for the watch-window's
/// event notifications. Deliberately isolate-agnostic: `WatchWindowTaskHandler`
/// (services/watch_window.dart) runs in the foreground-task's background
/// isolate and calls this the same way the main isolate would — each isolate
/// gets its own `FlutterLocalNotificationsPlugin` instance (a plain platform-
/// channel client), initialized lazily on first use.
class EventNotifications {
  EventNotifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const _channelId = 'balkon_events';
  static const _channelName = 'Balkon-Ereignisse';
  static const _channelDescription = 'Neue Ereignisse aus balkon/event/recent';

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(settings: const InitializationSettings(android: androidInit));
    _initialized = true;
  }

  /// Shows one notification for [event]. `id` is derived from the event's
  /// timestamp + text so re-delivery of the exact same event (should never
  /// happen given `EventDiffer`, but harmless if it does) collapses instead
  /// of stacking duplicate notifications.
  static Future<void> show(BorgEvent event) async {
    await _ensureInitialized();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    await _plugin.show(
      id: Object.hash(event.ts, event.text) & 0x7fffffff,
      title: _titleFor(event.category),
      body: event.text,
      notificationDetails: details,
    );
  }

  static String _titleFor(EventCategory category) => switch (category) {
        EventCategory.aircraft => 'Tiefflug erkannt',
        EventCategory.bird => 'Vogel-Ereignis',
        EventCategory.storm => 'Sturmwarnung',
        EventCategory.security => 'SENTRY: Person erkannt',
        EventCategory.tpms => 'Reifensensor',
        EventCategory.other => 'Balkon-Borg Ereignis',
      };
}
