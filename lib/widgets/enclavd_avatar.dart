import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import 'enclavd_image.dart';

/// Circular avatar with a colored ring (the app's avatar primitive).
class EnclavdAvatar extends StatelessWidget {
  const EnclavdAvatar({
    super.key,
    required this.size,
    required this.url,
    this.borderColor,
    this.fit = BoxFit.cover,
  });

  final double size;

  /// Resolved media URL (pass through resolveMediaUrl).
  final String url;

  /// Personality accent for the ring; null falls back to the theme border.
  final Color? borderColor;

  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Align(
      // Align hands the avatar loose constraints so a tight parent can't
      // stretch it into an ellipse.
      alignment: Alignment.center,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: EnclavdColors.cardSecondary,
          border: Border.all(
            color: borderColor ?? EnclavdColors.border,
            width: 2,
          ),
        ),
        // No clipBehavior on the ring (clipped borders render square on
        // some devices); ClipOval clips the image.
        child: ClipOval(
          // The SizedBox pins the layout box to sizexsize; without it a
          // portrait image stretches into a tall rectangle.
          child: SizedBox(
            width: size,
            height: size,
            child: EnclavdImage(
              url,
              fit: fit,
              width: size,
              height: size,
              placeholderShape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
