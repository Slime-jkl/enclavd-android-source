import 'package:flutter/material.dart';

/// Thread connector: a vertical rail that drops from the parent comment's
/// avatar and turns into a rounded L into each nested reply. One elbow
/// column per child row, sized by IntrinsicHeight so the rail spans the
/// row; the last child's rail stops at its elbow instead of running on.
///
/// Geometry contract (keep every host in sync):
/// - elbowY = the child avatar's VERTICAL CENTER measured from the row
///   top (avatar top padding + avatar size / 2).
/// - Child avatars are TOP-aligned with the comment block (same as the
///   parent), never vertically centered. EnclavdAvatar is pinned to its
///   own size (Align width/heightFactor 1), so rows must not re-center.
class ThreadElbow extends StatelessWidget {
  const ThreadElbow({
    super.key,
    required this.color,
    required this.elbowY,
    this.isLast = false,
    this.width = 18,
  });

  final Color color;
  final double elbowY;
  final bool isLast;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: CustomPaint(
        painter: ThreadElbowPainter(
          color: color,
          elbowY: elbowY,
          isLast: isLast,
        ),
      ),
    );
  }
}

class ThreadElbowPainter extends CustomPainter {
  ThreadElbowPainter({
    required this.color,
    required this.elbowY,
    this.isLast = false,
  });

  final Color color;
  final double elbowY;
  final bool isLast;

  static const double _radius = 6;
  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    final x = size.width / 2;
    final turnY = elbowY - _radius;
    // Vertical rail: stops above the elbow on the last child.
    canvas.drawLine(Offset(x, 0), Offset(x, isLast ? turnY : size.height),
        paint);

    // Rounded L into the child's header.
    final path = Path()
      ..moveTo(x, turnY)
      ..quadraticBezierTo(x, elbowY, x + _radius, elbowY)
      ..lineTo(size.width, elbowY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ThreadElbowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.elbowY != elbowY ||
      oldDelegate.isLast != isLast;
}
