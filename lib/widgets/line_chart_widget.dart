import 'package:flutter/material.dart';

/// Simple sparkline chart.
///
/// When [yAxisLabels] is provided, labels are drawn on the left
/// (reserving horizontal space) at evenly distributed heights — top
/// label = first entry, bottom label = last entry.
class LineChartWidget extends StatelessWidget {
  final List<double> data;
  final double maxValue;
  final Color color;
  final bool showDot;
  final List<String>? yAxisLabels;
  final Color? axisColor;

  const LineChartWidget({
    super.key,
    required this.data,
    required this.maxValue,
    this.color = const Color(0xFF00D4FF),
    this.showDot = true,
    this.yAxisLabels,
    this.axisColor,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        size: Size.infinite,
        painter: _LineChartPainter(
          data: data,
          maxValue: maxValue > 0 ? maxValue : 1,
          color: color,
          showDot: showDot,
          yAxisLabels: yAxisLabels,
          axisColor: axisColor ?? Colors.white.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final double maxValue;
  final Color color;
  final bool showDot;
  final List<String>? yAxisLabels;
  final Color axisColor;

  _LineChartPainter({
    required this.data,
    required this.maxValue,
    required this.color,
    required this.showDot,
    required this.yAxisLabels,
    required this.axisColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    // Reserve space on the left for axis labels.
    final double axisGutter = yAxisLabels != null ? 32 : 0;
    final chartLeft = axisGutter;
    final w = size.width - axisGutter;
    final h = size.height;
    if (w <= 0) return;

    // Draw Y-axis labels + horizontal grid lines
    if (yAxisLabels != null && yAxisLabels!.isNotEmpty) {
      final labels = yAxisLabels!;
      final gridPaint = Paint()
        ..color = axisColor.withValues(alpha: 0.18)
        ..strokeWidth = 0.5;
      for (int i = 0; i < labels.length; i++) {
        final t = labels.length == 1 ? 0.0 : i / (labels.length - 1);
        final y = t * h;
        // Grid line
        canvas.drawLine(
          Offset(chartLeft, y),
          Offset(chartLeft + w, y),
          gridPaint,
        );
        // Label
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(
              color: axisColor,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
        );
        tp.layout(maxWidth: axisGutter - 4);
        final ly = (y - tp.height / 2)
            .clamp(0.0, h - tp.height);
        tp.paint(canvas, Offset(axisGutter - 4 - tp.width, ly));
      }
    } else {
      // No labels — still draw faint grid
      final gridPaint = Paint()
        ..color = axisColor.withValues(alpha: 0.12)
        ..strokeWidth = 0.5;
      for (int i = 1; i <= 3; i++) {
        final y = h - (i / 4) * h;
        canvas.drawLine(
          Offset(chartLeft, y),
          Offset(chartLeft + w, y),
          gridPaint,
        );
      }
    }

    // Build chart points
    final points = <Offset>[];
    for (int i = 0; i < data.length; i++) {
      final x = chartLeft +
          (data.length == 1 ? 0 : (i / (data.length - 1)) * w);
      final y = h - (data[i].clamp(0, maxValue) / maxValue) * h;
      points.add(Offset(x, y));
    }

    // Gradient fill
    final fillPath = Path()..moveTo(points.first.dx, h);
    for (final pt in points) {
      fillPath.lineTo(pt.dx, pt.dy);
    }
    fillPath.lineTo(points.last.dx, h);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(chartLeft, 0, w, h)),
    );

    // Line
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Last-point dot (current value)
    if (showDot && points.isNotEmpty) {
      canvas.drawCircle(
        points.last,
        4.5,
        Paint()..color = color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(points.last, 3, Paint()..color = color);
      canvas.drawCircle(
        points.last,
        3,
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
