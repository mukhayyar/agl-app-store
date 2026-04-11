import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Color-coded circular gauge: green <60%, yellow 60-80%, red >80%
class GaugeWidget extends StatelessWidget {
  final double value; // 0–100
  final String label;
  final String? subLabel;
  final double size;

  const GaugeWidget({
    super.key,
    required this.value,
    required this.label,
    this.subLabel,
    this.size = 120,
  });

  Color _gaugeColor(double v) {
    if (v < 60) return const Color(0xFF00FF88);
    if (v < 80) return const Color(0xFFFFCC00);
    return const Color(0xFFFF4444);
  }

  @override
  Widget build(BuildContext context) {
    final color = _gaugeColor(value);
    return SizedBox(
      width: size,
      height: size + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(value: value.clamp(0.0, 100.0), color: color),
            child: SizedBox(
              width: size,
              height: size,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${value.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: size * 0.22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subLabel != null)
                    Text(
                      subLabel!,
                      style: TextStyle(
                        color: const Color(0xFF888899),
                        fontSize: size * 0.11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFCCCCDD),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value; // 0–100
  final Color color;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const startAngle = math.pi * 0.75;
    const sweepFull = math.pi * 1.5;

    final trackPaint = Paint()
      ..color = const Color(0xFF222233)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      trackPaint,
    );

    final valueSweep = sweepFull * (value / 100.0);
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, color == const Color(0xFF00FF88) ? 3 : 2);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweep,
      false,
      valuePaint,
    );

    // Tick marks at 0%, 25%, 50%, 75%, 100%
    final tickPaint = Paint()
      ..color = const Color(0xFF444455)
      ..strokeWidth = 1.5;

    for (int i = 0; i <= 4; i++) {
      final angle = startAngle + sweepFull * (i / 4.0);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * (radius - 12);
      canvas.drawLine(inner, outer, tickPaint);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color;
}
