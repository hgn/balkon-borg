import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/aircraft.dart';
import '../../services/haptics.dart';
import '../../services/ui_sounds.dart';
import '../../theme/balkon_theme.dart';

/// Pure bearing/distance → canvas-offset geometry (E10), factored out of the
/// painter so the tap hit-test, the callout position, and the paint code
/// all share one placement rule (what's drawn is exactly what's tappable)
/// and all three are unit-testable without a `Canvas`.
@immutable
class RadarGeometry {
  const RadarGeometry({required this.center, required this.radius});

  /// Centers on [size], radius shrinks by [edgePadding] to leave room for
  /// ring/cardinal labels drawn outside the traffic area.
  factory RadarGeometry.forSize(Size size, {double edgePadding = 26}) {
    final side = math.min(size.width, size.height);
    return RadarGeometry(
      center: Offset(size.width / 2, size.height / 2),
      radius: math.max(0, side / 2 - edgePadding),
    );
  }

  final Offset center;
  final double radius;

  /// Compass bearing (0 = north, clockwise) to the canvas angle Flutter's
  /// trig expects (0 = east/+x, clockwise since canvas y grows downward).
  static double bearingToCanvasAngle(double bearingDeg) => (bearingDeg * math.pi / 180) - math.pi / 2;

  /// Screen offset for a blip at [bearingDeg]/[distanceKm]. Traffic beyond
  /// [maxRangeKm] clamps to 94% of [radius] — just inside the outer ring,
  /// not on it, so it still reads as "further than anything really on the
  /// last ring" rather than looking like an exact detection at max range.
  BlipPlacement blipOffset({
    required double bearingDeg,
    required double distanceKm,
    required double maxRangeKm,
  }) {
    if (maxRangeKm <= 0 || radius <= 0) {
      return BlipPlacement(offset: center, clamped: distanceKm > 0);
    }
    final clamped = distanceKm > maxRangeKm;
    final norm = clamped ? 0.94 : (distanceKm / maxRangeKm).clamp(0.0, 1.0);
    final r = norm * radius;
    final angle = bearingToCanvasAngle(bearingDeg);
    return BlipPlacement(offset: center + Offset(math.cos(angle), math.sin(angle)) * r, clamped: clamped);
  }
}

class BlipPlacement {
  const BlipPlacement({required this.offset, required this.clamped});
  final Offset offset;
  final bool clamped;
}

/// Classic PPI persistence curve: brightness peaks at 1.0 the instant the
/// sweep beam passes a blip's bearing, then decays linearly until the beam
/// comes back around a full revolution later — floored at [minBrightness]
/// so old traffic dims but never fully disappears between sweeps.
double blipPersistence({
  required double bearingDeg,
  required double sweepDeg,
  double minBrightness = 0.15,
}) {
  final bearing = bearingDeg % 360;
  final sweep = sweepDeg % 360;
  final sinceSwept = ((sweep - bearing) % 360 + 360) % 360;
  final decay = 1 - sinceSwept / 360;
  return minBrightness + (1 - minBrightness) * decay;
}

/// ADS-B plan position indicator (E10, implementation-plan.md / D6): range
/// rings, a rotating sweep beam, blips at true bearing/distance that fade
/// with PPI persistence, a heading tick per blip, and a label on the
/// nearest (or tapped) aircraft. One `AnimationController` drives the sweep;
/// `MediaQuery.disableAnimations` renders one static frame with every blip
/// at full brightness instead.
///
/// Purely presentational: [aircraft] comes from the caller (`AppState`,
/// real or demo), and tapping a blip only changes which one is labelled —
/// the caller owns what "selection" means for anything beyond that.
///
/// The grid/sweep/blips paint on a `CustomPainter` (cheap, one canvas), but
/// the empty-sky message and the aircraft callout are real widgets in a
/// `Stack` on top of it — both are user-facing text that should be
/// discoverable by finders/screen readers, not baked into pixels.
class AdsbRadar extends StatefulWidget {
  const AdsbRadar({super.key, required this.aircraft, this.maxRangeKm = 50});

  final List<Aircraft> aircraft;
  final double maxRangeKm;

  @override
  State<AdsbRadar> createState() => _AdsbRadarState();
}

class _AdsbRadarState extends State<AdsbRadar> with SingleTickerProviderStateMixin {
  static const _revolution = Duration(seconds: 4);
  static const _tapSlop = 24.0; // big-fingers/low-dexterity touch target (task spec).
  static const _calloutWidthBudget = 118.0;

