import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/enclavd_theme.dart';
import 'app_motion.dart';

enum AppButtonVariant { primary, secondary, ghost, danger }

enum AppButtonSize { medium, small }

/// The one button in the app.
///
/// Pill buttons, bare `TextButton`s and one-off `FilledButton`s should not be
/// introduced any more - pick a variant here so radius, height, padding and
/// the loading treatment stay identical everywhere.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.trailing,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final FaIconData? icon;
  final bool loading;
  final bool expand;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  @override
  void didUpdateWidget(covariant AppButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A tap can disable the button (e.g. loading) before the pointer lifts;
    // drop stale interaction state so it doesn't stay pressed-looking.
    if (!_enabled) {
      _hovered = false;
      _pressed = false;
    }
  }

  void _handleTap() {
    widget.onPressed!();
  }

  /// Haptics land on touch-down so the press is acknowledged immediately, even
  /// if the tap ends up failing validation before it ever reaches onTap.
  void _setPressed(bool pressed) {
    if (pressed == _pressed) return;
    if (pressed) HapticFeedback.lightImpact();
    setState(() => _pressed = pressed);
  }

  Color _hoverColor(EnclavdPalette palette, Color base) {
    return switch (widget.variant) {
      AppButtonVariant.primary => palette.primaryButtonHover,
      AppButtonVariant.secondary => Color.lerp(base, Colors.white, 0.06)!,
      AppButtonVariant.ghost => palette.cardSecondary.withValues(alpha: 0.55),
      AppButtonVariant.danger => Color.lerp(base, Colors.black, 0.08)!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final height = widget.size == AppButtonSize.medium ? 44.0 : 34.0;
    final fontSize = widget.size == AppButtonSize.medium ? 14.0 : 12.5;

    late Color background;
    late Color foreground;
    Border? border;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        background = palette.primaryButton;
        foreground = palette.primaryButtonText;
      case AppButtonVariant.secondary:
        background = palette.cardSecondary;
        foreground = palette.textPrimary;
        border = Border.all(color: palette.border);
      case AppButtonVariant.ghost:
        background = Colors.transparent;
        foreground = palette.textSecondary;
      case AppButtonVariant.danger:
        background = palette.error;
        foreground = Colors.white;
    }

    if (!_enabled) {
      background = background.withValues(alpha: 0.45);
      foreground = foreground.withValues(alpha: 0.6);
    } else {
      final hovered = _hoverColor(palette, background);
      if (_hovered) background = hovered;
      if (_pressed) {
        background = Color.lerp(background, Colors.black, 0.18)!;
      }
    }

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(foreground),
              ),
            ),
          )
        else if (widget.icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FaIcon(widget.icon!, size: fontSize, color: foreground),
          ),
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ),
        if (widget.trailing != null) widget.trailing!,
      ],
    );

    final button = AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.enter,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: widget.size == AppButtonSize.medium ? 16 : 12,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Center(widthFactor: 1, child: content),
    );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel ?? widget.label,
      child: InkWell(
        onTap: _enabled ? _handleTap : null,
        onHover:
            _enabled ? (hovered) => setState(() => _hovered = hovered) : null,
        onHighlightChanged: _enabled ? _setPressed : null,
        borderRadius: BorderRadius.circular(10),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        enableFeedback: false,
        child: AnimatedScale(
          scale: _enabled && _pressed ? 0.97 : 1,
          duration: _pressed ? AppMotion.instant : AppMotion.fast,
          curve: _pressed ? AppMotion.exit : AppMotion.emphasized,
          child: widget.expand
              ? SizedBox(width: double.infinity, child: button)
              : button,
        ),
      ),
    );
  }
}

/// A square icon-only button using the same chrome as [AppButton].
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    this.variant = AppButtonVariant.ghost,
  });

  final FaIconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final palette = context.enclavd;
    final color = variant == AppButtonVariant.ghost
        ? palette.textSecondary
        : palette.textPrimary;
    final background = switch (variant) {
      AppButtonVariant.primary => palette.primaryButton,
      AppButtonVariant.secondary => palette.cardSecondary,
      AppButtonVariant.danger => palette.error,
      AppButtonVariant.ghost => Colors.transparent,
    };
    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: FaIcon(
          icon,
          size: size * 0.42,
          color: variant == AppButtonVariant.primary
              ? palette.primaryButtonText
              : color,
        ),
      ),
    );
    final tappable = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: child,
    );
    return tooltip == null
        ? tappable
        : Tooltip(message: tooltip!, child: tappable);
  }
}
