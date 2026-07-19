import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../contract/submodes.dart';
import '../../contract/topics.dart';
import '../../models/mode_state.dart';
import '../../state/app_state.dart';
import '../../theme/balkon_theme.dart';
import 'health_sheet.dart';
import 'mode_card.dart' show modeAccent;

/// Fixed dial order shared with the mode grid (`home_screen.dart`'s
/// `_ModeGrid`) — also the order the four bottom indicator LEDs light up in.
const _ledOrder = [MainMode.lumen, MainMode.comms, MainMode.sigint, MainMode.sentry];

/// Neutral plate color for the diffuser when the light is off/unknown or the
/// app is disconnected — a dim violet-grey close to `BalkonColors.darkSurface3`
/// so the panel still reads as "the diffuser", just unlit.
const _diffuserOff = Color(0xFF241C33);

/// Group opacity applied to the whole render while disconnected (see
/// [deviceTwinVisual]) — dim enough to read as "not talking to us" rather
/// than "switched off and fine".
const _disconnectedOpacity = 0.46;

/// Diffuser fill color: [_diffuserOff] while unlit, otherwise [wledColor]
/// lightened toward white — the opal acrylic diffuser softens raw LED color,
/// it never reads as a fully saturated swatch on the physical device either.
/// Pure (no `BuildContext`) so it is unit-testable on its own, mirroring
/// `adsb_radar.dart`'s `RadarGeometry`/`blipPersistence`.
Color deviceTwinDiffuserColor(Color? wledColor) {
  if (wledColor == null) return _diffuserOff;
  return Color.lerp(wledColor, Colors.white, 0.30)!;
}

/// Which of the 4 bottom indicator LEDs read "lit", in [_ledOrder]. SENTRY's
/// only lights when actually armed (`Submodes.sentryArmedSubmodes`), matching
/// the mode-card border treatment (`mode_card.dart`) rather than merely
/// "not off".
List<bool> deviceTwinLedActive(Map<MainMode, ModeState> modes) {
  bool isActive(MainMode m) {
    final s = modes[m];
    if (s == null) return false;
    if (m == MainMode.sentry) return Submodes.sentryArmedSubmodes.contains(s.submode);
    return !s.isOff;
  }

  return [for (final m in _ledOrder) isActive(m)];
}

/// Everything the painter needs, derived once from app state and otherwise
/// independent of `BuildContext`/`Theme` — the unit-testable core of the
/// widget (task spec: "the painter's pure parts ... unit-tested").
@immutable
class DeviceTwinVisual {
  const DeviceTwinVisual({required this.diffuserColor, required this.ledActive, required this.dim});

  final Color diffuserColor;

  /// Length 4, in [_ledOrder]. All `false` (and meaningless) while [dim].
  final List<bool> ledActive;

  /// True while disconnected: nothing in [ledActive]/[diffuserColor] can be
  /// trusted (possibly stale retained state), so the whole device renders
  /// desaturated/dim instead of pretending to know its own state.
  final bool dim;

  bool get sentryArmed => !dim && ledActive[3];
}

/// Resolves [DeviceTwinVisual] from the app's own state — no optimistic
/// reading of stale data while disconnected (same convention `AppState`
/// itself follows for the mode topics).
DeviceTwinVisual deviceTwinVisual({
  required bool connected,
  required Color? wledColor,
  required Map<MainMode, ModeState> modes,
}) {
  if (!connected) {
    return const DeviceTwinVisual(
      diffuserColor: _diffuserOff,
      ledActive: [false, false, false, false],
      dim: true,
    );
  }
  return DeviceTwinVisual(
    diffuserColor: deviceTwinDiffuserColor(wledColor),
    ledActive: deviceTwinLedActive(modes),
    dim: false,
  );
}

/// Case-border health tint (D1's header dot, same palette): quiet by design
/// — an all-OK device keeps its normal border, only degraded/bad states show
/// through, "alive but struggling" rather than a second alarm next to the
/// header dot.
Color? deviceTwinBorderTint(AggregateHealth health) => switch (health) {
      AggregateHealth.degraded => Colors.amber,
      AggregateHealth.bad => BalkonColors.danger,
      AggregateHealth.ok || AggregateHealth.unknown => null,
    };

