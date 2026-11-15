import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/enclavd_theme.dart';
import 'app_button.dart';
import 'app_motion.dart';

/// The app's dialog: card surface, 14 radius, title + message + action row.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required Widget content,
  String? confirmLabel,
  String? cancelLabel,
  bool confirmLoading = false,
  bool barrierDismissible = true,
  required FutureOr<bool> Function(BuildContext context) onConfirm,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _AppDialogHost<T>(
      title: title,
      message: message,
      content: content,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmLoading: confirmLoading,
      onConfirm: onConfirm,
    ),
  );
}

typedef BoolCallback = FutureOr<bool> Function(BuildContext context);

class _AppDialogHost<T> extends StatefulWidget {
  const _AppDialogHost({
    required this.title,
    required this.message,
    required this.content,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.confirmLoading,
    required this.onConfirm,
  });

  final String title;
  final String? message;
  final Widget content;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool confirmLoading;
  final BoolCallback onConfirm;

  @override
  State<_AppDialogHost<T>> createState() => _AppDialogHostState<T>();
}

class _AppDialogHostState<T> extends State<_AppDialogHost<T>> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await Future<bool>.sync(() => widget.onConfirm(context));
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.message!,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 14),
            widget.content,
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: widget.cancelLabel ?? 'Cancel',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.small,
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: widget.confirmLabel ?? 'Save',
                  size: AppButtonSize.small,
                  loading: _busy || widget.confirmLoading,
                  onPressed: _confirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-line text input styled for dialogs.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hintText,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      autofocus: autofocus,
      keyboardType: keyboardType,
      cursorColor: palette.link,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
        counterStyle: TextStyle(color: palette.textSecondary, fontSize: 11),
        filled: true,
        fillColor: palette.cardSecondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: palette.link),
        ),
      ),
    );
  }
}

/// Fade+scale entrance used by overlays that are not route-driven.
class AppOverlayEnter extends StatelessWidget {
  const AppOverlayEnter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: value, child: child),
      ),
    );
  }
}
