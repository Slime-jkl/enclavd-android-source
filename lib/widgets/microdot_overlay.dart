import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart' show AppServices;

/// Port of the site's components/microdot.php: while logged in, a faint
/// full-screen, click-through watermark tiles `* <user id> *` diagonally
/// over every screen, so a leaked screenshot can be traced back to the
/// account that took it.
///
/// Site parity: 200x120 tile, 12px bold text, grey #808080 at 2%
/// opacity, rotated -20°, pointer-events none. It lives in
/// MaterialApp.builder — above the Navigator — so it covers every route
/// and dialog, exactly like the site's fixed z-999999 layer.
///
/// The user id resolves from the live service container. The app root
/// builds BEFORE the splash creates the container, and login re-creates
/// it, so this widget watches for container changes and probes
/// /api/v1/me on each new one. Best-effort: any failure just leaves the
/// watermark off (no crash, no retry spam — probes only on change).
class MicrodotOverlay extends StatefulWidget {
  const MicrodotOverlay({super.key, this.resolveUserId});

  /// Injectable for tests; defaults to the live container's auth.me().
  final Future<int?> Function()? resolveUserId;

  @override
  State<MicrodotOverlay> createState() => _MicrodotOverlayState();
}

class _MicrodotOverlayState extends State<MicrodotOverlay> {
  int? _userId;
  AppServices? _lastContainer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final resolve = widget.resolveUserId;
    if (resolve != null) {
      final id = await resolve();
      if (mounted) setState(() => _userId = id);
      return;
    }
    while (mounted) {
      final services = AppServices.current;
      if (services != null && !identical(services, _lastContainer)) {
        _lastContainer = services;
        try {
          final user = await services.auth.me();
          if (!mounted) return;
          if (user != null) {
            setState(() => _userId = user.id);
            return;
          }
        } catch (_) {
          // Offline or transient — re-probe on the next container change.
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = _userId;
    if (id == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: MicrodotPainter('* $id *'),
        ),
      ),
    );
  }
}

/// Paints the tiled diagonal watermark. Public so tests can assert the
/// label and presence without pixel inspection.
class MicrodotPainter extends CustomPainter {
  MicrodotPainter(this.label);

  final String label;

  /// Site tile: 200x120, text centered, rotated -20° around the tile
  /// centre (microdot.php: `rotate(-20 100 60)`).
  static const double tileWidth = 200;
  static const double tileHeight = 120;

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0x05808080), // rgba(128,128,128,0.02)
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    for (double y = 0; y < size.height; y += tileHeight) {
      for (double x = 0; x < size.width; x += tileWidth) {
        canvas.save();
        canvas.translate(x + tileWidth / 2, y + tileHeight / 2);
        canvas.rotate(-20 * math.pi / 180);
        textPainter.paint(
            canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(MicrodotPainter oldDelegate) =>
      oldDelegate.label != label;
}
