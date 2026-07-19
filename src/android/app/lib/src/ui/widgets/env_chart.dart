import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/haptics.dart';
import '../../theme/balkon_theme.dart';

/// One chart data point: a value plotted against its real sample time.
/// [EnvChart] stays temperature/humidity/pressure-agnostic — callers
/// (`_EnvStatSpec` in home_screen.dart) decide which `EnvSample` field to
/// plot and how to format it; the chart only ever sees `(ts, value)` pairs.
typedef EnvChartPoint = ({DateTime ts, double value});

/// Maps a horizontal offset within the chart to the nearest sample index,
/// using the same even x-spacing `_EnvChartPainter.pointAt` draws with
/// (`dx = width / (length - 1)`). Extracted as a pure function so the
/// scrubbing math is unit-testable without pumping a widget.
///
/// Returns `null` when there's nothing to select (an empty history, or a
/// non-positive width — a chart that hasn't been laid out yet).
int? nearestSampleIndex({required double dx, required double width, required int length}) {
  if (length <= 0 || width <= 0) return null;
  if (length == 1) return 0;
  final step = width / (length - 1);
  return (dx / step).round().clamp(0, length - 1);
}

/// Environment line chart for the chart sheet (components.md "Bottom Sheet —
/// Umgebungs-Chart", D4: `CustomPainter`, no chart package). Draws a smooth
/// primary-colored line with rounded caps/joins plus a 15%-opacity fill
/// below it, scaled to the widget's own size (the design's `viewBox 300×100`
/// is just an aspect hint, not a fixed pixel size here).
///
/// Also owns touch-scrubbing: a horizontal drag selects the nearest sample,
/// draws a crosshair + dot on the curve, and fires [onSelectionChanged] once
/// per distinct sample crossed (plus a final `null` on release) so a caller
/// can swap its own readout without duplicating the x-pixel↔sample mapping.
/// A plain [GestureDetector.onHorizontalDrag*] is used deliberately: it's
/// backed by a `HorizontalDragGestureRecognizer`, which only claims the
/// gesture once motion is predominantly horizontal, so a vertical drag
/// still falls through to an ancestor (the chart sheet is itself
/// vertically draggable — drag-to-dismiss/resize, not a scroll view).
class EnvChart extends StatefulWidget {
  const EnvChart({super.key, required this.points, this.height = 140, this.onSelectionChanged});

  final List<EnvChartPoint> points;
  final double height;

  /// Fires with the newly selected point on every distinct sample crossed
  /// while scrubbing, and once more with `null` when the drag ends/cancels.
  final ValueChanged<EnvChartPoint?>? onSelectionChanged;

  @override
  State<EnvChart> createState() => _EnvChartState();
}

class _EnvChartState extends State<EnvChart> with SingleTickerProviderStateMixin {
  /// The index last reported via [EnvChart.onSelectionChanged]/haptics. This
  /// *is* the dedup rule: a new pointer-move only does anything when the
  /// nearest-sample index it maps to differs from this value, so a fast
  /// swipe across many pixels of the same sample's "bucket" produces zero
  /// extra haptic calls — multiple x pixels map to one sample index, and
  /// only the index transitions are notified.
  int? _selectedIndex;

  /// Index currently painted (crosshair + dot). Kept alive through the
  /// release fade-out even after [_selectedIndex] goes back to `null`, so
  /// the crosshair fades out in place instead of vanishing instantly.
  int? _paintIndex;

  late final AnimationController _crosshairFade;

  @override
  void initState() {
    super.initState();
    _crosshairFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  }

  @override
  void didUpdateWidget(covariant EnvChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Defend against the history shrinking under an active scrub (e.g. a
    // live data refresh mid-gesture): drop an index that's now out of range
    // rather than painting/reporting garbage.
    if (_selectedIndex != null && _selectedIndex! >= widget.points.length) {
      _selectedIndex = null;
      _paintIndex = null;
      _crosshairFade.value = 0;
    }
  }

  @override
  void dispose() {
    _crosshairFade.dispose();
    super.dispose();
  }

  bool get _disableAnimations => MediaQuery.of(context).disableAnimations;

  void _handleDrag(Offset localPosition, double width) {
    final index = nearestSampleIndex(
      dx: localPosition.dx,
      width: width,
      length: widget.points.length,
    );
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      if (index != null) _paintIndex = index;
    });
    if (index != null) {
      context.read<Haptics>().selectionClick();
      _crosshairFade.value = 1; // appear instantly — no fade-in, only fade-out.
    }
    widget.onSelectionChanged?.call(index == null ? null : widget.points[index]);
  }

  void _endDrag() {
    if (_selectedIndex == null) return;
    setState(() => _selectedIndex = null);
    widget.onSelectionChanged?.call(null);
    if (_disableAnimations) {
      _crosshairFade.value = 0;
      setState(() => _paintIndex = null);
    } else {
      _crosshairFade.reverse().then((_) {
        if (mounted) setState(() => _paintIndex = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final extras = Theme.of(context).extension<BalkonExtras>()!;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) => _handleDrag(details.localPosition, width),
            onHorizontalDragUpdate: (details) => _handleDrag(details.localPosition, width),
            onHorizontalDragEnd: (_) => _endDrag(),
            onHorizontalDragCancel: _endDrag,
            child: AnimatedBuilder(
              animation: _crosshairFade,
              builder: (context, _) => CustomPaint(
                painter: _EnvChartPainter(
                  points: widget.points,
                  color: color,
                  ringColor: extras.surface3,
                  selectedIndex: _paintIndex,
                  crosshairOpacity: _crosshairFade.value,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EnvChartPainter extends CustomPainter {
  const _EnvChartPainter({
    required this.points,
    required this.color,
    required this.ringColor,
    required this.selectedIndex,
    required this.crosshairOpacity,
  });

  final List<EnvChartPoint> points;
  final Color color;
  final Color ringColor;
  final int? selectedIndex;
  final double crosshairOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;

    final minV = points.map((p) => p.value).reduce(math.min);
    final maxV = points.map((p) => p.value).reduce(math.max);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    final dx = size.width / (points.length - 1);

    Offset pointAt(int i) {
      final t = (points[i].value - minV) / range;
      return Offset(dx * i, size.height - t * size.height);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p = pointAt(i);
      linePath.lineTo(p.dx, p.dy);
    }

    final fillPath = Path.from(linePath)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final selected = selectedIndex;
    if (selected != null && crosshairOpacity > 0) {
      final p = pointAt(selected);
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.35 * crosshairOpacity)
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(p, 6, Paint()..color = ringColor.withValues(alpha: crosshairOpacity));
      canvas.drawCircle(p, 4, Paint()..color = color.withValues(alpha: crosshairOpacity));
    }
  }

  @override
  bool shouldRepaint(covariant _EnvChartPainter oldDelegate) =>
      !identical(oldDelegate.points, points) ||
      oldDelegate.color != color ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.crosshairOpacity != crosshairOpacity;
}
