import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'ied_filter.dart';

/// The site's MAX output dimension (the web editor's export cap).
const int kMaxPostImageEdge = 1200;

/// Ceiling for a decode. A 12 MP camera frame is ~48 MB as RGBA and the
/// editor only ever exports 1200 px, so nothing above this is worth holding.
const int kMaxDecodeEdge = 2400;

/// Decode + bake work under this pixel count runs inline: it is a couple of
/// milliseconds, cheaper than shipping the buffer to another isolate.
const int _kInlinePixels = 100000;

/// The bytes are not an image (or one no available decoder knows how to read).
class ImageFormatException implements Exception {
  const ImageFormatException();

  @override
  String toString() => 'Unsupported image format';
}

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
      width: math.max(1, (out.width * scale).round()),
      height: math.max(1, (out.height * scale).round()),
      interpolation: img.Interpolation.cubic,
    );
  }
  return Uint8List.fromList(img.encodeJpg(out, quality: 85));
}

/// [bakeJpeg] off the UI thread. A full-size frame spends long enough in the
/// pure-Dart resize + JPEG encode to drop visible frames.
Future<Uint8List> bakeJpegAsync(img.Image source,
    {int maxEdge = kMaxPostImageEdge}) {
  if (source.width * source.height <= _kInlinePixels) {
    return Future.value(bakeJpeg(source, maxEdge: maxEdge));
  }
  return compute(
      _bakeJob, _BakeJob(source.getBytes(order: img.ChannelOrder.rgba),
          source.width, source.height, maxEdge));
}

/// Crop, filter and bake in one isolate hop: the editor's apply is a
/// per-pixel pass over a multi-megapixel frame, so none of it belongs on the
/// UI thread.
Future<Uint8List> bakeCropAsync(
  img.Image source, {
  required int x,
  required int y,
  required int width,
  required int height,
  List<double>? filter,
  int maxEdge = kMaxPostImageEdge,
}) {
  if (source.width * source.height <= _kInlinePixels) {
    final out = img.copyCrop(source, x: x, y: y, width: width, height: height);
    if (filter != null) IedFilter.applyToImage(out, filter);
    return Future.value(bakeJpeg(out, maxEdge: maxEdge));
  }
  return compute(
      _cropBakeJob,
      _CropJob(source.getBytes(order: img.ChannelOrder.rgba), source.width,
          source.height, x, y, width, height, filter, maxEdge));
}

/// Decode any format the device can read, scaled so the longest edge is at
/// most [maxEdge]. package:image handles the bulk of it (JPEG, PNG, WebP,
/// GIF, BMP, TIFF, TGA, QOI ...) off the UI thread for anything large, and
/// the platform's own decoder picks up the rest (HEIC/HEIF, AVIF), which is
/// where pure-Dart decoding used to fail outright.
Future<img.Image> decodeAnyImage(
  Uint8List bytes, {
  int maxEdge = kMaxDecodeEdge,
}) async {
  if (bytes.isEmpty) throw const ImageFormatException();

  final pixels = _probePixels(bytes);
  if (pixels != null) {
    if (pixels <= _kInlinePixels) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return _fit(decoded, maxEdge);
    } else {
      final raw = await compute(_decodeJob, _DecodeJob(bytes, maxEdge));
      if (raw != null) {
        return img.Image.fromBytes(
          width: raw.width,
          height: raw.height,
          bytes: raw.rgba.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
      }
    }
  }

  // A format package:image cannot parse, or a header it rejects.
  try {
    return await _decodeWithEngine(bytes, maxEdge);
  } on ImageFormatException {
    rethrow;
  } catch (_) {
    throw const ImageFormatException();
  }
}

