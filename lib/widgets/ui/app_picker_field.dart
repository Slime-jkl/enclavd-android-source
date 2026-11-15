import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import '../field_icon.dart';

/// Tap-to-pick form field that mirrors [AppInputField]'s decoration.
///
/// Picker values are chosen from a sheet rather than typed, so this is an
/// [InputDecorator] instead of a [TextFormField]. The whole field is the tap
/// target and the trailing chevron signals that a sheet will open.
class AppPickerField extends StatelessWidget {
  const AppPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.hintText = 'Select',
    this.prefixIcon,
    this.enabled = true,
  });

  final String label;

  /// Current selection; empty means nothing has been picked yet.
  final String value;
  final VoidCallback onTap;
  final String hintText;
  final FaIconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final empty = value.isEmpty;

    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label, ${empty ? hintText : value}',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: prefixIcon == null ? null : FieldIcon(prefixIcon!),
            suffixIcon: FieldIcon(
              FontAwesomeIcons.chevronDown,
              size: 13,
              color: palette.textSecondary,
            ),
            enabled: enabled,
          ),
          // Match AppInputField: while nothing is picked the label rests
          // inside the field; once picked the label floats and the value shows.
          isEmpty: empty,
          child: empty
              ? const SizedBox(width: double.infinity)
              : Text(
                  value,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                  ),
                ),
        ),
      ),
    );
  }
}
