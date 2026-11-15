import 'package:flutter/widgets.dart';

/// Shared motion vocabulary. Screens should not invent their own durations,
/// curves or looping animation controllers - use these so every transition
/// in the app feels like it belongs to the same product.
class AppMotion {
  const AppMotion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 420);

  /// Ambient loops (hero backgrounds).
  static const Duration drift = Duration(seconds: 9);
  static const Duration breath = Duration(milliseconds: 1400);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeInOutCubic;
  static const Curve spring = Curves.easeOutBack;

  /// True when the platform asks for reduced motion; ambient animation
  /// should render a single static frame instead of looping.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}
