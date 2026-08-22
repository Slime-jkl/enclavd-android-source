import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';

/// Password input with a visibility toggle (eye / eye-slash suffix).
/// Shared by the login and register screens so the toggle behaves and
/// looks identical everywhere.
class AuthPasswordField extends StatefulWidget {
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
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;

  /// Server-side error for this field (api/v1 register field errors),
  /// shown below the input until the user edits it away (the owner
  /// clears the error from its own state in [onChanged]).
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final FaIconData prefixIcon;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        prefixIcon: FaIcon(widget.prefixIcon, size: 18),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscure = !_obscure),
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: FaIcon(
            _obscure ? FontAwesomeIcons.eye : FontAwesomeIcons.eyeSlash,
            size: 18,
            color: EnclavdColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
