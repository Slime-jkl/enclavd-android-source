import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:gal/gal.dart';

import '../widgets/cached_image.dart';

/// Saves a remote image into the device gallery's Enclavd folder.
///
/// Bytes come from the disk cache when present (no re-download — the
/// cache stores the FULL-resolution originals; cacheWidth only downscales
/// at decode time). gal inserts via MediaStore (Pictures/Enclavd), which
/// needs no permission on Android 10+; legacy releases surface a
/// permission error we translate to a Settings hint.
///
/// The two platform-touching steps are injectable so the message matrix
/// is unit-testable without a device (widget tests hang on unhandled
/// platform channels).
class GallerySaver {
  GallerySaver({
    this.fetchBytes = CachedNetworkImageProvider.fetchBytes,
    this.saveBytes = Gal.putImageBytes,
  });

  /// Fetches the image bytes for a URL (cache-first, then download).
  final Future<Uint8List> Function(String url) fetchBytes;

  /// Persists image bytes into the gallery under the Enclavd album.
  final Future<void> Function(Uint8List bytes, {String? album}) saveBytes;

  static const String album = 'Enclavd';

  /// Saves [url] into the Enclavd gallery folder and returns a
  /// user-facing result message (never throws).
  Future<String> saveImage(String url) async {
    try {
      final bytes = await fetchBytes(url);
      await saveBytes(bytes, album: album);
      return 'Saved to the Enclavd folder in your gallery';
    } on PlatformException catch (e) {
      return e.code == 'permission_denied'
          ? 'Storage permission needed — allow it in Settings, then try again'
          : "Couldn't save the image.";
    } on HttpException {
      return "Couldn't download the image.";
    } catch (_) {
      return "Couldn't save the image.";
    }
  }
}
