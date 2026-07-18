/// Push-to-talk recording (E4, docs/use-cases.md §U21.2), abstracted behind
/// a small interface so the Camera screen's widget tests don't have to touch
/// the real `record` plugin channel (which needs a live platform binding).
/// [PackageTalkdownRecorder] is the production implementation; tests inject
/// a fake.
library;

import 'dart:io';

import 'package:record/record.dart';

abstract class TalkdownRecorder {
  /// Checks — and, per the `record` package's own API, requests — the
  /// RECORD_AUDIO runtime permission. No separate permission_handler
  /// dependency needed, `record` already exposes this.
  Future<bool> hasPermission();

  /// Starts recording to an implementation-owned temp file.
  Future<void> start();

  /// Stops recording; returns the recorded file's path, or null if nothing
  /// was recorded.
  Future<String?> stop();

  /// Stops and discards the in-progress recording (PTT released via
  /// `onTapCancel` — an interrupted gesture, not a real release-to-send).
  Future<void> cancel();

  Future<void> dispose();
}

/// Real implementation backed by the `record` package.
///
/// **Format decision:** WAV (`AudioEncoder.wav`, PCM16 with headers) rather
/// than the package's default AAC/M4A — `src/shared/README.md`'s
/// `POST /api/talkdown` contract expects a WAV body, and the arbiter just
/// plays it back (no server-side transcoding). Mono is enough for a talk-down
/// clip and keeps the upload small (contract caps it at ~5 MB / 30 s).
class PackageTalkdownRecorder implements TalkdownRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  static const _config = RecordConfig(
    encoder: AudioEncoder.wav,
    numChannels: 1,
  );

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start() async {
    final dir = await Directory.systemTemp.createTemp('borg-talkdown-');
    await _recorder.start(_config, path: '${dir.path}/talkdown.wav');
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}
