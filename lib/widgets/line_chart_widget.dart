import 'package:flutter/material.dart';

class LineChartWidget extends StatelessWidget {
  final List<double> data;
  final double maxValue;
  final Color color;
  final bool showDot;

  const LineChartWidget({
    super.key,
    required this.data,
    required this.maxValue,
    this.color = const Color(0xFF00D4FF),
    this.showDot = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Force CustomPaint to fill its parent — without this,
        // CustomPaint(size: Size.zero) collapses to zero and the chart
        // is invisible. LayoutBuilder gives us the actual finite size
        // from the parent SizedBox/Expanded/etc.
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 60.0;
        return ClipRect(
          child: CustomPaint(
            size: Size(w, h),
            painter: _LineChartPainter(
              data: data,
              maxValue: maxValue > 0 ? maxValue : 1,
              color: color,
              showDot: showDot,
            ),
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final double maxValue;
  final Color color;
  final bool showDot;

  _LineChartPainter({
    required this.data,
    required this.maxValue,
    required this.color,
    required this.showDot,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    final w = size.width;
    final h = size.height;
    const topPad = 4.0;
    const botPad = 4.0;
    final plotH = (h - topPad - botPad).clamp(1.0, h);

    // Background grid (5 horizontal lines at 0%/25%/50%/75%/100%)
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = 0.8;
    for (int i = 0; i <= 4; i++) {
      final y = topPad + (i / 4) * plotH;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Build points inside padded region
    final n = data.length;
    final points = <Offset>[];
    for (int i = 0; i < n; i++) {
      final x = n == 1 ? w / 2 : (i / (n - 1)) * w;
      final v = data[i].clamp(0, maxValue).toDouble();
      final y = topPad + (1 - v / maxValue) * plotH;
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    // Gradient fill beneath the line
    final fillBaseline = h - botPad;
    final fillPath = Path()..moveTo(points.first.dx, fillBaseline);
    for (final pt in points) {
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(points.last.dx, fillBaseline);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // The line itself
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Last-point dot
    if (showDot && points.isNotEmpty) {
      canvas.drawCircle(points.last, 4, Paint()..color = color);
      canvas.drawCircle(
        points.last,
        4,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => true;
}
