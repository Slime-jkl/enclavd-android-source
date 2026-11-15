import 'package:flutter/painting.dart';

/// Shared type scale.
///
/// Heading levels match the website's, so screens reuse one deliberate size
/// instead of hand-rolling another "big bold" style. Colour is applied by the
/// caller from the active palette.
abstract final class AppTypography {
  /// H3: auth headlines and section titles. Deliberately smaller than the
  /// brand mark so the logo stays the loudest thing on a signed-out screen.
  static const h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.2,
  );
}
