import 'package:flutter/material.dart';

/// Resolution-independent rendering of our existing nirang-mark.svg paths.
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 30, super.key});
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'niraN',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BrandPainter()),
    ),
  );
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(24),
      ),
      Paint()..color = const Color(0xFF081A3A),
    );
    final stroke = Paint()
      ..color = const Color(0xFF13D8D1)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(28, 30)
        ..lineTo(28, 69)
        ..quadraticBezierTo(28, 82, 41, 82)
        ..lineTo(53, 82),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(34, 30)
        ..lineTo(76, 72)
        ..quadraticBezierTo(81, 77, 81, 66)
        ..lineTo(81, 30),
      stroke,
    );
    final dot = Paint()..color = const Color(0xFF13D8D1);
    for (final point in [
      const Offset(28, 30),
      const Offset(53, 82),
      const Offset(81, 30),
    ]) {
      canvas.drawCircle(point, 8, dot);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter old) => false;
}
