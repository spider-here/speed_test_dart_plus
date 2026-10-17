import 'dart:math';

import 'package:flutter/material.dart';

/// Semicircle gauge driven by a live speed in Mb/s.
class Speedometer extends StatefulWidget {
  const Speedometer({required this.mbps, super.key});

  final double mbps;

  @override
  State<Speedometer> createState() => _SpeedometerState();
}

class _SpeedometerState extends State<Speedometer> {
  static const _stops = <double>[10, 25, 50, 100, 250, 500, 1000];

  double _max = 10;

  void _fitScale(double mbps) {
    for (final stop in _stops) {
      if (stop <= _max) continue;
      if (mbps <= _max * 0.92) break;
      _max = stop;
    }
  }

  @override
  void initState() {
    super.initState();
    _fitScale(widget.mbps);
  }

  @override
  void didUpdateWidget(Speedometer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mbps == 0 && oldWidget.mbps != 0) {
      _max = 10;
    }
    _fitScale(widget.mbps);
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 180),
      tween: Tween<double>(end: widget.mbps.clamp(0, _max).toDouble()),
      builder: (context, needle, _) {
        return SizedBox(
          width: 260,
          height: 170,
          child: CustomPaint(
            painter: _GaugePainter(needle: needle, maxSpeed: _max),
            child: Align(
              alignment: const Alignment(0, 0.45),
              child: Text(
                '${widget.mbps.toStringAsFixed(1)}\nMb/s',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.needle, required this.maxSpeed});

  static final Paint _trackPaint = Paint()
    ..color = const Color(0xFFE0E0E0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14
    ..strokeCap = StrokeCap.round;

  static final Paint _valuePaint = Paint()
    ..color = const Color(0xFF1565C0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 14
    ..strokeCap = StrokeCap.round;

  static final Paint _needlePaint = Paint()
    ..color = const Color(0xFF212121)
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  static final Paint _hubPaint = Paint()..color = const Color(0xFF212121);

  final double needle;
  final double maxSpeed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 16);
    final radius = min(size.width / 2 - 18, size.height - 28);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final t = maxSpeed == 0
        ? 0.0
        : (needle / maxSpeed).clamp(0.0, 1.0).toDouble();

    canvas
      ..drawArc(rect, pi, pi, false, _trackPaint)
      ..drawArc(rect, pi, pi * t, false, _valuePaint);

    final angle = pi + pi * t;
    final needleEnd = Offset(
      center.dx + cos(angle) * (radius - 8),
      center.dy + sin(angle) * (radius - 8),
    );
    canvas
      ..drawLine(center, needleEnd, _needlePaint)
      ..drawCircle(center, 6, _hubPaint);

    _label(canvas, '0', Offset(center.dx - radius + 10, center.dy - 6));
    _label(
      canvas,
      maxSpeed.toStringAsFixed(0),
      Offset(center.dx + radius - 10, center.dy - 6),
    );
  }

  void _label(Canvas canvas, String text, Offset at) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF616161), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(at.dx - painter.width / 2, at.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_GaugePainter oldDelegate) {
    return oldDelegate.needle != needle || oldDelegate.maxSpeed != maxSpeed;
  }
}
