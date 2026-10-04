import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight line chart used for the coin "sparkline" previews.
///
/// Implemented with a [CustomPainter] so it stays a single widget with no
/// third-party chart dependency.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 44,
    this.strokeWidth = 2.2,
    this.filled = true,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double strokeWidth;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          strokeWidth: strokeWidth,
          filled: filled,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.strokeWidth,
    required this.filled,
  });

  final List<double> values;
  final Color color;
  final double strokeWidth;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) {
      return;
    }

    final double min = values.reduce(math.min);
    final double max = values.reduce(math.max);
    final double range = (max - min).abs() < 1e-9 ? 1 : max - min;
    final double dx = size.width / (values.length - 1);
    final double inset = strokeWidth; // keep the stroke inside the box
    final double usableHeight = math.max(size.height - inset, 1);

    final Path path = Path();
    for (int i = 0; i < values.length; i++) {
      final double x = dx * i;
      final double y =
          inset / 2 + (1 - (values[i] - min) / range) * usableHeight;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    if (filled) {
      final Path area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      final Paint fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            color.withValues(alpha: 0.28),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(area, fillPaint);
    }

    final Paint strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.filled != filled;
  }
}
