import 'package:flutter/material.dart';

import 'package:microscopeapp/core/theme/crystal_theme.dart';

class FramingGuide extends StatelessWidget {
  const FramingGuide({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _FramePainter()),
          Align(
            alignment: const Alignment(0, 0.72),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xCC0B1212),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Align the board inside the frame',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.12,
      size.width * 0.84,
      size.height * 0.62,
    );
    final bracket = Paint()
      ..color = crystalTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const length = 28.0;
    final corners = <List<Offset>>[
      [rect.topLeft, rect.topLeft + const Offset(length, 0), rect.topLeft + const Offset(0, length)],
      [rect.topRight, rect.topRight + const Offset(-length, 0), rect.topRight + const Offset(0, length)],
      [rect.bottomLeft, rect.bottomLeft + const Offset(length, 0), rect.bottomLeft + const Offset(0, -length)],
      [rect.bottomRight, rect.bottomRight + const Offset(-length, 0), rect.bottomRight + const Offset(0, -length)],
    ];
    for (final corner in corners) {
      canvas.drawLine(corner[0], corner[1], bracket);
      canvas.drawLine(corner[0], corner[2], bracket);
    }

    final hairline = Paint()
      ..color = crystalTeal.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    final center = rect.center;
    canvas.drawLine(center + const Offset(-10, 0), center + const Offset(10, 0), hairline);
    canvas.drawLine(center + const Offset(0, -10), center + const Offset(0, 10), hairline);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
