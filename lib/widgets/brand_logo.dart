import 'package:flutter/material.dart';

import '../services/branding_service.dart';
import 'enclavd_image.dart';

/// App wordmark: the site's seasonal art when one is live, else the
/// bundled asset for the current brightness.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 22});

  /// Height of the bundled wordmark, in logical pixels.
  final double height;

  /// The bundled mark is a wide lockup (1584x231). Served seasonal art can be
  /// any ratio, so it is fitted inside the same width and up to twice this
  /// height — never stretched or clipped by a fixed height alone.
  static const _wordmarkAspect = 1584 / 231;

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
        if (url == null) {
          return Image.asset(asset, height: height, fit: BoxFit.contain);
        }
        final width = height * _wordmarkAspect;
        return SizedBox(
          width: width,
          height: height * 2,
          child: EnclavdImage(
            url,
            width: width,
            height: height * 2,
            fit: BoxFit.contain,
            errorAsset: asset,
            shimmer: false,
          ),
        );
      },
    );
  }
}
