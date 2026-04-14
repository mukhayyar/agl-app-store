import 'dart:math';
import 'package:flutter/material.dart';

class SpeedometerWidget extends StatefulWidget {
  final double speedKmh;
  final double maxSpeed;
  final double size;

  const SpeedometerWidget({
    super.key,
    required this.speedKmh,
    this.maxSpeed = 120,
    this.size = 260,
  });

  @override
  State<SpeedometerWidget> createState() => _SpeedometerWidgetState();
}

class _SpeedometerWidgetState extends State<SpeedometerWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _prevSpeed = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _animation = Tween<double>(begin: 0, end: widget.speedKmh).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void didUpdateWidget(SpeedometerWidget old) {
    super.didUpdateWidget(old);
    if (old.speedKmh != widget.speedKmh) {
      _prevSpeed = _animation.value;
      _animation = Tween<double>(
        begin: _prevSpeed,
        end: widget.speedKmh,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _SpeedometerPainter(
              speed: _animation.value,
              maxSpeed: widget.maxSpeed,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  Text(
                    _animation.value.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -2,
                    ),
                  ),
                  const Text(
                    'km/h',
                    style: TextStyle(
                      color: Color(0xFF00D4FF),
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double speed;
  final double maxSpeed;

  _SpeedometerPainter({required this.speed, required this.maxSpeed});

  static const double _startAngle = pi * 0.75;  // 135°
  static const double _sweepAngle = pi * 1.5;   // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 18;

    // Background circle
    canvas.drawCircle(
      center,
      size.width / 2,
      Paint()..color = const Color(0xFF0D0D0D),
    );

    // Outer ring
    canvas.drawCircle(
      center,
      size.width / 2 - 2,
      Paint()
        ..color = const Color(0xFF2A2A3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = const Color(0xFF2A2A3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round,
    );

    // Gradient arc (speed indicator)
    final fraction = (speed / maxSpeed).clamp(0.0, 1.0);
    if (fraction > 0) {
      final sweepUsed = _sweepAngle * fraction;

      // Draw gradient arc in segments
      const segments = 60;
      final segmentSweep = sweepUsed / segments;
      for (int i = 0; i < segments; i++) {
        final t = i / segments;
        final segAngle = _startAngle + sweepUsed * t;
        Color segColor;
        if (t < 0.5) {
          // Green -> Yellow
          segColor = Color.lerp(
            const Color(0xFF00FF88),
            const Color(0xFFFFAA00),
            t * 2,
          )!;
        } else {
          // Yellow -> Red
          segColor = Color.lerp(
            const Color(0xFFFFAA00),
            const Color(0xFFFF2244),
            (t - 0.5) * 2,
          )!;
        }
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          segAngle,
          segmentSweep + 0.01,
          false,
          Paint()
            ..color = segColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 16
            ..strokeCap = StrokeCap.butt,
        );
      }
    }

    // Tick marks and speed labels
    _drawTicks(canvas, center, radius, size);

    // Needle
    _drawNeedle(canvas, center, radius, fraction);

    // Center dot
    canvas.drawCircle(
      center,
      8,
      Paint()..color = const Color(0xFF00D4FF),
    );
    canvas.drawCircle(
      center,
      4,
      Paint()..color = Colors.white,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius, Size size) {
    final labelSpeeds = [0, 20, 40, 60, 80, 100, 120];
    final majorTickPaint = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;
    final minorTickPaint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;

    // Minor ticks every 10
    for (int i = 0; i <= 120; i += 10) {
      final t = i / maxSpeed;
      final angle = _startAngle + _sweepAngle * t;
      final isMajor = labelSpeeds.contains(i);
      final outerR = radius - 18;
      final innerR = isMajor ? outerR - 12 : outerR - 7;
      canvas.drawLine(
        Offset(center.dx + outerR * cos(angle), center.dy + outerR * sin(angle)),
        Offset(center.dx + innerR * cos(angle), center.dy + innerR * sin(angle)),
        isMajor ? majorTickPaint : minorTickPaint,
      );
    }

    // Speed labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final spd in labelSpeeds) {
      final t = spd / maxSpeed;
      final angle = _startAngle + _sweepAngle * t;
      final labelR = radius - 48;
      textPainter.text = TextSpan(
        text: '$spd',
        style: const TextStyle(color: Colors.white54, fontSize: 14),
      );
      textPainter.layout();
      final dx = center.dx + labelR * cos(angle) - textPainter.width / 2;
      final dy = center.dy + labelR * sin(angle) - textPainter.height / 2;
      textPainter.paint(canvas, Offset(dx, dy));
    }
  }

  void _drawNeedle(Canvas canvas, Offset center, double radius, double fraction) {
    final angle = _startAngle + _sweepAngle * fraction;
    final needleLength = radius - 30;
    final tipX = center.dx + needleLength * cos(angle);
    final tipY = center.dy + needleLength * sin(angle);

    // Needle shadow
    canvas.drawLine(
      center,
      Offset(tipX, tipY),
      Paint()
        ..color = Colors.black45
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    // Needle
    canvas.drawLine(
      center,
      Offset(tipX, tipY),
      Paint()
        ..color = const Color(0xFF00D4FF)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SpeedometerPainter old) =>
      old.speed != speed || old.maxSpeed != maxSpeed;
}
