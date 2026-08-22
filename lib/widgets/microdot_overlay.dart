import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart' show AppServices;

/// The user id resolves from the live service container. The app root
/// builds BEFORE the splash creates the container, and login re-creates
/// it, so this widget watches for container changes and probes
/// /api/v1/me on each new one. Best-effort: any failure just leaves the
/// watermark off (no crash, no retry spam - probes only on change).
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
          // Offline or transient - re-probe on the next container change.
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

  /// Jitter amplitude (px). Big enough to break the periodic grid, small
  /// enough that neighbouring tiles (200x120) can never collide.
  static const double _jitterRange = 12;

  /// Deterministic pseudo-random offset for tile (tx, ty), so the tiling
  /// reads as faint noise instead of a regular texture (the eye catches
  /// periodic patterns far more easily than scattered ones). Pure
  /// function of the tile indices - stable across repaints, no shimmer.
  static Offset _tileJitter(int tx, int ty) {
    var h = (tx * 0x9E3779B1 ^ ty * 0x85EBCA77) & 0x7FFFFFFF;
    h = ((h ^ (h >> 13)) * 0x5BD1E995) & 0x7FFFFFFF;
    h ^= h >> 15;
    final dx = h % 25 - _jitterRange; // -12..12 px
    final dy = (((h * 0x9E3779B1) & 0x7FFFFFFF) % 25) - _jitterRange;
    return Offset(dx.toDouble(), dy.toDouble());
  }

  @override
  void paint(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0x03808080), // 0.012 alpha - site uses 0.02; see class doc
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    var ty = 0;
    for (double y = 0; y < size.height; y += tileHeight, ty++) {
      var tx = 0;
      for (double x = 0; x < size.width; x += tileWidth, tx++) {
        final jitter = _tileJitter(tx, ty);
        canvas.save();
        canvas.translate(x + tileWidth / 2 + jitter.dx,
            y + tileHeight / 2 + jitter.dy);
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
