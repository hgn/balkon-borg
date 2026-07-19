import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../services/condensation_gate.dart';
import '../../services/shader_library.dart';

/// Slow condensation/droplet wash on the app background above 85% relative
/// humidity (E11, implementation-plan.md D6): fine droplets with a faint
/// refractive shimmer, drifting downward very slowly. Barely-there by
/// design — a mood, not a foreground element (see the low alpha ceiling in
/// `shaders/condensation.frag`). Fades in/out (hysteresis via
/// [CondensationGate]: on >=85%, off again <82%, so a sensor hovering right
/// at the threshold does not flicker it).
///
/// Sits behind the app content in `shell.dart`'s `Stack`, same layer family
/// as `WledGlow`. Purely reactive to [humidity] (the caller hands in
/// `AppState.envHistory.last.h`, or `null` while there's no data yet).
///
/// Renders nothing when [enabled] is false, under
/// `MediaQuery.disableAnimations`, or when the shader failed to compile
/// ([ShaderLibrary.condensation] is `null`).
class CondensationOverlay extends StatefulWidget {
  const CondensationOverlay({super.key, required this.humidity, required this.enabled});

  final double? humidity;
  final bool enabled;

  @override
  State<CondensationOverlay> createState() => _CondensationOverlayState();
}

// `TickerProviderStateMixin`, not `SingleTickerProviderStateMixin`: this
// state drives two independent tickers — the `_fade` AnimationController
// and the raw drift `Ticker` for `uTime` — and the single-ticker mixin
// allows only one vended ticker per State.
class _CondensationOverlayState extends State<CondensationOverlay> with TickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 1500);

  final CondensationGate _gate = CondensationGate();
  late final AnimationController _fade = AnimationController(vsync: this, duration: _fadeDuration)
    ..addListener(_onFadeTick)
    ..addStatusListener(_onFadeStatus);

  Ticker? _ticker;
  Duration _elapsed = Duration.zero;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _sync();
  }

  @override
  void didUpdateWidget(covariant CondensationOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.humidity != widget.humidity || oldWidget.enabled != widget.enabled) _sync();
  }

  /// [CondensationGate.update] runs unconditionally (even while disabled or
  /// reduce-motion) so the hysteresis state always tracks the real humidity
  /// — flipping "Effekte" back on while already above threshold shows the
  /// wash immediately rather than waiting for a fresh crossing.
  void _sync() {
    final gateActive = _gate.update(widget.humidity);
    final visible = widget.enabled && !_reduceMotion && gateActive;
    if (visible) {
      if (_fade.status != AnimationStatus.completed) _fade.forward();
      if (_ticker == null) {
        _ticker = createTicker(_onTick)..start();
      } else if (!_ticker!.isActive) {
        _ticker!.start();
      }
    } else if (_fade.status != AnimationStatus.dismissed) {
      // Guarded (rather than an unconditional `reverse()`): `_sync` also
      // runs on every unrelated `didChangeDependencies` call (e.g. a theme
      // change) while the effect is already fully off, and re-issuing
      // `reverse()` on an idle controller would schedule a throwaway frame
      // each time — harmless, but needless churn for something that's
      // supposed to stay quiet.
      _fade.reverse();
    }
  }

  void _onTick(Duration elapsed) => setState(() => _elapsed = elapsed);

  void _onFadeTick() {
    if (mounted) setState(() {});
  }

  /// The drift ticker stops itself once the fade-out fully completes —
  /// nothing keeps repainting once the effect is fully invisible.
  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) _ticker?.stop();
  }

  @override
  void dispose() {
    _fade.dispose();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fade.status == AnimationStatus.dismissed) return const SizedBox.shrink();
    final program = context.read<ShaderLibrary>().condensation;
    if (program == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _CondensationPainter(
            program: program,
            intensity: _fade.value,
            time: _elapsed.inMilliseconds / 1000,
          ),
        ),
      ),
    );
  }
}

class _CondensationPainter extends CustomPainter {
  _CondensationPainter({required this.program, required this.intensity, required this.time});

  final ui.FragmentProgram program;
  final double intensity;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, intensity);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _CondensationPainter oldDelegate) =>
      oldDelegate.intensity != intensity || oldDelegate.time != time;
}