  late final AnimationController _controller = AnimationController(vsync: this, duration: _revolution);
  bool _reduceMotion = false;
  String? _selectedHex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    _sync();
  }

  void _sync() {
    if (_reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Aircraft> get _placeable => [
        for (final a in widget.aircraft)
          if (a.isPlaceable) a,
      ];

  Aircraft? _nearest(List<Aircraft> placeable) {
    if (placeable.isEmpty) return null;
    var best = placeable.first;
    for (final a in placeable.skip(1)) {
      if (a.distKm! < best.distKm!) best = a;
    }
    return best;
  }

  Aircraft? _labelled(List<Aircraft> placeable) {
    if (_selectedHex != null) {
      for (final a in placeable) {
        if (a.hex == _selectedHex) return a;
      }
    }
    return _nearest(placeable);
  }

  void _handleTapUp(TapUpDetails details, Size size, List<Aircraft> placeable) {
    final geometry = RadarGeometry.forSize(size);
    Aircraft? hit;
    var hitDistSq = _tapSlop * _tapSlop;
    for (final a in placeable) {
      final placement = geometry.blipOffset(
        bearingDeg: a.bearingDeg!,
        distanceKm: a.distKm!,
        maxRangeKm: widget.maxRangeKm,
      );
      final d = (placement.offset - details.localPosition).distanceSquared;
      if (d <= hitDistSq) {
        hit = a;
        hitDistSq = d;
      }
    }
    if (hit == null) return;
    setState(() => _selectedHex = hit!.hex);
    context.read<Haptics>().selectionClick();
    context.read<UiSounds>().blip();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    final placeable = _placeable;
    final labelled = _labelled(placeable);

    // Square-ish, full available width (task spec): `AspectRatio` expands to
    // the incoming width and derives height from it, rather than relying on
    // the surrounding Column (loose height) to hand back a definite size.
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final geometry = RadarGeometry.forSize(size);

          return GestureDetector(
            onTapUp: (details) => _handleTapUp(details, size, placeable),
            child: Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) {
                        final sweepDeg = _reduceMotion ? null : _controller.value * 360;
                        return CustomPaint(
                          size: size,
                          painter: _AdsbRadarPainter(
                            aircraft: placeable,
                            maxRangeKm: widget.maxRangeKm,
                            sweepDeg: sweepDeg,
                            selectedHex: labelled?.hex,
                            gridColor: extras.textDim,
                            sweepColor: scheme.primary,
                            blipColor: scheme.primary,
                            ringLabelStyle: balkonMonoStyle(context, 10, FontWeight.w600, color: extras.textDim),
                            cardinalStyle: balkonMonoStyle(context, 10, FontWeight.w700, color: extras.textDim),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (widget.aircraft.isEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          'keine Flugzeuge in Reichweite',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Manrope',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: extras.textDim,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (labelled != null)
                  _callout(context, labelled, geometry, size, extras),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The nearest-(or tapped-)aircraft label: callsign, altitude, distance,
  /// anchored next to its blip and flipped to the opposite side if it would
  /// otherwise run past the card edge.
  Widget _callout(
    BuildContext context,
    Aircraft a,
    RadarGeometry geometry,
    Size size,
    BalkonExtras extras,
  ) {
    final placement = geometry.blipOffset(
      bearingDeg: a.bearingDeg!,
      distanceKm: a.distKm!,
      maxRangeKm: widget.maxRangeKm,
    );
    final mainText = a.flight ?? a.hex.toUpperCase();
    final altText = a.altFt != null ? '${a.altFt!.round()} ft' : '— ft';
    final distText = '${a.distKm!.toStringAsFixed(1)} km';
    final wantsRight = placement.offset.dx + 10 + _calloutWidthBudget <= size.width;
    final top = (placement.offset.dy - 20).clamp(0.0, math.max(0.0, size.height - 44)).toDouble();

    return Positioned(
      left: wantsRight ? placement.offset.dx + 10 : null,
      right: wantsRight ? null : size.width - placement.offset.dx + 10,
      top: top,
      child: IgnorePointer(
        child: Container(
          constraints: BoxConstraints(maxWidth: _calloutWidthBudget),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: extras.surface3.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mainText,
                overflow: TextOverflow.ellipsis,
                style: balkonMonoStyle(context, 13, FontWeight.w700),
              ),
              Text(
                '$altText · $distText',
                overflow: TextOverflow.ellipsis,
                style: balkonMonoStyle(context, 11, FontWeight.w600, color: extras.textDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdsbRadarPainter extends CustomPainter {
  const _AdsbRadarPainter({
    required this.aircraft,
    required this.maxRangeKm,
    required this.sweepDeg,
    required this.selectedHex,
    required this.gridColor,
    required this.sweepColor,
    required this.blipColor,
    required this.ringLabelStyle,
    required this.cardinalStyle,
  });

  /// Already filtered to placeable (bearing+distance known) aircraft.
  final List<Aircraft> aircraft;
  final double maxRangeKm;
  final double? sweepDeg;
  final String? selectedHex;
  final Color gridColor;
  final Color sweepColor;
  final Color blipColor;
  final TextStyle ringLabelStyle;
  final TextStyle cardinalStyle;

  static const _ringFractions = [0.2, 0.5, 1.0];
  static const _cardinals = [(0.0, 'N'), (90.0, 'E'), (180.0, 'S'), (270.0, 'W')];

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = RadarGeometry.forSize(size);
    if (geometry.radius <= 0) return;

    _paintRings(canvas, geometry);
    _paintCardinals(canvas, geometry);
    if (sweepDeg != null) _paintSweep(canvas, geometry, sweepDeg!);

    // Farthest first so nearer (usually more relevant) blips paint on top.
    final sorted = [...aircraft]..sort((a, b) => b.distKm!.compareTo(a.distKm!));
    for (final a in sorted) {
      _paintBlip(canvas, geometry, a);
    }
  }

  void _paintRings(Canvas canvas, RadarGeometry g) {
    final paint = Paint()
      ..color = gridColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final fraction in _ringFractions) {
      final r = g.radius * fraction;
      canvas.drawCircle(g.center, r, paint);
      final km = (maxRangeKm * fraction).round();
      _paintText(canvas, '$km km', ringLabelStyle, g.center + Offset(4, -r - 12));
    }
  }

  void _paintCardinals(Canvas canvas, RadarGeometry g) {
    for (final (bearing, label) in _cardinals) {
      final angle = RadarGeometry.bearingToCanvasAngle(bearing);
      final pos = g.center + Offset(math.cos(angle), math.sin(angle)) * (g.radius + 12);
      _paintText(canvas, label, cardinalStyle, pos, centered: true);
    }
  }

  void _paintSweep(Canvas canvas, RadarGeometry g, double sweepDegValue) {
    final angle = RadarGeometry.bearingToCanvasAngle(sweepDegValue);
    final rect = Rect.fromCircle(center: g.center, radius: g.radius);
    final gradient = SweepGradient(
      transform: GradientRotation(angle),
      colors: [
        sweepColor.withValues(alpha: 0.32),
        sweepColor.withValues(alpha: 0.0),
        sweepColor.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.24, 1.0],
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawCircle(g.center, g.radius, Paint()..shader = gradient.createShader(rect));
    canvas.restore();

    final edge = g.center + Offset(math.cos(angle), math.sin(angle)) * g.radius;
    canvas.drawLine(
      g.center,
      edge,
      Paint()
        ..color = sweepColor.withValues(alpha: 0.75)
        ..strokeWidth = 1.4,
    );
  }

  void _paintBlip(Canvas canvas, RadarGeometry g, Aircraft a) {
    final placement = g.blipOffset(bearingDeg: a.bearingDeg!, distanceKm: a.distKm!, maxRangeKm: maxRangeKm);
    final brightness =
        sweepDeg == null ? 1.0 : blipPersistence(bearingDeg: a.bearingDeg!, sweepDeg: sweepDeg!);
    final alpha = (placement.clamped ? brightness * 0.55 : brightness).clamp(0.0, 1.0);
    final isSelected = a.hex == selectedHex;

    final dotRadius = isSelected ? 5.5 : 4.0;
    canvas.drawCircle(placement.offset, dotRadius, Paint()..color = blipColor.withValues(alpha: alpha));
    if (isSelected) {
      canvas.drawCircle(
        placement.offset,
        dotRadius + 4,
        Paint()
          ..color = blipColor.withValues(alpha: alpha * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (a.trackDeg != null) {
      final headingAngle = RadarGeometry.bearingToCanvasAngle(a.trackDeg!);
      final tickEnd =
          placement.offset + Offset(math.cos(headingAngle), math.sin(headingAngle)) * (dotRadius + 7);
      canvas.drawLine(
        placement.offset,
        tickEnd,
        Paint()
          ..color = blipColor.withValues(alpha: alpha)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintText(Canvas canvas, String text, TextStyle style, Offset position, {bool centered = false}) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)
      ..layout();
    final offset = centered ? position - Offset(painter.width / 2, painter.height / 2) : position;
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _AdsbRadarPainter oldDelegate) =>
      !identical(oldDelegate.aircraft, aircraft) ||
      oldDelegate.maxRangeKm != maxRangeKm ||
      oldDelegate.sweepDeg != sweepDeg ||
      oldDelegate.selectedHex != selectedHex ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.sweepColor != sweepColor ||
      oldDelegate.blipColor != blipColor;
}