/// Decode and bake a picked file in one step. Android 13+ hands back raw
/// multi-megabyte camera output (the picker ignores its own maxWidth and
/// quality), and PHP drops the whole POST when the body outgrows
/// post_max_size, so every picked image goes through here before it is
/// attached.
Future<Uint8List> bakePickedBytes(
  Uint8List bytes, {
  int maxEdge = kMaxPostImageEdge,
}) async {
  if (bytes.isEmpty) throw const ImageFormatException();

  final pixels = _probePixels(bytes);
  if (pixels != null) {
    if (pixels <= _kInlinePixels) {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) return bakeJpeg(decoded, maxEdge: maxEdge);
    } else {
      // One hop: decode, downscale and encode, so only a small JPEG crosses
      // back to the UI isolate.
      final baked =
          await compute(_decodeBakeJob, _DecodeBakeJob(bytes, maxEdge));
      if (baked != null) return baked;
    }
  }

  final decoded = await decodeAnyImage(bytes, maxEdge: kMaxDecodeEdge);
  return bakeJpegAsync(decoded, maxEdge: maxEdge);
}

/// Pixel count from the file header (cheap), or null when no pure-Dart
/// decoder recognises the format.
int? _probePixels(Uint8List bytes) {
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder == null) return null;
    final info = decoder.startDecode(bytes);
    if (info == null) return null;
    return info.width * info.height;
  } catch (_) {
    return null;
  }
}

img.Image _fit(img.Image source, int maxEdge) {
  final longest = math.max(source.width, source.height);
  if (longest <= maxEdge) return source;
  final scale = maxEdge / longest;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.cubic,
  );
}

/// Platform decoder, for the containers package:image does not parse.
Future<img.Image> _decodeWithEngine(Uint8List bytes, int maxEdge) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? frame;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final srcW = descriptor.width;
    final srcH = descriptor.height;
    if (srcW <= 0 || srcH <= 0) throw const ImageFormatException();

    var targetW = srcW;
    var targetH = srcH;
    final longest = math.max(srcW, srcH);
    if (longest > maxEdge) {
      final scale = maxEdge / longest;
      targetW = math.max(1, (srcW * scale).round());
      targetH = math.max(1, (srcH * scale).round());
    }

    codec = await descriptor.instantiateCodec(
        targetWidth: targetW, targetHeight: targetH);
    frame = (await codec.getNextFrame()).image;
    final data =
        await frame.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) throw const ImageFormatException();
    return img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: data.buffer,
      bytesOffset: data.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  } finally {
    frame?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

class _DecodeJob {
  const _DecodeJob(this.bytes, this.maxEdge);

  final Uint8List bytes;
  final int maxEdge;
}

/// RGBA frame that can cross an isolate boundary.
class _RawImage {
  const _RawImage(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

_RawImage? _decodeJob(_DecodeJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  final fitted = _fit(decoded, job.maxEdge);
  return _RawImage(fitted.getBytes(order: img.ChannelOrder.rgba),
      fitted.width, fitted.height);
}

class _DecodeBakeJob {
  const _DecodeBakeJob(this.bytes, this.maxEdge);

  final Uint8List bytes;
  final int maxEdge;
}

Uint8List? _decodeBakeJob(_DecodeBakeJob job) {
  final decoded = img.decodeImage(job.bytes);
  if (decoded == null) return null;
  return bakeJpeg(_fit(decoded, kMaxDecodeEdge), maxEdge: job.maxEdge);
}

class _BakeJob {
  const _BakeJob(this.rgba, this.width, this.height, this.maxEdge);

  final Uint8List rgba;
  final int width;
  final int height;
  final int maxEdge;
}

Uint8List _bakeJob(_BakeJob job) {
  final source = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    bytesOffset: job.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return bakeJpeg(source, maxEdge: job.maxEdge);
}

class _CropJob {
  const _CropJob(this.rgba, this.width, this.height, this.x, this.y, this.w,
      this.h, this.filter, this.maxEdge);

  final Uint8List rgba;
  final int width;
  final int height;
  final int x;
  final int y;
  final int w;
  final int h;
  final List<double>? filter;
  final int maxEdge;
}

Uint8List _cropBakeJob(_CropJob job) {
  final source = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: job.rgba.buffer,
    bytesOffset: job.rgba.offsetInBytes,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  final out =
      img.copyCrop(source, x: job.x, y: job.y, width: job.w, height: job.h);
  final filter = job.filter;
  if (filter != null) IedFilter.applyToImage(out, filter);
  return bakeJpeg(out, maxEdge: job.maxEdge);
}
