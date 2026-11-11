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
    this.shimmer = true,
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

  /// Off for marks that must not flash a block (logos): the space is held
  /// empty until the first frame decodes.
  final bool shimmer;

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
      // frameBuilder fires once the frame is decoded. Until then the
      // placeholder must stay *visible* (it used to fade from opacity 0,
      // which is why a slow image looked like an empty white/black gap);
      // once the frame lands the skeleton fades out and the image fades in.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: frame == null
              ? KeyedSubtree(
                  key: const ValueKey('enclavd-image-placeholder'),
                  child: shimmer
                      ? _placeholder()
                      : SizedBox(
                          width: width,
                          height: placeholderHeight ?? height,
                        ),
                )
              : KeyedSubtree(
                  key: const ValueKey('enclavd-image-frame'),
                  child: child,
                ),
        );
      },
      errorBuilder: (context, error, stack) => _fallback(context),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _placeholder() {
    // Fill whichever dimension the caller left to the layout. Call sites like
    // the article hero/cover pass no width/height and rely on their parent
    // SizedBox, so a fixed 140px block would leave a visible gap while the
    // bitmap downloads.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = width ??
            (constraints.maxWidth.isFinite ? constraints.maxWidth : null);
        final h = placeholderHeight ??
            height ??
            (constraints.maxHeight.isFinite ? constraints.maxHeight : 140);
        return ShimmerBox(
          width: w,
          height: h,
          borderRadius: 8,
          shape: placeholderShape,
        );
      },
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
