import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:enclavd/utils/image_bake.dart';

const List<double> _grayscale = [
  0.299, 0.587, 0.114, 0, 0,
  0.299, 0.587, 0.114, 0, 0,
  0.299, 0.587, 0.114, 0, 0,
  0, 0, 0, 1, 0,
];

void main() {
  // Small frames only: anything above _kInlinePixels would need a real
  // isolate, and widget-test time does not run one.
  final source = img.Image(width: 120, height: 90);
  img.fill(source, color: img.ColorRgb8(120, 40, 200));
  final png = Uint8List.fromList(img.encodePng(source));

  test('bakePickedBytes decodes a pure-Dart format and re-encodes as JPEG',
      () async {
    final baked = await bakePickedBytes(png, maxEdge: 1200);
    expect(baked.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    final decoded = img.decodeJpg(baked)!;
    expect(decoded.width, 120);
    expect(decoded.height, 90);
  });

  test('bakePickedBytes caps the longest edge', () async {
    final baked = await bakePickedBytes(png, maxEdge: 60);
    final decoded = img.decodeJpg(baked)!;
    expect(decoded.width, 60);
    expect(decoded.height, 45);
  });

  test('decodeAnyImage returns the RGBA frame at the requested cap', () async {
    final decoded = await decodeAnyImage(png, maxEdge: 60);
    expect(decoded.width, 60);
    expect(decoded.height, 45);
  });

  test('bakeCropAsync crops and applies the filter matrix in one pass',
      () async {
    final baked = await bakeCropAsync(source,
        x: 10,
        y: 10,
        width: 40,
        height: 30,
        filter: _grayscale);
    final decoded = img.decodeJpg(baked)!;
    expect(decoded.width, 40);
    expect(decoded.height, 30);
  });
}
