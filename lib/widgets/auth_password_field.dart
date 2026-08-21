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
    this.textInputAction,
    this.onFieldSubmitted,
    this.prefixIcon = FontAwesomeIcons.lock,
  });

  final TextEditingController controller;
  final String label;
  final FocusNode? focusNode;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
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
      decoration: InputDecoration(
        labelText: widget.label,
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
