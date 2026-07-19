import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/borg_event.dart';
import '../../services/sentry_glitch_trigger.dart';
import '../../services/shader_library.dart';

/// One-shot CRT interference pass over the camera view when SENTRY reports a
/// person (E11, implementation-plan.md D6): ~400ms of scanlines, tear bands
/// with a fake RGB fringe, and a short noise flicker, settling back to
/// normal. Once per event, never looping.
///
/// Trigger: a new `security`-category entry arriving in `recentEvents`
/// (`AppState.recentEvents`), not a SENTRY submode flip — the wire contract
/// only defines `off`/`armed` today (`models/mode_state.dart`), so the event
/// ring is the only signal that actually says "a person was reported" (see
/// `services/sentry_glitch_trigger.dart`).
///
/// Overlay-only (D6): paints on top of `_LiveCameraArea` via
/// `shaders/sentry-glitch.frag`, never samples it — no `AnimatedSampler`,
/// no per-frame subtree snapshot. Purely reactive to [recentEvents]: the
/// caller just keeps handing this widget the current ring on every rebuild.
///
/// Renders nothing (zero-cost `SizedBox.shrink`) when [enabled] is false,
/// under `MediaQuery.disableAnimations`, or when the shader failed to
/// compile ([ShaderLibrary.sentryGlitch] is `null`, looked up via
/// `Provider` — the loader service's contract for "no effect available").
class SentryGlitchOverlay extends StatefulWidget {
  const SentryGlitchOverlay({super.key, required this.recentEvents, required this.enabled});

  final List<BorgEvent> recentEvents;
  final bool enabled;

  @override
  State<SentryGlitchOverlay> createState() => _SentryGlitchOverlayState();
}

class _SentryGlitchOverlayState extends State<SentryGlitchOverlay> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 400);

  final SentryGlitchTrigger _trigger = SentryGlitchTrigger();

  // Assigned eagerly in `initState`, not as a `late final` field
  // initializer: `build()` short-circuits to `SizedBox.shrink` without ever
  // touching `_controller` whenever there's no compiled program (every
  // widget test, plus a real device that failed to compile the shader) — a
  // lazy `late` field would then only construct the `AnimationController`
  // the first time `dispose()` references it, by which point the element is
  // already deactivating and `vsync: this` can no longer look up its
  // `TickerMode` ancestor ("Looking up a deactivated widget's ancestor is
  // unsafe").
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _baselineSet = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)..addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!_baselineSet) {
      _trigger.check(widget.recentEvents); // establishes the baseline, never fires.
      _baselineSet = true;
    }
  }

  @override
  void didUpdateWidget(covariant SentryGlitchOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.recentEvents, widget.recentEvents)) return;
    final fresh = _trigger.check(widget.recentEvents);
    if (fresh && widget.enabled && !_reduceMotion) {
      _controller
        ..stop()
        ..value = 0
        ..forward();
    }
  }

  /// The ticker stops itself the instant the one-shot completes: resetting
  /// to `dismissed` here (rather than leaving it parked at `completed`)
  /// means `build()` collapses back to `SizedBox.shrink` and the controller
  /// goes fully idle until the next trigger re-arms it.
  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _controller.reset();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _reduceMotion) return const SizedBox.shrink();
    final program = context.read<ShaderLibrary>().sentryGlitch;
    if (program == null) return const SizedBox.shrink();

    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (_controller.status == AnimationStatus.dismissed) return const SizedBox.shrink();
            // No `Positioned` here on purpose: this widget is placed as a
            // plain (non-positioned) child in `_LiveCameraArea`'s
            // `Stack(fit: StackFit.expand)`, which already hands every such
            // child tight expand constraints — a nested `Positioned.fill`
            // would not be a *direct* Stack child and Flutter would reject
            // it. `CustomPaint` just fills whatever constraints it gets.
            return CustomPaint(
              painter: _SentryGlitchPainter(
                program: program,
                progress: _controller.value,
                // Derived from progress, not wall-clock (deterministic
                // under `flutter test`'s fake clock; only relative movement
                // within this one shot matters here).
                time: _controller.value * (_duration.inMilliseconds / 1000),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SentryGlitchPainter extends CustomPainter {
  _SentryGlitchPainter({required this.program, required this.progress, required this.time});

  final ui.FragmentProgram program;
  final double progress;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shader = program.fragmentShader()
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, progress);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _SentryGlitchPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.time != time;
}
