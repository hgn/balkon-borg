import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Environment line chart for the chart sheet (components.md "Bottom Sheet —
/// Umgebungs-Chart", D4: `CustomPainter`, no chart package). Draws a smooth
/// primary-colored line with rounded caps/joins plus a 15%-opacity fill
/// below it, scaled to the widget's own size (the design's `viewBox 300×100`
/// is just an aspect hint, not a fixed pixel size here).
class EnvChart extends StatelessWidget {
  const EnvChart({super.key, required this.values, this.height = 140});

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _EnvChartPainter(values: values, color: color)),
    );
  }
}

class _EnvChartPainter extends CustomPainter {
  const _EnvChartPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;

    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : maxV - minV;
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final t = (values[i] - minV) / range;
      return Offset(dx * i, size.height - t * size.height);
    }

    final linePath = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < values.length; i++) {
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
  }

  @override
  bool shouldRepaint(covariant _EnvChartPainter oldDelegate) =>
      !identical(oldDelegate.values, values) || oldDelegate.color != color;
}
