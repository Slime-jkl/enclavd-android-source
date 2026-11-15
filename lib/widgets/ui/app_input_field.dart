import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import '../field_icon.dart';

/// Standard form input used across the app.
///
/// Owns the shared label/hint/icon layout, disabled state, validation error
/// slot and the optional password visibility toggle. Colours and the recessed
/// fill come from [ThemeData.inputDecorationTheme] so every form field reads
/// the same without repeating decoration code.
class AppInputField extends StatefulWidget {
  const AppInputField({
    super.key,
    required this.controller,
    required this.label,
    this.hintText,
    this.prefixIcon,
    this.focusNode,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.validator,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.obscureText = false,
    this.showObscureToggle = false,
    this.onFieldSubmitted,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;

  /// Icon rendered in the 48px leading slot.
  final FaIconData? prefixIcon;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;

  /// Server-side field error, cleared by the caller as the user edits.
  final String? errorText;

  /// Steady guidance below the field; hidden while [errorText] is showing.
  final String? helperText;
  final bool enabled;
  final bool obscureText;

  /// Adds the eye/eye-slash suffix and hides the text while [_obscure] is on.
  final bool showObscureToggle;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;
  final int maxLines;

  @override
  State<AppInputField> createState() => _AppInputFieldState();
}

class _AppInputFieldState extends State<AppInputField> {
  late bool _obscure = widget.obscureText;

  @override
  void didUpdateWidget(AppInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.obscureText != oldWidget.obscureText) {
      _obscure = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final hasToggle = widget.showObscureToggle;

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: widget.obscureText && _obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        prefixIcon:
            widget.prefixIcon == null ? null : FieldIcon(widget.prefixIcon!),
        suffixIcon: hasToggle
            ? IconButton(
                onPressed: widget.enabled
                    ? () => setState(() => _obscure = !_obscure)
                    : null,
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: FaIcon(
                  _obscure ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
                  size: 18,
                  color: palette.textSecondary,
                ),
              )
            : null,
      ),
    );
  }
}
