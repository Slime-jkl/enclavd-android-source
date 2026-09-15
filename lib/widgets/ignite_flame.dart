import 'package:flutter/material.dart';

/// The lit fire, painted instead of loaded: a small flame that flickers.
///
/// Native on purpose. The site plays a Lottie file because a browser has no
/// flame of its own; the app would have to ship an animation runtime for one
/// icon. Layers of gradient tongues read the same at 20px and cost nothing.
class IgniteFlame extends StatefulWidget {
  const IgniteFlame({
    super.key,
    required this.color,
    this.size = 20,
    this.animate = true,
  });

  /// Fire colour: the theme's ignite accent (orange).
  final Color color;

  /// Height in logical pixels; the width follows the flame's own ratio.
  final double size;

  /// Off renders the same shape as a still frame (dialogs, tests).
  final bool animate;

  @override
  State<IgniteFlame> createState() => _IgniteFlameState();
}

class _IgniteFlameState extends State<IgniteFlame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _flicker.repeat(reverse: true);
    } else {
      _flicker.value = 0.5;
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.size * 0.74;
    // Decoration only: taps belong to the row underneath.
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: width,
          height: widget.size,
          child: AnimatedBuilder(
            animation: _flicker,
            builder: (context, _) => CustomPaint(
              size: Size(width, widget.size),
              painter: _FlamePainter(
                phase: _flicker.value,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({required this.phase, required this.color});

  /// 0..1, ping-ponged by the controller.
  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sway = (phase - 0.5) * 2; // -1 .. 1

    // Outer tongue: the accent colour, brightest at the base.
    _tongue(
      canvas,
      size,
      scale: 1,
      lift: 0,
      sway: sway,
      paint: Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.10)!,
            color,
          ],
        ).createShader(Offset.zero & size),
    );

    // Core and hot centre lean the other way, so the layers shimmer against
    // each other instead of moving as one blob.
    _tongue(
      canvas,
      size,
      scale: 0.66 + 0.04 * sway,
      lift: size.height * 0.02,
      sway: -sway * 0.6,
      paint: Paint()..color = const Color(0xFFFCD34D),
    );
    _tongue(
      canvas,
      size,
      scale: 0.36 + 0.03 * sway,
      lift: size.height * 0.06,
      sway: sway * 0.3,
      paint: Paint()..color = const Color(0xFFFFF7E6),
    );
  }

  void _tongue(
    Canvas canvas,
    Size size, {
    required double scale,
    required double lift,
    required double sway,
    required Paint paint,
  }) {
    final w = size.width * scale;
    final h = size.height * scale;
    canvas.save();
    canvas.translate((size.width - w) / 2, size.height - h - lift);
    canvas.drawPath(_flamePath(w, h, sway), paint);
    canvas.restore();
  }

  /// A flame silhouette in a [w] x [h] box: rounded base, tip leaning with
  /// [sway].
  Path _flamePath(double w, double h, double sway) {
    final cx = w / 2;
    final tipX = cx + sway * w * 0.16;
    final tipY = h * 0.03;
    return Path()
      ..moveTo(cx - w * 0.30, h * 0.90)
      ..cubicTo(cx - w * 0.58, h * 0.72, cx - w * 0.36, h * 0.50, tipX, tipY)
      ..cubicTo(cx + w * 0.36, h * 0.50, cx + w * 0.58, h * 0.72, cx + w * 0.30,
          h * 0.90)
      ..cubicTo(cx + w * 0.20, h, cx - w * 0.20, h, cx - w * 0.30, h * 0.90)
      ..close();
  }

  @override
  bool shouldRepaint(_FlamePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
