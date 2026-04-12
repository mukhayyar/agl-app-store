import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Large automotive-style arc speedometer (0–120 km/h)
class SpeedometerWidget extends StatefulWidget {
  final double speedKmh;
  final double maxSpeed;

  const SpeedometerWidget({
    super.key,
    required this.speedKmh,
    this.maxSpeed = 120,
  });

  @override
  State<SpeedometerWidget> createState() => _SpeedometerWidgetState();
}

class _SpeedometerWidgetState extends State<SpeedometerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _displaySpeed = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    )..addListener(() {
        setState(() => _displaySpeed = _animation.value);
      });
  }

  @override
  void didUpdateWidget(SpeedometerWidget old) {
    super.didUpdateWidget(old);
    if ((old.speedKmh - widget.speedKmh).abs() > 0.1) {
      _animation = Tween<double>(
        begin: _displaySpeed,
        end: widget.speedKmh,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = math.min(constraints.maxWidth, 320.0);
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SpeedometerPainter(
            speed: _displaySpeed.clamp(0.0, widget.maxSpeed),
            maxSpeed: widget.maxSpeed,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                Text(
                  _displaySpeed.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -2,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'km/h',
                  style: TextStyle(
                    color: Color(0xFF556677),
                    fontSize: 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  _SpeedometerPainter({required this.speed, required this.maxSpeed});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 16;

    const startAngle = math.pi * 0.72; // ~130 degrees from positive x
    const sweepFull = math.pi * 1.56;  // ~281 degrees total

    // Background track
    final trackPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepFull,
      false,
      trackPaint,
    );

    // Colored arc: green → yellow → red gradient by speed zone
    final fraction = speed / maxSpeed;
    final valueSweep = sweepFull * fraction;

    Color arcColor;
    if (fraction < 0.5) {
      arcColor = Color.lerp(const Color(0xFF00FF88), const Color(0xFFFFCC00), fraction * 2)!;
    } else {
      arcColor = Color.lerp(const Color(0xFFFFCC00), const Color(0xFFFF4444), (fraction - 0.5) * 2)!;
    }

    final arcPaint = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 22
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweep,
      false,
      arcPaint,
    );

    // Solid arc on top (no blur)
    final arcPaintSolid = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      valueSweep,
      false,
      arcPaintSolid,
    );

    // Tick marks every 10 km/h
    final tickPaint = Paint()
      ..color = const Color(0xFF334455)
      ..strokeWidth = 2.0;
    final majorTickPaint = Paint()
      ..color = const Color(0xFF556677)
      ..strokeWidth = 2.5;

    for (int i = 0; i <= maxSpeed.toInt(); i += 10) {
      final isMajor = i % 20 == 0;
      final angle = startAngle + sweepFull * (i / maxSpeed);
      final outerR = radius - 28;
      final innerR = outerR - (isMajor ? 14 : 8);
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * outerR;
      final inner = center + Offset(math.cos(angle), math.sin(angle)) * innerR;
      canvas.drawLine(inner, outer, isMajor ? majorTickPaint : tickPaint);

      // Speed labels at major ticks
      if (isMajor) {
        final labelRadius = innerR - 14;
        final labelPos = center + Offset(math.cos(angle), math.sin(angle)) * labelRadius;
        final tp = TextPainter(
          text: TextSpan(
            text: '$i',
            style: const TextStyle(color: Color(0xFF667788), fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, labelPos - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Needle
    final needleAngle = startAngle + sweepFull * fraction;
    final needleLen = radius - 36;
    final needleTip = center + Offset(math.cos(needleAngle), math.sin(needleAngle)) * needleLen;
    final needleBase = center + Offset(math.cos(needleAngle), math.sin(needleAngle)) * (-20);

    final needlePaint = Paint()
      ..color = const Color(0xFFFF6644)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(needleBase, needleTip, needlePaint);

    // Center dot
    canvas.drawCircle(center, 10, Paint()..color = const Color(0xFF223344));
    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFFFF6644));
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFF00D4FF));
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) =>
      old.speed != speed || old.maxSpeed != maxSpeed;
}
