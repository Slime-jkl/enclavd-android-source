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
/// - The parent row/card above an open group paints a RailDrop at the
///   SAME x as the child rail (children indent + elbow width / 2), from
///   the parent avatar's rim down to its own bottom edge, so the rail
///   reads as hanging off the avatar instead of floating under the card.
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

/// Vertical rail segment painted inside the parent row/card of an OPEN
/// reply group. It carries the child rail up from the parent avatar's
/// rim so the L reads as hanging off it; the host stacks it behind the
/// row (comments) or over the card (threads, where the card bg would
/// hide it) and sizes it to the row/card box, margins included, so the
/// segment ends exactly where the first child's elbow column starts.
class RailDrop extends StatelessWidget {
  const RailDrop({
    super.key,
    required this.color,
    required this.railX,
    required this.startY,
  });

  final Color color;

  /// Rail center x in the parent row/card's local space. Must match the
  /// child rail: children indent + ThreadElbow width / 2.
  final double railX;

  /// Y the segment begins, row/card-local: at the avatar's bottom rim so
  /// the round cap meets it (a hair inside the box for round avatars,
  /// just past it when the segment paints over a bordered square).
  final double startY;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RailDropPainter(color: color, railX: railX, startY: startY),
      child: const SizedBox.expand(),
    );
  }
}

class _RailDropPainter extends CustomPainter {
  _RailDropPainter({
    required this.color,
    required this.railX,
    required this.startY,
  });

  final Color color;
  final double railX;
  final double startY;

  static const double _stroke = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(railX, startY), Offset(railX, size.height), paint);
  }

  @override
  bool shouldRepaint(_RailDropPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.railX != railX ||
      oldDelegate.startY != startY;
}
