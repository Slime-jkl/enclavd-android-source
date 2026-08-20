import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// A disk-backed ImageProvider for remote images.
///
/// Why: the feed renders the same avatars and gallery images over and over.
/// Flutter's in-memory ImageCache helps within a session, but every cold
/// start re-downloads everything. This provider caches the raw bytes on
/// disk (app cache dir) so the second launch is instant and offline-ish.
///
/// Design notes:
///  - Raw bytes cached, decoding left to the framework's ImageCache (so
///    memory is still managed by the standard cache, and cacheWidth can
///    downscale at decode time).
///  - TTL + max-age sweep keep the cache bounded (images on the site are
///    immutable — 1-year cache headers — so staleness is a non-issue; we
///    still cap the directory size).
///  - Errors fall through to the caller's errorBuilder (e.g. default avatar).
class CachedNetworkImageProvider extends ImageProvider<CachedNetworkImageProvider> {
  CachedNetworkImageProvider(this.url, {this.httpClientFactory});

  final String url;

  /// Injectable for tests; defaults to a plain HttpClient.
  final HttpClient Function()? httpClientFactory;

  static const int _maxAgeDays = 14;
  static const int _maxFiles = 300;

  @override
  Future<CachedNetworkImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _loadAsync(
    CachedNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    try {
      final bytes = await _cachedBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      // Surface the error to the caller's errorBuilder instead of hanging.
      throw Exception('Failed to load image: $url ($e)');
    }
  }

  Future<Uint8List> _cachedBytes() async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/${_fileName()}');

    if (await file.exists()) {
      final age = DateTime.now().difference(await file.lastModified());
      if (age.inDays < _maxAgeDays) {
        return file.readAsBytes();
      }
    }

    final client = (httpClientFactory ?? _defaultClient)();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('GET $url → ${response.statusCode}');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes, flush: true);
      await _sweep(dir);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<Directory> _cacheDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/enclavd_img');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _fileName() {
    final hash = sha1Of(url);
    // Keep the original extension so the decoder can sniff format easily.
    final ext = _extensionOf(url);
    return '$hash.$ext';
  }

  /// FNV-1a 64-bit hex — stable across runs (unlike String.hashCode).
  static String sha1Of(String input) {
    final bytes = utf8.encode(input);
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _extensionOf(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot > path.length - 5) return 'bin';
    final ext = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,4}$').hasMatch(ext) ? ext : 'bin';
  }

  /// Bounded cache: delete oldest files beyond the cap.
  Future<void> _sweep(Directory dir) async {
    try {
      final files = await dir.list().toList();
      if (files.length <= _maxFiles) return;
      files.sort((a, b) {
        final am = File(a.path).lastModifiedSync();
        final bm = File(b.path).lastModifiedSync();
        return am.compareTo(bm);
      });
      for (final f in files.take(files.length - _maxFiles)) {
        await f.delete();
      }
    } catch (_) {
      // Sweep is best-effort; never block an image load on it.
    }
  }

  static HttpClient _defaultClient() => HttpClient();

  @override
  bool operator ==(Object other) =>
      other is CachedNetworkImageProvider && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedNetworkImageProvider($url)';
}
