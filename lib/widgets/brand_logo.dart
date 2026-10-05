import 'package:flutter/material.dart';

import '../services/branding_service.dart';
import 'enclavd_image.dart';

/// App wordmark: the site's seasonal art when one is live, else the
/// bundled asset for the current brightness.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 22});

  final double height;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final asset = light
        ? 'assets/images/enclavd-logo-dark.png'
        : 'assets/images/enclavd-logo-white.png';
    final served = light
        ? BrandingService.instance.wordmarkLight
        : BrandingService.instance.wordmark;
    return ValueListenableBuilder<String?>(
      valueListenable: served,
      builder: (context, path, _) {
        final url = BrandingService.resolveUrl(path);
        if (url == null) return Image.asset(asset, height: height);
        // The seasonal art carries decoration above and below the letters, so
        // it needs about twice the wordmark's height to read at the same size.
        return EnclavdImage(
          url,
          height: height * 2,
          fit: BoxFit.contain,
          errorAsset: asset,
          shimmer: false,
        );
      },
    );
  }
}
