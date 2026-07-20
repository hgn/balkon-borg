/// The MQTT/HTTP interface contract, mirrored from `src/shared/README.md`.
/// That file is authoritative; keep this in sync with it.
library;

/// Main modes, also path segments in mode/cmd topics.
enum MainMode { lumen, comms, sigint, sentry }

abstract final class Topics {
  // State (retained, borgd-owned).
  static String mode(MainMode m) => 'balkon/mode/${m.name}';
  static const modeFocus = 'balkon/mode/focus';
  static const stateKnob = 'balkon/state/knob';

  // Commands (fire-and-forget; the state topic echo is the ack).
  static String cmdMode(MainMode m) => 'balkon/cmd/mode/${m.name}';
  static const cmdFocus = 'balkon/cmd/focus';
  static const cmdBrightness = 'balkon/cmd/brightness';
  static const cmdVolume = 'balkon/cmd/volume';

  // Health (retained).
  static const health = 'balkon/health';
  static const healthPrefix = 'balkon/health/';

  // Events (event/recent is the retained ring the watch window diffs against).
  static const eventRecent = 'balkon/event/recent';
  static const eventPrefix = 'balkon/event/';

  // Telemetry / feeds.
  static const envRecent = 'balkon/env/recent';
  static const presence = 'balkon/presence';

  /// Retained sky snapshot from readsb, republished ~1/s while ADS-B runs
  /// (`src/shared/README.md`, decisions log 2026-07-19): `{"v":1,"ts":…,
  /// "aircraft":[…nearest first]}`. `models/aircraft.dart` parses it.
  static const adsbAircraft = 'balkon/adsb/aircraft';

  // Media pointers (retained).
  static const noaaImage = 'balkon/noaa/image';
  static const sstvImage = 'balkon/iss/sstv/image';
  static const timelapseVideo = 'balkon/timelapse/video';

  /// Everything the app subscribes to.
  static const subscription = 'balkon/#';
}

/// Balcony coordinates, used to fall back to client-side great-circle math
/// (`models/aircraft.dart`'s `GreatCircle`) when `balkon/adsb/aircraft`
/// carries `lat`/`lon` but no `dist_km`/`bearing_deg`. Munich Laim, read off
/// a map — an approximation, not surveyed; moves to app settings/borgd
/// config once the real balcony position matters for more than a radar
/// picture (decisions log 2026-07-19).
abstract final class BorgGeo {
  static const homeLat = 48.1372;
  static const homeLon = 11.5000;
}

abstract final class BorgHttp {
  /// Default host; overridable in the app settings.
  static const defaultHost = 'borg-pi';
  static const defaultMqttPort = 1883;

  static Uri statusPage(String host) => Uri.http(host, '/');
  static Uri healthJson(String host) => Uri.http(host, '/health.json');
  static Uri talkdown(String host) => Uri.http(host, '/api/talkdown');
  static Uri apkVersion(String host) => Uri.http(host, '/apk/version.json');

  /// go2rtc MJPEG fallback; the primary live-view path is WebRTC (flutter_webrtc).
  static Uri liveMjpeg(String host) =>
      Uri.http('$host:1984', '/api/stream.mjpeg', {'src': 'cam'});
}
