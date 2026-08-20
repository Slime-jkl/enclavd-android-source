import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cached_image.dart';
import 'shimmer.dart';

/// Network image with the app's loading discipline:
///  - shows a shimmer placeholder until the image bytes are FULLY fetched
///    and the first frame is decoded (never a partial/blank flash);
///  - fades the real image in once it's ready;
///  - decodes at display size (cacheWidth) instead of full resolution —
///    avatars are served full-size, so without this a 35px avatar decodes a
///    500px image into memory on every card (the feed's scroll-jank cause);
///  - falls back to an asset on error, mirroring the site's onerror
///    handlers (avatar → default-avatar.png, post image → no-image.jpg).
///
/// Backed by CachedNetworkImageProvider (disk cache), so repeat views and
/// cold starts don't re-download the same bytes.
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
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String errorAsset;
  final BorderRadius? borderRadius;
  final double? placeholderHeight;

  @override
  Widget build(BuildContext context) {
    // Decode at display size × device pixel ratio, clamped to a sane
    // maximum — the single biggest memory/jank win for image-heavy feeds.
    // ResizeImage wraps the provider so decoding happens at display size
    // (the raw cached bytes stay full-res on disk; memory gets the small one).
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
      // frameBuilder fires once the frame is actually decoded — render the
      // shimmer until then, fade in after.
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
    );
  }

  Widget _fallback(BuildContext context) {
    // Same as the site's onerror: swap in a local asset (default avatar for
    // avatars, no-image.jpg for post images) instead of a bare icon.
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
