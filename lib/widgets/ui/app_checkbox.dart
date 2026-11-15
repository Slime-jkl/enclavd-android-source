import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';

/// The app's checkbox row: an 18px box, a label, and a 44px tap target.
///
/// The check is centred in the box (a bare `FaIcon` in a fixed-size container
/// would otherwise sit top-left), and the whole row toggles it.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? semanticLabel;

  bool get _enabled => onChanged != null;

  void _toggle() {
    HapticFeedback.selectionClick();
    onChanged!(!value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final enabled = _enabled;
    final fill = enabled
        ? palette.primaryButton
        : palette.primaryButton.withValues(alpha: 0.45);
    final text = enabled
        ? palette.textPrimary
        : palette.textSecondary.withValues(alpha: 0.6);

    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      checked: value,
      enabled: enabled,
      onTap: enabled ? _toggle : null,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? _toggle : null,
          enableFeedback: false,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.enter,
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value ? fill : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: value ? fill : palette.border,
                        width: 1.5,
                      ),
                    ),
                    child: value
                        ? FaIcon(
                            FontAwesomeIcons.check,
                            size: 10,
                            color: palette.primaryButtonText,
                          )
                        : null,
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      label!,
                      style: TextStyle(color: text, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
