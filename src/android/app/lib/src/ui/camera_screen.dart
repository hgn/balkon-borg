import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../contract/submodes.dart';
import '../contract/topics.dart';
import '../models/mode_state.dart';
import '../services/talkdown_recorder.dart';
import '../state/app_state.dart';
import '../state/settings.dart';
import '../theme/balkon_theme.dart';
import 'widgets/borg_chip.dart';
import 'widgets/ptt_button.dart';
import 'widgets/sentry_switch.dart';

/// Camera tab (components.md "Live-Kamera" / "SENTRY-Karte" / "Push-to-Talk
/// Button" / "Chips"; implementation-plan.md E4; docs/use-cases.md §U11/§U21).
/// One scrolling column: live view, SENTRY arm card, push-to-talk, voice
/// effect chips. WebRTC live view is deferred (plan D5) — this stage wires
/// only the MJPEG fallback attempt.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.recorder});

  /// Injectable for widget tests: defaults to the real `record`-backed
  /// implementation; tests pass a fake so nothing touches the microphone
  /// plugin channel.
  final TalkdownRecorder? recorder;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final TalkdownRecorder _recorder = widget.recorder ?? PackageTalkdownRecorder();

  bool _recording = false;
  Timer? _autoStopTimer;
  String _voiceEffect = 'normal';

  // Contract cap, `src/shared/README.md`: "POST /api/talkdown — body: WAV
  // (<= ~30 s, <= 5 MB)".
  static const _maxRecording = Duration(seconds: 30);

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = context.watch<Settings>();
    final sentryState = state.modes[MainMode.sentry] ?? const ModeState(submode: 'off');

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        _LiveCameraArea(demoMode: settings.demoMode, host: settings.host),
        const SizedBox(height: 22),
        _SentryCard(state: sentryState),
        const SizedBox(height: 28),
        Center(
          child: PttButton(
            held: _recording,
            onTapDown: (_) => unawaited(_startRecording()),
            onTapUp: (_) => _finishRecording(),
            onTapCancel: _cancelRecording,
          ),
        ),
        const SizedBox(height: 14),
        _VoiceEffectRow(
          selected: _voiceEffect,
          onSelect: (id) => setState(() => _voiceEffect = id),
        ),
      ],
    );
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    final granted = await _recorder.hasPermission();
    if (!mounted || !granted) return;
    await _recorder.start();
    if (!mounted) return;
    setState(() => _recording = true);
    _autoStopTimer = Timer(_maxRecording, _finishRecording);
  }

  /// Release-to-send (`onTapUp`): stops the recording and uploads it.
  void _finishRecording() {
    _autoStopTimer?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);

    // Snapshot everything context-derived now — the upload runs in the
    // background (fire-and-forget per the task spec) and must not touch
    // `context` after the `await` below.
    final settings = context.read<Settings>();
    final messenger = ScaffoldMessenger.of(context);
    final textStyle = Theme.of(context).textTheme.bodyLarge;
    final snackColor = Theme.of(context).extension<BalkonExtras>()!.surface3;

    unawaited(_stopAndSend(
      demoMode: settings.demoMode,
      host: settings.host,
      messenger: messenger,
      textStyle: textStyle,
      snackColor: snackColor,
    ));
  }

  /// Interrupted gesture (`onTapCancel`): stop and discard, no upload.
  void _cancelRecording() {
    _autoStopTimer?.cancel();
    if (!_recording) return;
    setState(() => _recording = false);
    unawaited(_recorder.cancel());
  }

  Future<void> _stopAndSend({
    required bool demoMode,
    required String host,
    required ScaffoldMessengerState messenger,
    required TextStyle? textStyle,
    required Color snackColor,
  }) async {
    final path = await _recorder.stop();
    if (path == null) return;

    if (demoMode) {
      _snack(messenger, textStyle, snackColor, 'Demo — nicht gesendet');
      return;
    }

    try {
      final bytes = await File(path).readAsBytes();
      final response = await http.post(
        BorgHttp.talkdown(host),
        headers: const {'Content-Type': 'audio/wav'},
        body: bytes,
      );
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      _snack(messenger, textStyle, snackColor, ok ? 'Gesendet' : 'Fehlgeschlagen — borg-pi offline?');
    } catch (_) {
      _snack(messenger, textStyle, snackColor, 'Fehlgeschlagen — borg-pi offline?');
    }
  }

  void _snack(ScaffoldMessengerState messenger, TextStyle? style, Color background, String text) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: background,
        duration: const Duration(seconds: 2),
        content: Text(text, style: style),
      ),
    );
  }
}

/// Live camera area (components.md "Live-Kamera"): 220px, radius 26, border
/// outline, `surface` background. Demo mode shows a stylized placeholder
/// (skips the network attempt entirely); otherwise attempts the go2rtc MJPEG
/// fallback (`BorgHttp.liveMjpeg`) with a graceful offline placeholder.
class _LiveCameraArea extends StatefulWidget {
  const _LiveCameraArea({required this.demoMode, required this.host});

  final bool demoMode;
  final String host;

  @override
  State<_LiveCameraArea> createState() => _LiveCameraAreaState();
}

