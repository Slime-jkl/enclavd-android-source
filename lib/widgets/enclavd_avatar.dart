import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import 'enclavd_image.dart';

class EnclavdAvatar extends StatelessWidget {
  const EnclavdAvatar({
    super.key,
    required this.size,
    required this.url,
    this.borderColor,
    this.fit = BoxFit.cover,
    this.square = false,
  });

  final double size;

  /// Resolved media URL (pass through resolveMediaUrl)
  final String url;

  /// Personality accent for the ring ==> null falls back to the theme border
  final Color? borderColor;

  final BoxFit fit;

  final bool square;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.28);
    // Factors pin the box to the avatar size: a plain Align expands to
    // fill bounded heights (rows inside IntrinsicHeight/stretch), which
    // floats the avatar mid-row on multi-line items. Parents align it.
    return Align(
      alignment: Alignment.center,
      widthFactor: 1,
      heightFactor: 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? radius : null,
          color: EnclavdColors.cardSecondary,
          border: Border.all(
            color: borderColor ?? EnclavdColors.border,
            width: 2,
          ),
        ),
        child: square
            ? ClipRRect(
                borderRadius: radius,
                child: _image(),
              )
            : ClipOval(child: _image()),
      ),
    );
  }

  Widget _image() {
    return SizedBox(
      width: size,
      height: size,
      child: EnclavdImage(
        url,
        fit: fit,
        width: size,
        height: size,
        placeholderShape: square ? BoxShape.rectangle : BoxShape.circle,
      ),
    );
  }
}
