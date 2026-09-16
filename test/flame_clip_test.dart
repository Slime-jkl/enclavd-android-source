import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:enclavd/widgets/ignite_flame_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

/// The animation's content is scaled past its own frame, so it must be clipped
/// to the card: a short card was the case where it spilled over the edges.
void main() {
  testWidgets('the flame never paints outside the card', (tester) async {
    const canvas = 300.0;
    const cardW = 160.0;
    const cardH = 90.0;
    const padX = 70.0;
    const padY = 105.0;
    const outside = Color(0xFFFFFFFF);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: outside,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: canvas,
                height: canvas,
                color: outside,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: padX,
                      top: padY,
                      child: Container(
                        width: cardW,
                        height: cardH,
                        color: outside,
                        child: const IgniteFlameOverlay(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 20 && find.byType(Lottie).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.byType(Lottie), findsOneWidget, reason: 'the vortex decoded');

    await tester.pump(const Duration(milliseconds: 300));

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    late ByteData pixels;
    late int width;
    late int height;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      width = image.width;
      height = image.height;
      pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });

    var stray = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final onCard = x >= padX &&
            x < padX + cardW &&
            y >= padY &&
            y < padY + cardH;
        if (onCard) continue;
        final o = (y * width + x) * 4;
        final delta = (pixels.getUint8(o) - 255).abs() +
            (pixels.getUint8(o + 1) - 255).abs() +
            (pixels.getUint8(o + 2) - 255).abs();
        if (delta > 24) stray++;
      }
    }

    expect(stray, 0, reason: 'flame pixels outside the card: $stray');
  });
}
