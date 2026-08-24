import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:enclavd/screens/image_editor_screen.dart';

/// The crop frame must always stay INSIDE the image. This mirrors the
/// provider's rendering: the image is contain-fit (centered) inside a
/// viewport-sized child; under scale s + translation (tx, ty) its rect in
/// viewport coords is [ox*s+tx, (ox+iw)*s+tx] × [oy*s+ty, (oy+ih)*s+ty].
void expectFrameInImage({
  required double imgW,
  required double imgH,
  required Size viewport,
  required Rect frame,
  required double scale,
  required double tx,
  required double ty,
}) {
  final fit = math.min(viewport.width / imgW, viewport.height / imgH);
  final iw = imgW * fit;
  final ih = imgH * fit;
  final ox = (viewport.width - iw) / 2;
  final oy = (viewport.height - ih) / 2;
  final imageRect = Rect.fromLTRB(
    ox * scale + tx,
    oy * scale + ty,
    (ox + iw) * scale + tx,
    (oy + ih) * scale + ty,
  );
  final inside = imageRect.left <= frame.left &&
      imageRect.top <= frame.top &&
      imageRect.right >= frame.right &&
      imageRect.bottom >= frame.bottom;
  expect(
    inside,
    isTrue,
    reason: 'frame $frame must stay inside image rect $imageRect',
  );
}

void main() {
  const viewport = Size(400, 400);

  group('clampCropTransform — zoom floor (image must cover the frame)', () {
    test('wide image in a square free-crop viewport starts zoomed to cover',
        () {
      // 1600x900 (16:9) contain-fit into 400x400: iw=400, ih=225, oy=87.5.
      // Free frame = viewport; min scale = max(400/400, 400/225) ≈ 1.78.
      final r = clampCropTransform(
        imgW: 1600,
        imgH: 900,
        viewport: viewport,
        frame: Offset.zero & viewport,
        scale: 1,
        tx: 0,
        ty: 0,
      );
      expect(r.scale, closeTo(16 / 9, 1e-9)); // 400 / 225
      expect(r.tx, closeTo(0, 1e-6),
          reason: 'image already spans the full width — tx stays valid');
      expect(r.ty, closeTo(-87.5 * r.scale, 1e-6),
          reason: 'letterbox offset scaled up — the image must slide up to '
              'cover the viewport height');
      expectFrameInImage(
          imgW: 1600,
          imgH: 900,
          viewport: viewport,
          frame: Offset.zero & viewport,
          scale: r.scale,
          tx: r.tx,
          ty: r.ty);
    });

    test('portrait image free-crop: zoom floor + both axes pinned', () {
      // 900x1600 contain-fit into 400x400: iw=225, ih=400, ox=87.5.
      final r = clampCropTransform(
        imgW: 900,
        imgH: 1600,
        viewport: viewport,
        frame: Offset.zero & viewport,
        scale: 0.5,
        tx: 50,
        ty: 50,
      );
      expect(r.scale, closeTo(16 / 9, 1e-9)); // 400 / 225
      expect(r.tx, closeTo(-87.5 * r.scale, 1e-6),
          reason: 'no horizontal slack — pinned to exactly cover');
      expect(r.ty, closeTo(0, 1e-6));
      expectFrameInImage(
          imgW: 900,
          imgH: 1600,
          viewport: viewport,
          frame: Offset.zero & viewport,
          scale: r.scale,
          tx: r.tx,
          ty: r.ty);
    });

    test('zoom above the max is pulled back', () {
      final r = clampCropTransform(
        imgW: 1600,
        imgH: 900,
        viewport: viewport,
        frame: Offset.zero & viewport,
        scale: 12,
        tx: -100,
        ty: -100,
        maxScale: 6,
      );
      expect(r.scale, 6);
      expectFrameInImage(
          imgW: 1600,
          imgH: 900,
          viewport: viewport,
          frame: Offset.zero & viewport,
          scale: r.scale,
          tx: r.tx,
          ty: r.ty);
    });
  });

  group('clampCropTransform — pan confined to the image', () {
    test('portrait image zoomed in: horizontal pan clamps both sides', () {
      // At scale 2 the image x-extent is [175+tx, 625+tx]; to keep the
      // viewport frame inside: tx ∈ [-225, -175].
      final left = clampCropTransform(
        imgW: 900,
        imgH: 1600,
        viewport: viewport,
        frame: Offset.zero & viewport,
        scale: 2,
        tx: -300,
        ty: -200,
      );
      expect(left.tx, closeTo(-225, 1e-6));

      final right = clampCropTransform(
        imgW: 900,
        imgH: 1600,
        viewport: viewport,
        frame: Offset.zero & viewport,
        scale: 2,
        tx: -100,
        ty: -100,
      );
      expect(right.tx, closeTo(-175, 1e-6));
      expectFrameInImage(
          imgW: 900,
          imgH: 1600,
          viewport: viewport,
          frame: Offset.zero & viewport,
          scale: right.scale,
          tx: right.tx,
          ty: right.ty);
    });

    test('16:9 frame on a 16:9 image: locked at cover, pans once zoomed',
        () {
      final frame = Rect.fromCenter(
          center: viewport.center(Offset.zero),
          width: 400,
          height: 225); // 16:9 frame, y ∈ [87.5, 312.5]

      // At exactly-cover scale there is no slack at all.
      final locked = clampCropTransform(
        imgW: 1600,
        imgH: 900,
        viewport: viewport,
        frame: frame,
        scale: 1,
        tx: 100,
        ty: 100,
      );
      expect(locked.scale, closeTo(1, 1e-9));
      expect(locked.tx, closeTo(0, 1e-6));
      expect(locked.ty, closeTo(0, 1e-6));

      // Zoomed to 2x, panning is bounded to the image again.
      final zoomed = clampCropTransform(
        imgW: 1600,
        imgH: 900,
        viewport: viewport,
        frame: frame,
        scale: 2,
        tx: 100,
        ty: 0,
      );
      expect(zoomed.tx, closeTo(0, 1e-6), reason: 'tx upper bound is 0');
      expect(zoomed.ty, closeTo(-87.5, 1e-6),
          reason: 'ty upper bound is -87.5 (frame top vs image top at 2x)');
      expectFrameInImage(
          imgW: 1600,
          imgH: 900,
          viewport: viewport,
          frame: frame,
          scale: zoomed.scale,
          tx: zoomed.tx,
          ty: zoomed.ty);
    });
  });
}
