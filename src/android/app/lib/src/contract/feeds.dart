/// Additional MQTT topics outside the arbiter-owned contract in `topics.dart`
/// (`src/shared/README.md` is authoritative there). This file holds feeds
/// published directly by a component rather than the arbiter.
library;

abstract final class Feeds {
  /// Published directly by BirdNET-Go, one message per detection, in
  /// BirdNET-Go's **native** payload schema — not yet pinned in
  /// `src/shared/README.md` (planned for Pi stage M4). `BirdDetection.fromJson`
  /// parses it defensively until then.
  static const birdDetections = 'balkon/birds/detections';

  /// WLED's own built-in MQTT status topic (`<mqttDeviceTopic>/v`, WLED's
  /// "verbose state" JSON), read directly for the ambient glow (E9). Not
  /// under `balkon/*` — the ESP/WLED integration publishes its native
  /// on/bri/seg payload here independently of the arbiter contract; the
  /// arbiter still owns brightness *commands* via `balkon/cmd/brightness`.
  /// `parseWledColor` (`models/wled_state.dart`) parses it defensively.
  static const wledState = 'wled/balkon/v';
}
