/// The kinds of sound the app makes, each switchable on its own in the
/// settings (the master `Settings.uiSoundsEnabled` still gates all of them).
///
/// Separate from `ui_sounds.dart` so `Settings` can persist per-class
/// preferences without the state layer depending on the audio service.
library;

enum SoundClass {
  /// Navigation and selection: tabs, chips, presets, cards, radar blips.
  navigation,

  /// State echo — borgd reporting that something really changed.
  confirm,

  /// The rare droid babble that answers a state echo instead of a chirp.
  /// Switchable on its own so the grammar can stay while the joke goes.
  droid,

  /// SENTRY arm/disarm.
  sentry,

  /// Push-to-talk: key-down click and the send acknowledgement.
  ptt,

  /// Something failed (a talkdown that did not go out).
  error,

  /// The boot underscore under the radar animation.
  boot,
}
