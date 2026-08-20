import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// Port of the site's image-editor filters (post_form.php IED_FILTERS) —
/// CSS filter strings compiled to 4×5 color matrices (row-major, the
/// Flutter ColorFilter.matrix layout). The SAME matrix drives the live
/// preview (ColorFilter.matrix on the widget) and the baked output
/// (per-pixel loop via package:image), so what you see is what uploads.
class IedFilter {
  const IedFilter(this.id, this.label, this.css);

  final String id;
  final String label;
  final String css;

  /// Combined 4x5 matrix (20 entries); identity for css ''.
  List<double> matrix() => _compile(css);

  static const List<IedFilter> presets = [
    IedFilter('normal', 'Normal', ''),
    IedFilter('clarendon', 'Clarendon', 'contrast(1.2) saturate(1.35)'),
    IedFilter('gingham', 'Gingham',
        'brightness(1.05) hue-rotate(-10deg) saturate(.85)'),
    IedFilter('moon', 'Moon', 'grayscale(1) brightness(1.1) contrast(1.1)'),
    IedFilter('lark', 'Lark', 'brightness(1.1) contrast(.9) saturate(1.2)'),
    IedFilter('reyes', 'Reyes',
        'sepia(.35) brightness(1.1) contrast(.85) saturate(.75)'),
    IedFilter('juno', 'Juno', 'saturate(1.4) contrast(1.1) hue-rotate(-5deg)'),
    IedFilter('slumber', 'Slumber', 'saturate(.66) brightness(1.05) sepia(.2)'),
    IedFilter('crema', 'Crema', 'sepia(.2) saturate(.85) brightness(1.05)'),
    IedFilter('inkwell', 'Inkwell', 'grayscale(1) sepia(.1) contrast(1.1)'),
    IedFilter('aden', 'Aden',
        'hue-rotate(-20deg) contrast(.9) saturate(.85) brightness(1.2)'),
    IedFilter('vivid', 'Vivid', 'saturate(2) contrast(1.1)'),
    IedFilter('fade', 'Fade', 'opacity(.85) brightness(1.1) saturate(.7)'),
    IedFilter(
        'mav', 'Maverick', 'hue-rotate(30deg) saturate(1.2) brightness(.95)'),
  ];

  /// Bakes the matrix into an image (mutates it). Used at Apply time —
  /// identical math to the ColorFilter.matrix preview.
  static void applyToImage(img.Image image, List<double> m) {
    for (final p in image) {
      final r = p.r.toDouble();
      final g = p.g.toDouble();
      final b = p.b.toDouble();
      final a = p.a.toDouble();
      p
        ..r = _clamp(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4])
        ..g = _clamp(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9])
        ..b = _clamp(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14])
        ..a = _clamp(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]);
    }
  }

  static int _clamp(double v) => v.round().clamp(0, 255);
}

// ── CSS filter → matrix ──────────────────────────────────────────────────

/// 'contrast(1.2) saturate(1.35)' → combined matrix (ops applied in order).
List<double> _compile(String css) {
  var m = _identity;
  final re = RegExp(r'(\w+)\(([^)]*)\)');
  for (final match in re.allMatches(css)) {
    final op = match.group(1)!;
    final raw = match.group(2)!.trim();
    final num = double.tryParse(raw.replaceAll(RegExp(r'deg$'), '')) ?? 1;
    final deg = raw.endsWith('deg') ? num * math.pi / 180 : null;
    final next = switch (op) {
      'brightness' => _brightness(num),
      'contrast' => _contrast(num),
      'saturate' => _saturate(num),
      'grayscale' => _saturate(0),
      'sepia' => _sepia(num),
      'hue-rotate' => _hueRotate(deg ?? 0),
      'opacity' => _opacity(num),
      _ => _identity,
    };
    m = _multiply(next, m);
  }
  return m;
}

final List<double> _identity = [
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0, //
];

List<double> _brightness(double b) => [
      b, 0, 0, 0, 0, //
      0, b, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

List<double> _contrast(double c) => [
      c, 0, 0, 0, 127.5 * (1 - c), //
      0, c, 0, 0, 127.5 * (1 - c), //
      0, 0, c, 0, 127.5 * (1 - c), //
      0, 0, 0, 1, 0, //
    ];

List<double> _saturate(double s) => [
      0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0, //
      0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];

/// Sepia at `amount` (0..1), blended with identity — matches CSS
/// sepia(.35) which is a partial effect.
List<double> _sepia(double amount) {
  const full = [
    0.393, 0.769, 0.189, //
    0.349, 0.686, 0.168, //
    0.272, 0.534, 0.131, //
  ];
  final m = List<double>.filled(20, 0);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      m[row * 5 + col] =
          amount * full[row * 3 + col] + (1 - amount) * (row == col ? 1 : 0);
    }
    m[row * 5 + 3] = 0;
    m[row * 5 + 4] = 0;
  }
  m[15] = 0;
  m[16] = 0;
  m[17] = 0;
  m[18] = 1;
  m[19] = 0;
  return m;
}

List<double> _hueRotate(double rad) {
  final a = math.cos(rad);
  final b = math.sin(rad);
  return [
    0.213 + 0.787 * a - 0.213 * b, 0.715 - 0.715 * a - 0.715 * b,
    0.072 - 0.072 * a + 0.928 * b, 0, 0, //
    0.213 - 0.213 * a + 0.143 * b, 0.715 + 0.285 * a + 0.140 * b,
    0.072 - 0.072 * a - 0.283 * b, 0, 0, //
    0.213 - 0.213 * a - 0.787 * b, 0.715 - 0.715 * a + 0.715 * b,
    0.072 + 0.928 * a + 0.072 * b, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// CSS opacity(a) over the site's dark card background: RGB blends toward
/// gray-900 (#111827) by (1-a). (JPEG has no alpha channel, so this bakes
/// the visual result instead of encoding transparency.)
List<double> _opacity(double a) => [
      a, 0, 0, 0, 17 * (1 - a), //
      0, a, 0, 0, 24 * (1 - a), //
      0, 0, a, 0, 39 * (1 - a), //
      0, 0, 0, 1, 0, //
    ];

/// b = a × b (matrices applied right-to-left like CSS filter chains).
List<double> _multiply(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += a[row * 5 + k] * b[k * 5 + col];
      }
      // The translation column of the product also carries A's own offset
      // (standard 4x5 matrix multiplication).
      if (col == 4) v += a[row * 5 + 4];
      out[row * 5 + col] = v;
    }
  }
  return out;
}
