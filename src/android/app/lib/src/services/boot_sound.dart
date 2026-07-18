/// Boot underscore playback (E8, implementation-plan.md), abstracted behind a
/// small interface so `BootOverlay`'s widget tests don't have to touch the
/// real `audioplayers` plugin channel (which needs a live platform binding).
/// [PackageBootSound] is the production implementation; tests inject a fake.
library;

import 'package:audioplayers/audioplayers.dart';

abstract class BootSound {
  /// Fire-and-forget playback of the boot underscore. Must never throw —
  /// implementations are responsible for swallowing playback failures
  /// (missing plugin, decode error, etc.) themselves.
  Future<void> play();

  Future<void> dispose();
}

/// Real implementation backed by `package:audioplayers`, playing the bundled
/// `assets/audio/start.wav` asset.
class PackageBootSound implements BootSound {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play() async {
    try {
      await _player.play(AssetSource('audio/start.wav'));
    } catch (_) {
      // Any playback failure (missing plugin on host, decode error, etc.) is
      // silently ignored — the boot sequence must never depend on audio.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {
      // Same rationale as play(): never let cleanup throw into the widget tree.
    }
  }
}
