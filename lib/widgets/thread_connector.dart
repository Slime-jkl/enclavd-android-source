import 'package:flutter/material.dart';

/// Thread connector: a vertical rail that drops from the parent comment's
/// avatar and turns into a rounded L toward each nested reply. One elbow
/// column per child row, sized by IntrinsicHeight so the rail spans the
/// row; the last child's rail stops at its elbow instead of running on.
///
/// Geometry contract (keep every host in sync):
/// - The child block is FLUSH (no indent) and the elbow column is 28
///   wide, so the rail x = width / 2 = 14 == the parent avatar's center.
///   The stem hangs from the parent avatar's MIDDLE, not its rim.
/// - elbowY = the child avatar's VERTICAL CENTER measured from the row
///   top (avatar top padding + avatar size / 2 = 20 for 28px avatars).
/// - Both ends stay clear of the avatars: the host's RailDrop starts 4
///   below the parent avatar bottom (startY = top pad + size + 4), and
///   the elbow arm stops _endGap (4) short of the child avatar. Round
///   caps make the floating ends read as deliberate, not broken.
/// - Child avatars are TOP-aligned with the comment block (same as the
///   parent), never vertically centered. EnclavdAvatar is pinned to its
///   own size (Align width/heightFactor 1), so rows must not re-center.
class ThreadElbow extends StatelessWidget {
  const ThreadElbow({
    super.key,
    required this.color,
    required this.elbowY,
    this.isLast = false,
    this.width = 28,
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

  /// Air gap between the arm tip and the child avatar's rim: the elbow
  /// column ends flush with the avatar, so the L stops short and the
  /// round cap reads as a floating connector instead of a stab.
  static const double _endGap = 4;

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

    // Rounded L toward the child's header; the arm stops short of the
    // avatar so the connector keeps a gap at both ends.
    final path = Path()
      ..moveTo(x, turnY)
      ..quadraticBezierTo(x, elbowY, x + _radius, elbowY)
      ..lineTo(size.width - _endGap, elbowY);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(ThreadElbowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.elbowY != elbowY ||
      oldDelegate.isLast != isLast;
}

/// Vertical rail segment painted inside the parent row/card of an OPEN
/// reply group. It hangs the child rail from the parent avatar: the
/// host stacks it behind the row (comments) or over the card (threads,
/// where the card bg would hide it) and sizes it to the row/card box,
/// so the segment ends exactly where the first child's elbow column
/// starts.
class RailDrop extends StatelessWidget {
  const RailDrop({
    super.key,
    required this.color,
    required this.railX,
    required this.startY,
  });

  final Color color;

  /// Rail center x in the parent row/card's local space. Must match the
  /// child rail: the avatar starts at x 0, so railX = avatar size / 2
  /// puts the stem under the avatar's middle.
  final double railX;

  /// Y the segment begins, row/card-local: avatar bottom + gap (top pad
  /// + avatar size + 4) so the round cap floats clear of the circle
  /// instead of touching its rim.
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
