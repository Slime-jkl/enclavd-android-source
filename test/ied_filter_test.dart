import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:enclavd/utils/ied_filter.dart';

void main() {
  group('IedFilter.matrix', () {
    test('normal is the identity matrix', () {
      final m = IedFilter.presets.first.matrix();
      expect(m, hasLength(20));
      for (var i = 0; i < 20; i++) {
        final row = i ~/ 5;
        final col = i % 5;
        expect(m[i], closeTo(row == col ? 1.0 : 0.0, 1e-9), reason: 'entry $i');
      }
    });

    test('clarendon chains contrast(1.2) then saturate(1.35)', () {
      final m =
          IedFilter.presets.firstWhere((f) => f.id == 'clarendon').matrix();
      // Saturated R-row starts 0.213+0.787*1.35; contrast(1.2) scales it.
      expect(m[0], closeTo((0.213 + 0.787 * 1.35) * 1.2, 1e-6));
    });

    test('fade chains opacity -> brightness -> saturate with bg blend', () {
      final m = IedFilter.presets.firstWhere((f) => f.id == 'fade').matrix();
      // saturate(.7) R-row: 0.213+0.787*.7; x brightness 1.1 x opacity .85.
      expect(m[0], closeTo((0.213 + 0.787 * 0.7) * 1.1 * 0.85, 1e-6));
      // Opacity blends RGB toward the dark card bg, so every RGB row carries
      // a non-zero translation (JPEG-safe bake).
      expect(m[4], greaterThan(0));
      expect(m[9], greaterThan(0));
      expect(m[14], greaterThan(0));
    });

    test('hue-rotate converts deg to radians', () {
      final m = filterById('mav').matrix();
      // hue-rotate(30deg) -> cross-channel terms (a non-diagonal row).
      expect(m[1], isNot(closeTo(0.0, 1e-9)));
    });

    test('applyToImage bakes the matrix into pixels (clamped)', () {
      final image = img.Image(width: 8, height: 8);
      img.fill(image, color: img.ColorRgb8(100, 150, 200));
      final before = image.getPixel(0, 0).r.toInt();

      IedFilter.applyToImage(image, filterById('clarendon').matrix());
      final after = image.getPixel(0, 0).r.toInt();

      expect(after, isNot(before));
      expect(after, inInclusiveRange(0, 255));
    });

    test('encode->decode roundtrip preserves the baked filter (lossy ok)', () {
      final image = img.Image(width: 8, height: 8);
      img.fill(image, color: img.ColorRgb8(120, 90, 60));
      // Moon = pure grayscale (no sepia tint), so channels are EQUAL
      // before the lossy JPEG encode.
      IedFilter.applyToImage(image, filterById('moon').matrix());

      final px = image.getPixel(0, 0);
      expect(px.r.toInt(), px.g.toInt());
      expect(px.g.toInt(), px.b.toInt());

      final bytes = img.encodeJpg(image, quality: 85);
      final decoded = img.decodeJpg(bytes);
      expect(decoded, isNotNull);
      // JPEG chroma subsampling re-introduces small channel deltas.
      final d = decoded!.getPixel(0, 0);
      expect((d.r.toInt() - d.g.toInt()).abs(), lessThanOrEqualTo(15));
      expect((d.g.toInt() - d.b.toInt()).abs(), lessThanOrEqualTo(15));
    });
  });
}

IedFilter filterById(String id) =>
    IedFilter.presets.firstWhere((f) => f.id == id);
