import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import 'enclavd_image.dart';

/// Circular avatar — the app's single avatar primitive (feed author rows,
/// comments, likers, profile header).
///
/// Bulletproof circle pattern: the colored ring is a plain BoxDecoration
/// with NO clipBehavior (a clipped circle border is the classic source of
/// "borders cut off at the corners" GPU artifacts), and the image itself
/// is clipped by an explicit [ClipOval] — the most direct circular clip
/// in Flutter. The loading shimmer is also circular, so an avatar never
/// shows a square while its image loads.
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
    return Container(
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
      // NO clipBehavior here — the ring must never be clipped by the
      // decoration's own clip path (that interplay is what renders square
      // borders on some devices). The image is clipped by ClipOval below.
      child: ClipOval(
        child: EnclavdImage(
          url,
          fit: fit,
          placeholderShape: BoxShape.circle,
        ),
      ),
    );
  }
}
