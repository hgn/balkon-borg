import 'package:flutter/material.dart';

import '../../contract/topics.dart';
import '../../theme/balkon_theme.dart';

/// Brief notice that starting [mode] took the single RTL-SDR away from the
/// other radio mode (architecture.md §3/§4). Shown wherever a COMMS or SIGINT
/// program can be started: the Radio tab and the Home submode sheet.
///
/// Displacement itself is `AppState.setSubmodeExclusive`; this is only how the
/// UI says it out loud, so the light going out on the other card does not look
/// like a glitch.
void showTunerNotice(BuildContext context, MainMode mode) {
  final extras = Theme.of(context).extension<BalkonExtras>()!;
  final message =
      mode == MainMode.comms ? 'SIGINT pausiert · ein Tuner' : 'COMMS pausiert · ein Tuner';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: extras.surface3,
      duration: const Duration(seconds: 2),
      content: Text(message, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}
