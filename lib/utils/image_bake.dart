import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The site's MAX output dimension (the web editor's export cap).
const int kMaxPostImageEdge = 1200;

/// Post image bake, site parity: bounded to [maxEdge] on its longest side,
/// JPEG q85. The image editor's export and the composer's multi-image picks
/// both end here, so every attached file is the same shape.
Uint8List bakeJpeg(img.Image source, {int maxEdge = kMaxPostImageEdge}) {
  var out = source;
  final longest = math.max(out.width, out.height);
  if (longest > maxEdge) {
    final scale = maxEdge / longest;
    out = img.copyResize(
      out,
      width: (out.width * scale).round(),
      height: (out.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

/// Decode and bake a picked file in one step. Android 13+ hands back raw
/// multi-megabyte camera output (the picker ignores its own maxWidth and
/// quality), and PHP drops the whole POST when the body outgrows
/// post_max_size, so every picked image goes through here before it is
/// attached. Throws [FormatException] when the bytes are not an image.
Uint8List bakePickedBytes(Uint8List bytes,
    {int maxEdge = kMaxPostImageEdge}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported image file');
  }
  return bakeJpeg(decoded, maxEdge: maxEdge);
}