/// Twin-Lite (E12, implementation-plan.md D6): a small painted portrait of
/// the enclosure as seen from below (case shell, diffuser, camera lens, the
/// four bottom indicator LEDs, a hint of the RTL-SDR antenna). `CustomPainter`
/// only, no model file/asset/3D package — the diffuser is tinted live by
/// `AppState.wledColor` (animated via [balkonSpring], the theme's
/// direct-manipulation curve), the LEDs and the SENTRY ring reflect the mode
/// state the app already has.
///
/// One `AnimationController`, used only to tween the diffuser color between
/// two known values — never `.repeat()`s, so a static device costs nothing.
/// Tapping opens the health sheet, same destination as the header status dot.
class DeviceTwin extends StatefulWidget {
  const DeviceTwin({super.key});

  /// Wide and flat, echoing the real enclosure (~508×150mm underside
  /// footprint, `docs/img/overview.png`) rather than a squared-off icon.
  static const aspectRatio = 3.0;

  /// Caps the strip's height regardless of how wide its row is — without
  /// this, [aspectRatio] alone would let the strip grow tall on a wide
  /// viewport (a tablet, or `flutter_test`'s default 800×600 surface); the
  /// point of the widget is a compact band, not a hero image that competes
  /// with the mode grid below it (home_screen.dart, task spec: "must not
  /// push everything below the fold").
  static const _maxHeight = 118.0;

  @override
  State<DeviceTwin> createState() => _DeviceTwinState();
}

