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
    return Align(
      // A tight parent (the AppBar leading forces its full 48×56 slot onto
      // children) would stretch a bare Container into an ELLIPSE — the
      // reported bug ("image is oval, border only seen left and right").
      // Align fills the parent but hands the avatar LOOSE constraints, so
      // the Container's own width/height (size×size) always win. Under
      // unbounded constraints (feed rows) Align shrink-wraps to the child,
      // so every other avatar usage is untouched.
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
        // NO clipBehavior here — the ring must never be clipped by the
        // decoration's own clip path (that interplay is what renders square
        // borders on some devices). The image is clipped by ClipOval below.
        child: ClipOval(
          // The explicit SizedBox pins the image's LAYOUT box to exactly
          // size×size under ANY incoming constraints. Without it, an
          // Image with null width/height sizes itself to the image's own
          // aspect ratio whenever a parent hands down loose constraints —
          // a portrait avatar (the site stores raw photos: the dev
          // account's is 571x417) then renders as a TALL RECTANGLE inside
          // the circular clip: an oval that covers the ring top/bottom.
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