class _LiveCameraAreaState extends State<_LiveCameraArea> {
  bool _rendering = false;

  /// Called from `Image`'s frameBuilder/errorBuilder — i.e. during a build —
  /// so any state change defers to after the frame.
  void _setRendering(bool value) {
    if (_rendering == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _rendering = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    // Demo mode fakes a live-looking feed; real mode only pulses once a
    // stream frame has actually rendered.
    final pulsing = widget.demoMode || _rendering;

    return Container(
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: extras.surface,
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(BalkonRadii.liveCamera),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.demoMode ? _demoPlaceholder(extras) : _mjpegAttempt(extras),
          Positioned(top: 12, left: 12, child: _LiveBadge(pulsing: pulsing)),
        ],
      ),
    );
  }

  Widget _demoPlaceholder(BalkonExtras extras) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [extras.surface3, extras.surface2],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.videocam_rounded, size: 40, color: extras.textDim),
    );
  }

  Widget _mjpegAttempt(BalkonExtras extras) {
    final url = BorgHttp.liveMjpeg(widget.host).toString();
    return Image.network(
      url,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) _setRendering(true);
        return child;
      },
      errorBuilder: (context, error, stack) {
        _setRendering(false);
        return _offlinePlaceholder(extras);
      },
    );
  }

  Widget _offlinePlaceholder(BalkonExtras extras) {
    return Container(
      color: extras.surface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, size: 36, color: extras.textDim.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            'Kein Stream — borg-pi offline?',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Manrope', fontSize: 12, fontWeight: FontWeight.w600, color: extras.textDim),
          ),
        ],
      ),
    );
  }
}

/// LIVE indicator overlay (components.md): 6px dot in `danger` + "LIVE"
/// label, pulsing (motion.md `pulseDot`, 1400ms) only while [pulsing].
class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.pulsing});

  final bool pulsing;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final Animation<double> _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _LiveBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !oldWidget.pulsing) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && oldWidget.pulsing) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extras = Theme.of(context).extension<BalkonExtras>()!;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = widget.pulsing ? _pulse.value : 0.0;
        final opacity = 1 - t * 0.65; // pulseDot: opacity 1 <-> .35
        final scale = 1 + t * 0.4; // pulseDot: scale 1 <-> 1.4
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(BalkonRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: opacity,
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: extras.danger, shape: BoxShape.circle),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'LIVE',
                style: TextStyle(fontFamily: 'Manrope', fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// SENTRY arm/disarm card (components.md "SENTRY-Karte").
class _SentryCard extends StatelessWidget {
  const _SentryCard({required this.state});

  final ModeState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final textTheme = Theme.of(context).textTheme;
    final armed = Submodes.sentryArmedSubmodes.contains(state.submode);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
      decoration: BoxDecoration(
        color: extras.surface2,
        borderRadius: BorderRadius.circular(BalkonRadii.sentryCard),
        // components.md: "Scharf-Zustand (dezent) ... kein Vollflächen-
        // Alarm, keine Puls-Animation auf der Karte selbst".
        border: Border.all(color: armed ? extras.danger.withValues(alpha: 0.45) : scheme.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SENTRY', style: textTheme.labelLarge?.copyWith(color: extras.textDim)),
                const SizedBox(height: 6),
                Text(_statusText(state.submode), style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SentrySwitch(
            armed: armed,
            onChanged: (wantArmed) => context.read<AppState>().setSubmode(
                  MainMode.sentry,
                  wantArmed ? 'armed' : 'off',
                ),
          ),
        ],
      ),
    );
  }

  /// Status line per SENTRY submode (docs/use-cases.md §U11 lifecycle:
  /// off · arming · armed · grace · alarm). Only `off`/`armed` exist in the
  /// wire contract today (`contract/submodes.dart`); `arming`/`grace`/`alarm`
  /// are handled defensively for when the arbiter starts sending them.
  String _statusText(String submode) => switch (submode) {
        'off' => 'Nicht scharf',
        'arming' => 'Scharfschaltung läuft…',
        'armed' => 'Scharf — Kamera bestätigt Personen',
        'grace' => 'Scharf — Zutritt erkannt, Entwaffnung möglich',
        'alarm' => 'Alarm — Person bestätigt',
        _ => Submodes.labelFor(MainMode.sentry, submode),
      };
}

/// Voice-effect chip row (components.md "Chips"; docs/use-cases.md §U21.3).
/// UI-state only for now — the client-side voice DSP is a later stage
/// (implementation-plan.md D5); selecting a chip just records the choice.
class _VoiceEffectRow extends StatelessWidget {
  const _VoiceEffectRow({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  static const _effects = [
    (id: 'normal', label: 'Normal'),
    (id: 'borg', label: 'Borg'),
    (id: 'megaphone', label: 'Megafon'),
    (id: 'pitch', label: 'Tief'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final effect in _effects)
          BorgChip(
            label: effect.label,
            selected: selected == effect.id,
            selectedBackground: scheme.primary,
            selectedForeground: Colors.white,
            onTap: () => onSelect(effect.id),
          ),
      ],
    );
  }
}