class _DeviceTwinState extends State<DeviceTwin> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: balkonSpringDuration);
  late final CurvedAnimation _curve = CurvedAnimation(parent: _controller, curve: balkonSpring);

  ColorTween _diffuserTween = ColorTween(begin: _diffuserOff, end: _diffuserOff);
  Color _lastTarget = _diffuserOff;
  bool _initialized = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Starts (or skips, under reduced motion) a spring tween from whatever is
  /// currently on screen to [target]. Called from `build()`, same idiom as
  /// `shell.dart`'s `_HealthDot._syncPing` — the widget's own constructor
  /// never changes, the Provider-driven target does.
  void _syncDiffuser(Color target) {
    if (!_initialized) {
      _initialized = true;
      _lastTarget = target;
      _diffuserTween = ColorTween(begin: target, end: target);
      _controller.value = 1;
      return;
    }
    if (target == _lastTarget) return;
    final current = _diffuserTween.evaluate(_curve) ?? _lastTarget;
    _lastTarget = target;
    if (_reduceMotion) {
      _diffuserTween = ColorTween(begin: target, end: target);
      _controller.value = 1;
      return;
    }
    _diffuserTween = ColorTween(begin: current, end: target);
    _controller
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final scheme = Theme.of(context).colorScheme;

    final visual = deviceTwinVisual(
      connected: state.connected,
      wledColor: state.wledColor,
      modes: state.modes,
    );
    _syncDiffuser(visual.diffuserColor);
    final borderTint = deviceTwinBorderTint(state.aggregateHealth);
    final ledPalette = [for (final m in _ledOrder) modeAccent(context, m)];

    return GestureDetector(
      onTap: () => showHealthSheet(context, state),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: DeviceTwin._maxHeight),
        child: AspectRatio(
          aspectRatio: DeviceTwin.aspectRatio,
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                painter: DeviceTwinPainter(
                  caseColor: extras.surface2,
                  borderColor: borderTint ?? scheme.outline,
                  diffuserColor: _diffuserTween.evaluate(_curve) ?? visual.diffuserColor,
                  ledColors: ledPalette,
                  ledActive: visual.ledActive,
                  ledOffColor: extras.textDim,
                  sentryArmed: visual.sentryArmed,
                  sentryColor: extras.danger,
                  markColor: extras.textDim,
                  dim: visual.dim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat, geometric render of the enclosure's underside: rounded case shell,
/// the diffuser as the dominant surface, a camera pod with lens (+ a SENTRY
/// ring when armed), a small mic/speaker grille, the four bottom indicator
/// LEDs, and a short antenna hint off the right edge. No gradients/shadows —
/// matches the flat style of `adsb_radar.dart`'s painter.
///
/// Public (unlike `adsb_radar.dart`'s painter) so widget tests can assert on
/// its fields directly — this widget has no visible text to check instead.
@immutable
class DeviceTwinPainter extends CustomPainter {
  const DeviceTwinPainter({
    required this.caseColor,
    required this.borderColor,
    required this.diffuserColor,
    required this.ledColors,
    required this.ledActive,
    required this.ledOffColor,
    required this.sentryArmed,
    required this.sentryColor,
    required this.markColor,
    required this.dim,
  });

  final Color caseColor;
  final Color borderColor;
  final Color diffuserColor;

  /// Length 4, [_ledOrder].
  final List<Color> ledColors;
  final List<bool> ledActive;
  final Color ledOffColor;

  final bool sentryArmed;
  final Color sentryColor;

  /// Mic-grille / antenna stroke color.
  final Color markColor;

  final bool dim;

  static const _lensColor = Color(0xFF14101C);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.shortestSide <= 0) return;
    final w = size.width;
    final h = size.height;

    // Group opacity for the "disconnected" state (task spec: must not look
    // like a device that's simply switched off and fine) — only paid for
    // when actually dim, saveLayer is not free.
    final needsLayer = dim;
    if (needsLayer) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: _disconnectedOpacity),
      );
    }

    _paintCase(canvas, w, h);
    _paintDiffuser(canvas, w, h);
    _paintCameraPod(canvas, w, h);
    _paintMicGrille(canvas, w, h);
    _paintLeds(canvas, w, h);
    _paintAntenna(canvas, w, h);

    if (needsLayer) canvas.restore();
  }

  void _paintCase(Canvas canvas, double w, double h) {
    final rect = RRect.fromRectAndRadius(Offset.zero & Size(w, h), Radius.circular(h * 0.30));
    canvas.drawRRect(rect, Paint()..color = caseColor);
    canvas.drawRRect(
      rect.deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = borderColor,
    );
  }

  void _paintDiffuser(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTRB(w * 0.035, h * 0.08, w * 0.965, h * 0.60);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(h * 0.16));
    canvas.drawRRect(rrect, Paint()..color = diffuserColor);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.18),
    );
  }

  void _paintCameraPod(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.16, h * 0.80);
    final side = h * 0.30;
    final podRect = Rect.fromCenter(center: center, width: side, height: side);
    final podRRect = RRect.fromRectAndRadius(podRect, Radius.circular(side * 0.28));
    canvas.drawRRect(podRRect, Paint()..color = caseColor);
    canvas.drawRRect(
      podRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );

    final lensRadius = side * 0.30;
    canvas.drawCircle(center, lensRadius, Paint()..color = _lensColor);
    canvas.drawCircle(
      center + Offset(-lensRadius * 0.30, -lensRadius * 0.30),
      lensRadius * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
    if (sentryArmed) {
      canvas.drawCircle(
        center,
        lensRadius + 3.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = sentryColor,
      );
    }
  }

  void _paintMicGrille(Canvas canvas, double w, double h) {
    final center = Offset(w * 0.31, h * 0.80);
    final dotRadius = h * 0.014;
    final spacing = h * 0.05;
    final paint = Paint()..color = markColor.withValues(alpha: 0.7);
    for (var row = -1; row <= 1; row++) {
      for (var col = -1; col <= 1; col++) {
        canvas.drawCircle(center + Offset(col * spacing, row * spacing), dotRadius, paint);
      }
    }
  }

  void _paintLeds(Canvas canvas, double w, double h) {
    final y = h * 0.80;
    const startFrac = 0.52;
    const endFrac = 0.88;
    final radius = h * 0.045;
    for (var i = 0; i < ledActive.length; i++) {
      final x = w * (startFrac + (endFrac - startFrac) * (i / (ledActive.length - 1)));
      final active = ledActive[i];
      final color = active ? ledColors[i] : ledOffColor.withValues(alpha: 0.35);
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
      if (active) {
        canvas.drawCircle(
          Offset(x, y),
          radius + 1.6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.4),
        );
      }
    }
  }

  void _paintAntenna(Canvas canvas, double w, double h) {
    // Kept entirely below the diffuser's bottom edge (0.60h, `_paintDiffuser`)
    // so it always reads as coming off the case's side, never crossing over
    // the lit panel.
    final base = Offset(w * 0.86, h * 0.72);
    final tip = Offset(w * 0.99, h * 0.62);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = markColor,
    );
    canvas.drawCircle(tip, 1.8, Paint()..color = markColor);
  }

  @override
  bool shouldRepaint(covariant DeviceTwinPainter oldDelegate) =>
      oldDelegate.caseColor != caseColor ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.diffuserColor != diffuserColor ||
      !listEquals(oldDelegate.ledColors, ledColors) ||
      !listEquals(oldDelegate.ledActive, ledActive) ||
      oldDelegate.ledOffColor != ledOffColor ||
      oldDelegate.sentryArmed != sentryArmed ||
      oldDelegate.sentryColor != sentryColor ||
      oldDelegate.markColor != markColor ||
      oldDelegate.dim != dim;
}
