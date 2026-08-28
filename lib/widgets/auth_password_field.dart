import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';

import '../theme/enclavd_theme.dart';
import '../widgets/field_icon.dart';

/// Password input with a visibility toggle, shared by login/register.
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

  /// Server-side field error, cleared when the user edits.
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
        prefixIcon: FieldIcon(widget.prefixIcon),
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
