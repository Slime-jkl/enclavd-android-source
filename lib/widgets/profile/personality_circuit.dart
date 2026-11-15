import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The web profile's circuit artwork (`personality-circuit` in profile.php),
/// redrawn as a CustomPainter so the app carries the same identity without
/// adding an SVG package.
///
/// Coordinates are authored in the site's 800x260 viewBox and scaled with
/// `BoxFit.cover` semantics. The two coloured halves meet in the middle with
/// a soft collision glow, and short "pulses" trace along the viewer and
/// member paths.
class PersonalityCircuit extends StatelessWidget {
  const PersonalityCircuit({
    super.key,
    required this.viewerColor,
    required this.memberColor,
    required this.progress,
    this.blurSigma = 5,
    this.opacity = 0.75,
  });

  final Color viewerColor;
  final Color memberColor;

  /// 0..1 trace progress (the web runs this over 5.2s).
  final double progress;
  final double blurSigma;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final painted = CustomPaint(
      painter: _CircuitPainter(
        viewerColor: viewerColor,
        memberColor: memberColor,
        // A static frame at 55% when the user asked for reduced motion.
        progress: reduce ? 0.55 : progress,
        animate: !reduce,
      ),
      child: const SizedBox.expand(),
    );
    final faded = Opacity(
      opacity: opacity,
      child: blurSigma <= 0
          ? painted
          : ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: painted,
            ),
    );
    return IgnorePointer(child: faded);
  }
}

class _CircuitPainter extends CustomPainter {
  _CircuitPainter({
    required this.viewerColor,
    required this.memberColor,
    required this.progress,
    required this.animate,
  });

  final Color viewerColor;
  final Color memberColor;
  final double progress;
  final bool animate;

  static const List<List<Offset>> _viewerPaths = [
    [Offset(0, 32), Offset(96, 32), Offset(120, 56), Offset(250, 56), Offset(272, 78), Offset(400, 78)],
    [Offset(0, 108), Offset(64, 108), Offset(90, 82), Offset(214, 82), Offset(240, 108), Offset(400, 108)],
    [Offset(0, 188), Offset(88, 188), Offset(114, 162), Offset(262, 162), Offset(288, 188), Offset(400, 188)],
    [Offset(0, 62), Offset(42, 62), Offset(64, 84), Offset(144, 84)],
    [Offset(0, 148), Offset(52, 148), Offset(74, 126), Offset(156, 126)],
  ];

  static const List<Offset> _viewerNodes = [
    Offset(120, 56),
    Offset(272, 78),
    Offset(90, 82),
    Offset(240, 108),
    Offset(114, 162),
    Offset(288, 188),
    Offset(64, 84),
    Offset(74, 126),
  ];

  /// Which traced paths carry a pulse and their stagger, matching the site's
  /// delays (0/.28/.56 viewer, .14/.42/.70 member).
  static const List<double> _viewerPulseDelays = [0, 0.28, 0.56];
  static const List<double> _memberPulseDelays = [0.14, 0.42, 0.70];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final scale = math.max(size.width / 800, size.height / 260);
    final dx = (size.width - 800 * scale) / 2;
    final dy = (size.height - 260 * scale) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    _paintHalf(canvas, viewerColor, mirror: false);
    _paintHalf(canvas, memberColor, mirror: true);
    _paintCollision(canvas);
    canvas.restore();
  }

  void _paintHalf(Canvas canvas, Color color, {required bool mirror}) {
    List<List<Offset>> paths = _viewerPaths;
    List<Offset> nodes = _viewerNodes;
    if (mirror) {
      paths = [
        for (final p in _viewerPaths)
          [for (final o in p) Offset(800 - o.dx, o.dy)],
      ];
      nodes = [for (final n in _viewerNodes) Offset(800 - n.dx, n.dy)];
    }

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.20);
    for (final points in paths) {
      canvas.drawPath(_path(points), base);
    }

    final nodePaint = Paint()..color = color.withValues(alpha: 0.30);
    for (final node in nodes) {
      canvas.drawCircle(node, 3.4, nodePaint);
    }

    final delays = mirror ? _memberPulseDelays : _viewerPulseDelays;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: animate ? 0.95 : 0.55);
    for (var i = 0; i < delays.length; i++) {
      final metric = _path(paths[i]).computeMetrics().first;
      final length = metric.length;
      final head = ((progress - delays[i]) % 1 + 1) % 1;
      final start = head * length;
      final segment = metric.extractPath(start, start + length * 0.22);
      canvas.drawPath(segment, pulsePaint);
    }
  }

  void _paintCollision(Canvas canvas) {
    final t = (progress * 2 * math.pi);
    final pulse = 0.5 - 0.5 * math.cos(t);
    final alpha = animate ? (0.08 + 0.47 * pulse) : 0.24;
    final scale = animate ? (0.85 + 0.30 * pulse) : 1.0;
    const center = Offset(400, 130);
    final radius = 34 * scale;

    final paint = Paint()
      ..color = Color.lerp(viewerColor, memberColor, 0.5)!
          .withValues(alpha: alpha)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(center, radius, paint);
    // Two offset lobes give the clash its two-colour edge.
    canvas.drawCircle(
      center.translate(-radius * 0.45, 0),
      radius * 0.8,
      Paint()
        ..color = viewerColor.withValues(alpha: alpha * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(
      center.translate(radius * 0.45, 0),
      radius * 0.8,
      Paint()
        ..color = memberColor.withValues(alpha: alpha * 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  Path _path(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_CircuitPainter old) =>
      old.progress != progress ||
      old.viewerColor != viewerColor ||
      old.memberColor != memberColor ||
      old.animate != animate;
}
