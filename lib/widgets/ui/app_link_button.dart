import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'expanded_tap_area.dart';

/// A text-only action, e.g. "Forgot password?" or "Create an account".
///
/// It looks like a plain link: no pill, ripple, hover tint or press animation.
/// The tappable area is deliberately much larger than the text (44px tall and
/// a transparent 36px/12px overlay on top) but completely invisible, so
/// near-misses still land without the link moving its neighbours. On pages
/// that can scroll the overlay is suppressed so drags still scroll.
class AppLinkButton extends StatelessWidget {
  const AppLinkButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fontSize = 13,
  });

  final String label;
  final VoidCallback? onPressed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ExpandedTapArea(
      onTap: onPressed,
      horizontalPadding: 36,
      verticalPadding: 12,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: context.enclavd.link,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          animationDuration: Duration.zero,
          enableFeedback: false,
          shape: const RoundedRectangleBorder(),
        ),
        child: Text(label, style: TextStyle(fontSize: fontSize)),
      ),
    );
  }
}
