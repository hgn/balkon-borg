import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../contract/topics.dart';
import '../models/borg_event.dart';

/// User settings, persisted via shared_preferences.
class Settings extends ChangeNotifier {
  Settings(this._prefs);

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  // Broker.
  String get host => _prefs.getString('host') ?? BorgHttp.defaultHost;
  int get port => _prefs.getInt('port') ?? BorgHttp.defaultMqttPort;
  String get username => _prefs.getString('username') ?? 'app';
  String get password => _prefs.getString('password') ?? '';

  // Theme (E1): dark is the native/default tone, light is user-selectable
  // via the header toggle pill (binary — no "system" option in the design).
  ThemeMode get themeMode =>
      _prefs.getString('theme_mode') == 'light' ? ThemeMode.light : ThemeMode.dark;

  // Demo mode (D2): feeds AppState with realistic fake data instead of the
  // real MQTT broker. Default on until the Pi broker (M1) exists.
  bool get demoMode => _prefs.getBool('demo_mode') ?? true;

  // Watch window (self-wake notification model, src/shared/README.md):
  // any app use arms 6 h of periodic MQTT checks; interval is configurable.
  static const watchWindow = Duration(hours: 6);
  Duration get checkInterval =>
      Duration(seconds: _prefs.getInt('check_interval_s') ?? 30);

  /// Per-category notification toggles; security defaults on, the rest off.
  bool notify(EventCategory c) =>
      _prefs.getBool('notify_${c.name}') ?? (c == EventCategory.security);

  Future<void> setBroker({
    String? host,
    int? port,
    String? username,
    String? password,
  }) async {
    if (host != null) await _prefs.setString('host', host);
    if (port != null) await _prefs.setInt('port', port);
    if (username != null) await _prefs.setString('username', username);
    if (password != null) await _prefs.setString('password', password);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('theme_mode', mode == ThemeMode.light ? 'light' : 'dark');
    notifyListeners();
  }

  Future<void> setDemoMode(bool on) async {
    await _prefs.setBool('demo_mode', on);
    notifyListeners();
  }

  Future<void> setCheckInterval(Duration d) async {
    await _prefs.setInt('check_interval_s', d.inSeconds);
    notifyListeners();
  }

  Future<void> setNotify(EventCategory c, bool on) async {
    await _prefs.setBool('notify_${c.name}', on);
    notifyListeners();
  }
}
