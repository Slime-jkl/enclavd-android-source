import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cached_image.dart';
import 'shimmer.dart';

/// Network image with shimmer placeholder, display-size decode, asset fallback.
class EnclavdImage extends StatelessWidget {
  const EnclavdImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorAsset = 'assets/images/default-avatar.png',
    this.borderRadius,
    this.placeholderHeight,
    this.placeholderShape = BoxShape.rectangle,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String errorAsset;
  final BorderRadius? borderRadius;
  final double? placeholderHeight;

  /// Shimmer shape; avatars pass [BoxShape.circle].
  final BoxShape placeholderShape;

  @override
  Widget build(BuildContext context) {
    // Decode at display size x dpr, clamped: the biggest memory/jank win
    // for image-heavy feeds.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetWidth = (width ?? MediaQuery.sizeOf(context).width);
    final cacheWidth = (targetWidth * dpr).ceil().clamp(8, 2048);

    final image = Image(
      image: ResizeImage.resizeIfNeeded(
        cacheWidth,
        null,
        CachedNetworkImageProvider(url),
      ),
      width: width,
      height: height,
      fit: fit,
      // frameBuilder fires once the frame is decoded; shimmer until then,
      // then fade in.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: frame == null ? _placeholder() : child,
        );
      },
      errorBuilder: (context, error, stack) => _fallback(context),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _placeholder() {
    return ShimmerBox(
      width: width,
      height: placeholderHeight ?? height ?? 140,
      borderRadius: 8,
      shape: placeholderShape,
    );
  }

  Widget _fallback(BuildContext context) {
    // Site onerror parity: swap in a local asset instead of a bare icon.
    return Image.asset(
      errorAsset,
      width: width,
      height: placeholderHeight ?? height,
      fit: BoxFit.cover,
    );
  }
}

/// Shimmer placeholder shown while a full post-card image loads.
class EnclavdImagePlaceholder extends StatelessWidget {
  const EnclavdImagePlaceholder({
    super.key,
    this.height = 140,
    this.borderRadius = 8,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final w = math.min(MediaQuery.sizeOf(context).width - 56, 640.0);
    return ShimmerBox(width: w, height: height, borderRadius: borderRadius);
  }
}
