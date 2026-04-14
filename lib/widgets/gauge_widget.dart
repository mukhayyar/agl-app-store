import 'dart:math';
import 'package:flutter/material.dart';

class GaugeWidget extends StatelessWidget {
  final double value;   // 0–100
  final double size;
  final String label;

  const GaugeWidget({
    super.key,
    required this.value,
    this.size = 100,
    this.label = '',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(value: value.clamp(0, 100)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${value.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;

  _GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 10;
    const startAngle = pi * 0.75;
    const sweepAngle = pi * 1.5;

    // Background arc
    final bgPaint = Paint()
      ..color = const Color(0xFF2A2A3E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc color
    Color arcColor;
    if (value < 60) {
      arcColor = const Color(0xFF00D4FF);
    } else if (value < 80) {
      arcColor = const Color(0xFFFFAA00);
    } else {
      arcColor = const Color(0xFFFF4444);
    }

    final valuePaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * (value / 100),
      false,
      valuePaint,
    );

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i <= 10; i++) {
      final tickAngle = startAngle + sweepAngle * (i / 10);
      final outerX = center.dx + (radius + 5) * cos(tickAngle);
      final outerY = center.dy + (radius + 5) * sin(tickAngle);
      final innerX = center.dx + (radius - 5) * cos(tickAngle);
      final innerY = center.dy + (radius - 5) * sin(tickAngle);
      canvas.drawLine(
        Offset(outerX, outerY),
        Offset(innerX, innerY),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}
