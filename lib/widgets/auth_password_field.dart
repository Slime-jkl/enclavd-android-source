import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import 'ui/app_input_field.dart';

/// Password input with a visibility toggle, shared by login/register.
class AuthPasswordField extends StatelessWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.focusNode,
    this.validator,
    this.errorText,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.prefixIcon = FontAwesomeIcons.lock,
    this.enabled = true,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;

  /// Server-side field error, cleared when the user edits.
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final FaIconData prefixIcon;

  /// Disables the input (and its toggle) while a submit is in flight.
  final bool enabled;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return AppInputField(
      controller: controller,
      label: label,
      focusNode: focusNode,
      validator: validator,
      errorText: errorText,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onChanged: onChanged,
      prefixIcon: prefixIcon,
      enabled: enabled,
      autofillHints: autofillHints,
      obscureText: true,
      showObscureToggle: true,
    );
  }
}
