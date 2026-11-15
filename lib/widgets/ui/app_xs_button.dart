import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';
import 'expanded_tap_area.dart';

/// The intent of an [AppXsButton].
enum AppXsButtonTone {
  /// A primary action, e.g. "OK" in a picker footer.
  primary,

  /// A quiet action, e.g. "Cancel".
  neutral,
}

/// An extra-small text action, e.g. the Cancel/OK pair in a picker footer.
///
/// Deliberately much smaller than [AppButton] (28px tall, 12px label) so it
/// can sit inside sheets and dialogs without competing with the content. The
/// tappable area is far larger than the text: a transparent overlay extends
/// 16x12px around it, exactly like [AppLinkButton], while a subtle pressed
/// tint and a light haptic confirm the touch.
class AppXsButton extends StatelessWidget {
  const AppXsButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.tone = AppXsButtonTone.primary,
  });

  static const double height = 28;

  final String label;
  final VoidCallback? onPressed;
  final FaIconData? icon;
  final AppXsButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final enabled = onPressed != null;
    final color =
        tone == AppXsButtonTone.neutral ? palette.textSecondary : palette.link;
    final dimmed = enabled ? color : color.withValues(alpha: 0.4);

    return ExpandedTapArea(
      onTap: onPressed,
      horizontalPadding: 16,
      verticalPadding: 12,
      coverChild: false,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  }
                : null,
            borderRadius: BorderRadius.circular(7),
            overlayColor: WidgetStatePropertyAll(
              color.withValues(alpha: 0.12),
            ),
            splashFactory: NoSplash.splashFactory,
            enableFeedback: false,
            child: AnimatedContainer(
              duration: AppMotion.instant,
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: enabled
                      ? color.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    FaIcon(icon, size: 10.5, color: dimmed),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: dimmed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
